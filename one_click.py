#!/usr/bin/env python3
"""一键：建仓 -> 云端编译 -> 下载 IPA -> 交给侧载工具。

只把三件必须由本人完成的事留给你：
  1) 一个 GitHub PAT（脚本用 getpass 输入，不回显、不写盘、不经过对话）
  2) 在 Sideloadly 里输入你自己的 Apple ID（密码绝不经过我）
  3) 手机上点「信任开发者」

用法：
    python3 one_click.py
  或双击同目录的 一键安装.command

前置：仓库需为公开（公开仓库 macOS runner 免费且不限时长）。
"""
import argparse
import base64
import getpass
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.github.com"
WORKFLOW = "unsigned-ipa.yml"
ARTIFACT = "KuXuan-unsigned-IPA"
SKIP_DIRS = {".git", "__pycache__", ".idea", ".vscode", "build"}
SKIP_FILES = {".DS_Store"}
# 注意：不能排除 .png —— KuXuan/Resources/icon.png 是前端引用的资源，
# 排除后编译出的 App 里 favicon 会 404。
SKIP_EXT = {".pyc", ".zip", ".ipa", ".xcarchive", ".dmg"}


class APIError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def req(method, path, token, payload=None, raw=False):
    url = API + path
    body = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "kuxuan-oneclick",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            data = resp.read()
            return data if raw else (json.loads(data) if data else {})
    except urllib.error.HTTPError as e:
        raise APIError(e.code, e.read().decode("utf-8", "replace")[:400])
    except urllib.error.URLError as e:
        raise APIError(0, "网络错误：%s" % e.reason)


def collect(src):
    out = []
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name in SKIP_FILES or os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            full = os.path.join(root, name)
            out.append((os.path.relpath(full, src).replace(os.sep, "/"), full))
    return sorted(out)


def upload(token, owner, full_name, src):
    # 确认仓库存在且可访问（空仓库由 upload_or_build 换仓处理）
    try:
        req("GET", "/repos/%s" % full_name, token)
        print("  仓库可访问，开始推送：https://github.com/%s" % full_name)
    except APIError as e:
        raise APIError(e.code,
            "无法访问仓库 %s（HTTP %s）。请确认仓库已建好且令牌有 repo 权限。" % (full_name, e.code))

    # GitHub Contents API 会自动创建多级目录，直接对每个文件 PUT 即可。
    files = collect(src)
    n = 0
    for rel, full in files:
        # 账号策略禁止通过 API 写入 .github/workflows/，该文件需用户到网页手动创建
        if rel.startswith(".github/workflows/"):
            print("  ⏭️ 跳过 %s（API 禁止写入 .github/workflows，请到 GitHub 网页手动创建）" % rel)
            continue
        # URL 中的路径需做 percent-encoding（文件名可能含中文/空格）
        rel_q = urllib.parse.quote(rel, safe="/")
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        # 若文件已存在则取 sha 以便覆盖（支持重复上传）
        sha = None
        try:
            r = req("GET", "/repos/%s/contents/%s" % (full_name, rel_q), token)
            sha = r.get("sha")
        except APIError:
            pass
        body = {"message": "add " + rel, "content": content}
        if sha:
            body["sha"] = sha
        req("PUT", "/repos/%s/contents/%s" % (full_name, rel_q), token, body)
        n += 1
        print("  ↑ %s" % rel)
    print("  ✅ 上传完成（推送 %d 个文件；.github/workflows/* 需你手动在网页创建）" % n)


def _wait_main(token, full_name, timeout=90):
    """auto_init 建仓后会异步初始化默认分支；轮询等待 main 的 ref 就绪，
    避免在空仓库/未就绪仓库上 Contents API 返回 404。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req("GET", "/repos/%s/git/ref/heads/main" % full_name, token)
            return
        except APIError:
            time.sleep(2)
    print("  ⚠️ 等待默认分支就绪超时，仍尝试推送")


def upload_or_build(token, owner, repo, src):
    """推送工程；处理两种特殊情况：
       - 仓库不存在：自动建仓（auto_init 初始化默认分支）后推送
       - 仓库存在但是空仓库：API 无法写入（404/409），自动改用 <repo>-unsigned 建新仓推送
       返回最终使用的 full_name。"""
    full = "%s/%s" % (owner, repo)
    # 1) 探测仓库是否存在
    try:
        req("GET", "/repos/%s" % full, token)
        exists = True
    except APIError as e:
        if e.code == 404:
            exists = False
        else:
            raise
    # 2) 不存在 → 建仓（auto_init 会初始化默认分支，避免空仓库 409）
    if not exists:
        print("  仓库不存在，自动建仓：https://github.com/%s" % full)
        req("POST", "/user/repos", token, {
            "name": repo, "description": "KuXuan iOS music player (unsigned build)",
            "private": False, "auto_init": True,
            "has_issues": False, "has_wiki": False, "has_projects": False})
    # auto_init 异步初始化默认分支；轮询等待 main 就绪
    _wait_main(token, full)
    # 3) 尝试推送；空仓库仍会 404/409，则改用新仓库名重建
    try:
        upload(token, owner, full, src)
        return full
    except APIError as e:
        if e.code not in (404, 409) or not exists:
            raise
        new_repo = repo + "-ci"
        new_full = "%s/%s" % (owner, new_repo)
        print("  ⚠️ %s 无法写入；改用 %s（自动建仓+初始化）" % (full, new_full))
        try:
            req("POST", "/user/repos", token, {"name": new_repo, "private": False, "auto_init": True})
        except APIError as ce:
            if ce.code != 422:  # 422 = 已存在，直接复用即可
                raise
        _wait_main(token, new_full)
        upload(token, owner, new_full, src)
        return new_full


def wait_run(token, full_name, timeout=2400):
    print("\n[3/4] 等待云端编译（通常 5–15 分钟）...")
    try:
        req("POST", "/repos/%s/actions/workflows/%s/dispatches" % (full_name, WORKFLOW),
            token, {"ref": "main"})
    except APIError as e:
        if e.code == 404:
            print("❌ 找不到 workflow 文件 .github/workflows/%s。" % WORKFLOW)
            print("   请先到 GitHub 网页手动创建该文件（内容见对话），再运行一次本脚本即可自动编译+下载。")
            return None, "need_workflow"
        raise
    started = time.time()
    target = None
    last = ""
    while time.time() - started < timeout:
        try:
            runs = req("GET", "/repos/%s/actions/runs?event=workflow_dispatch&per_page=5" % full_name,
                       token).get("workflow_runs", [])
            if runs:
                r = runs[0]
                target = r["id"]
                state = "%s / %s" % (r["status"], r.get("conclusion") or "-")
                if state != last:
                    print("    %s  (run %s)" % (state, target))
                    last = state
                if r["status"] == "completed":
                    return target, r.get("conclusion")
        except APIError as e:
            print("    查询中（%s）" % e.code)
        time.sleep(20)
    return target, "timeout"


def fetch_logs(token, full_name, run_id):
    try:
        jobs = req("GET", "/repos/%s/actions/runs/%s/jobs?per_page=10" % (full_name, run_id),
                   token).get("jobs", [])
        for j in jobs:
            for s in j.get("steps", []):
                if s.get("conclusion") == "failure":
                    print("  ❌ 失败步骤：%s（第 %s 步）" % (s["name"], s["number"]))
        print("  完整日志：https://github.com/%s/actions/runs/%s" % (full_name, run_id))
    except APIError as e:
        print("  日志读取失败：%s" % e.code)


def download_ipa(token, full_name, run_id):
    print("\n[4/4] 下载编译产物...")
    arts = req("GET", "/repos/%s/actions/runs/%s/artifacts" % (full_name, run_id),
               token).get("artifacts", [])
    art = next((a for a in arts if a["name"] == ARTIFACT and not a.get("expired")), None)
    if not art:
        raise RuntimeError("未找到 artifact %s（可能编译未产出文件）" % ARTIFACT)

    r = urllib.request.Request(art["archive_download_url"], headers={
        "Authorization": "Bearer " + token, "User-Agent": "kuxuan-oneclick"})
    with urllib.request.urlopen(r, timeout=180) as resp:
        data = resp.read()
    z = zipfile.ZipFile(io.BytesIO(data))
    ipa = next((n for n in z.namelist() if n.lower().endswith(".ipa")), None)
    if not ipa:
        raise RuntimeError("artifact 内没有 .ipa：%s" % z.namelist()[:10])
    dest = os.path.expanduser("~/Downloads/KuXuan-unsigned.ipa")
    with open(dest, "wb") as f:
        f.write(z.read(ipa))
    size = os.path.getsize(dest) / 1024 / 1024
    print("  ✅ IPA 已就位：%s (%.1f MB)" % (dest, size))
    return dest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    ap.add_argument("--repo", default="kuxuan-ios")
    ap.add_argument("--src", default=HERE)
    args = ap.parse_args()

    token = args.token
    if not token:
        print("需要 GitHub PAT（repo 权限）。在 https://github.com/settings/tokens 生成。")
        print("输入不会回显，也不会保存到文件。\n")
        try:
            token = getpass.getpass("GitHub PAT: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消"); return 2
    if not token:
        print("未输入 token"); return 2

    print("\n[1/4] 校验 GitHub 账号")
    try:
        owner = req("GET", "/user", token)["login"]
    except APIError as e:
        print("❌ token 无效（HTTP %s）：%s" % (e.code, e.message)); return 1
    full_name = "%s/%s" % (owner, args.repo)
    print("  ✅ %s" % owner)

    print("\n[2/4] 上传工程")
    try:
        full_name = upload_or_build(token, owner, args.repo, args.src)
    except APIError as e:
        print("❌ 上传失败（HTTP %s）：%s" % (e.code, e.message)); return 1
    print("  目标仓库：https://github.com/%s" % full_name)

    run_id, conclusion = wait_run(token, full_name)
    if conclusion == "need_workflow":
        return 1
    if conclusion != "success":
        print("\n❌ 编译未成功：%s" % conclusion)
        if run_id:
            fetch_logs(token, full_name, run_id)
            print("\n把上面失败步骤或日志贴给我，我来改工程后重跑。")
        return 1

    try:
        ipa = download_ipa(token, full_name, run_id)
    except Exception as e:
        print("❌ 下载失败：%s" % e); return 1

    print("\n" + "=" * 56)
    print("IPA 已生成，接下来两步必须你本人完成：")
    print("  1. 打开 Sideloadly，拖入 %s" % ipa)
    print("  2. 输入你自己的 Apple ID → Start（手机需保持 USB 连接）")
    print("  3. 手机：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID")
    print("=" * 56)
    for app in ("Sideloadly", "AltServer"):
        p = "/Applications/%s.app" % app
        if os.path.isdir(p):
            subprocess.run(["open", "-a", p, ipa], check=False)
            print("已尝试用 %s 打开 IPA" % app)
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
