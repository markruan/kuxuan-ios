#!/usr/bin/env python3
"""把本目录上传成一个 GitHub 仓库，用于触发云端编译。

为什么需要它：这台 Mac 的 git / gh 都不可用（Command Line Tools 损坏），
所以改用 GitHub REST API 逐文件提交，完全绕开本地 git。

用法：
    python3 upload_to_github.py --token ghp_xxxxxxxxxxxx
    python3 upload_to_github.py --token ... --repo kuxuan-ios --private

token 需要 repo 权限（classic PAT 勾 repo，或 fine-grained PAT 勾 Contents 读写）。
建议用公开仓库：公开仓库的 macOS runner 免费，私有仓库按 10 倍系数扣分钟数。
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
SKIP_DIRS = {".git", "__pycache__", ".idea", ".vscode"}
SKIP_FILES = {".DS_Store"}
SKIP_EXT = {".pyc", ".zip", ".ipa", ".xcarchive"}


class APIError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def request(method, path, token, payload=None):
    url = API + path
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "kuxuan-uploader",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        raise APIError(e.code, detail)
    except urllib.error.URLError as e:
        raise APIError(0, "网络错误：%s" % e.reason)


def collect(src):
    result = []
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name in SKIP_FILES:
                continue
            if os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src).replace(os.sep, "/")
            result.append((rel, full))
    return sorted(result)


def main():
    ap = argparse.ArgumentParser(description="上传 KuXuan 原生工程到 GitHub")
    ap.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"), help="GitHub PAT")
    ap.add_argument("--repo", default="kuxuan-ios", help="仓库名")
    ap.add_argument("--private", action="store_true", help="建私有仓库（会消耗 Actions 分钟数）")
    ap.add_argument("--src", default=os.path.dirname(os.path.abspath(__file__)))
    args = ap.parse_args()

    if not args.token:
        print("错误：请提供 --token，或设置 GITHUB_TOKEN 环境变量")
        sys.exit(2)

    try:
        me = request("GET", "/user", args.token)
    except APIError as e:
        print("token 校验失败（HTTP %s）：%s" % (e.code, e.message))
        sys.exit(1)
    owner = me.get("login")
    print("已认证为：%s" % owner)

    repo_name = args.repo
    full_name = "%s/%s" % (owner, repo_name)
    try:
        created = request("POST", "/user/repos", args.token, {
            "name": repo_name,
            "description": "KuXuan - 自用 iOS 音乐播放器（原生壳 + 本地曲库）",
            "private": args.private,
            "auto_init": True,
            "has_issues": False,
            "has_wiki": False,
            "has_projects": False,
        })
        print("已创建仓库：%s" % created.get("html_url"))
    except APIError as e:
        if e.code == 422:
            print("仓库 %s 已存在，继续上传（同名文件会被覆盖）" % full_name)
        else:
            print("创建仓库失败（HTTP %s）：%s" % (e.code, e.message))
            sys.exit(1)

    # auto_init 后仓库需要短暂时间可写
    time.sleep(2)

    files = collect(args.src)
    print("待上传文件：%d 个\n" % len(files))
    ok = fail = 0
    for rel, full in files:
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode("ascii")
        quoted = urllib.parse.quote(rel, safe="/")
        path = "/repos/%s/contents/%s" % (full_name, quoted)

        sha = None
        try:
            existing = request("GET", path + "?ref=main", args.token)
            sha = existing.get("sha")
        except APIError as e:
            if e.code not in (404, 409):
                print("  ! 查询 %s 失败：%s" % (rel, e.code))

        payload = {
            "message": "Add %s" % rel,
            "content": content,
            "branch": "main",
        }
        if sha:
            payload["sha"] = sha
            payload["message"] = "Update %s" % rel
        try:
            request("PUT", path, args.token, payload)
            print("  OK  %s" % rel)
            ok += 1
        except APIError as e:
            print("  FAIL %s -> HTTP %s %s" % (rel, e.code, e.message[:120]))
            fail += 1

    print("\n上传完成：成功 %d / 失败 %d" % (ok, fail))
    print("仓库：https://github.com/%s" % full_name)
    print("下一步：打开 Actions → Build unsigned IPA → Run workflow")
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
