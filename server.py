#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KuXuan Music - 本地音乐服务（零第三方依赖，Python 标准库）
仅供个人自用，不对外发布。

启动: python3 server.py
iPhone 访问: http://<本机局域网IP>:8765
"""

import os
import re
import json
import math
import hmac
import base64
import hashlib
import secrets
import sqlite3
import wave
import struct
import socket
import time
import mimetypes
import urllib.parse
import urllib.request
import urllib.error
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(ROOT, "web")
MUSIC_DIR = os.path.join(ROOT, "music")
COVER_DIR = os.path.join(ROOT, "covers")
PORT = int(os.environ.get("KUXUAN_PORT", "8765"))
# 在线音源（用户本机跑的 NeteaseCloudMusicApi Enhanced v4.28.0），可用环境变量覆盖
# 3100 实测可用：search / cloudsearch / song/url/v1 / song/detail / playlist/detail
ONLINE_API = os.environ.get("KUXUAN_ONLINE_API", "http://127.0.0.1:3100").rstrip("/")
ONLINE_LEVEL = os.environ.get("KUXUAN_ONLINE_LEVEL", "standard")  # standard 128k / exhigh 320k
ONLINE_TIMEOUT = 8
# 首屏数据磁盘缓存：服务重启后无需等上游即可渲染主页
HOME_CACHE_FILE = os.path.join(ROOT, ".kx_home_cache.json")
HOME_CACHE_TTL = 3600

# ---------------------------------------------------------------- 账号体系
# 零第三方依赖：sqlite3 存账号，PBKDF2-HMAC-SHA256 存密码摘要，随机 Token 存会话。
# 说明：本机服务走局域网 HTTP（非 HTTPS），密码在传输层是明文的，
#       因此不预置任何默认账号，也不建议复用常用密码。自用场景可接受。
DB_PATH = os.path.join(ROOT, "kuxuan.db")
SESSION_TTL = 30 * 24 * 3600          # 30 天免登录
PBKDF2_ROUNDS = 200_000
# 默认不强制登录：音乐功能照常可用，账号只用于个人中心与后续云端收藏。
# 想让所有数据接口都必须登录：KUXUAN_REQUIRE_AUTH=1 python3 server.py
AUTH_REQUIRE = os.environ.get("KUXUAN_REQUIRE_AUTH", "0") == "1"
# 注册完建议关掉：KUXUAN_ALLOW_REGISTER=0，避免同 WiFi 的他人注册账号。
AUTH_ALLOW_REGISTER = os.environ.get("KUXUAN_ALLOW_REGISTER", "1") != "0"

AUDIO_EXT = {".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac",
             ".wav": "audio/wav", ".aiff": "audio/aiff", ".aif": "audio/aiff",
             ".mp4": "audio/mp4", ".ogg": "audio/ogg"}
# iPhone Safari 无法可靠播放 flac/ape，仅列出以便给出提示
UNSUPPORTED_EXT = {".flac", ".ape", ".wma", ".opus"}

_library = []
_library_lock = threading.Lock()


def log(msg):
    print("[kuxuan] " + msg, flush=True)


# ---------------------------------------------------------------- 演示音轨
def make_demo_tracks():
    """曲库为空时合成 3 首免版权的简短演示曲（自行生成的正弦和弦，无版权风险）"""
    demos = [
        ("KuXuan - 晨光.wav", [261.63, 329.63, 392.00, 523.25], 0.9),
        ("KuXuan - 晚风.wav", [220.00, 277.18, 329.63, 440.00], 0.75),
        ("KuXuan - 星夜.wav", [196.00, 246.94, 293.66, 392.00], 0.6),
    ]
    rate = 22050
    for fname, chord, tempo in demos:
        path = os.path.join(MUSIC_DIR, fname)
        if os.path.exists(path):
            continue
        seconds = 24
        frames = bytearray()
        total = rate * seconds
        for i in range(total):
            t = i / rate
            # 每 2 秒换一个和弦音，叠加五度与八度泛音
            step = int(t / 2) % len(chord)
            base = chord[step]
            env = min(1.0, (t % 2) / 0.08) * min(1.0, max(0.0, (2 - (t % 2)) / 0.35))
            lfo = 0.75 + 0.25 * math.sin(2 * math.pi * 0.5 * t)
            v = (math.sin(2 * math.pi * base * t) * 0.5
                 + math.sin(2 * math.pi * base * 1.5 * t) * 0.22
                 + math.sin(2 * math.pi * base * 2 * t) * 0.12
                 + math.sin(2 * math.pi * base * 3 * t) * 0.05)
            # 轻微高音旋律线
            mel = math.sin(2 * math.pi * base * 4 * t) * 0.06 * (0.5 + 0.5 * math.sin(2 * math.pi * t))
            sample = (v + mel) * env * lfo * 0.28 * tempo
            frames += struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767))
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(bytes(frames))
        log("生成演示音轨: " + fname)

    # 演示歌词
    lrc = os.path.join(MUSIC_DIR, "KuXuan - 晨光.lrc")
    if not os.path.exists(lrc):
        lines = ["[00:00.00]KuXuan 本地音乐", "[00:03.00]演示音轨 · 由本机实时合成",
                 "[00:07.00]把你自己的音乐放进 music 文件夹", "[00:11.00]刷新页面即可出现在这里",
                 "[00:15.00]支持 mp3 / m4a / wav / aac", "[00:19.00]感谢使用"]
        with open(lrc, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))


# ---------------------------------------------------------------- 曲库解析
def parse_id3v1(path):
    """读取 ID3v1 尾部标签（无需第三方库）"""
    try:
        with open(path, "rb") as f:
            f.seek(-128, os.SEEK_END)
            tag = f.read(128)
        if len(tag) == 128 and tag[:3] == b"TAG":
            def clean(b):
                return b.split(b"\x00")[0].decode("gbk", "ignore").strip()
            return clean(tag[3:33]), clean(tag[33:63])
    except Exception:
        pass
    return "", ""


def parse_name(filename):
    """支持 '歌手 - 歌名.mp3' 命名"""
    stem = os.path.splitext(filename)[0]
    if " - " in stem:
        artist, title = stem.split(" - ", 1)
        return title.strip(), artist.strip()
    return stem, "未知艺术家"


def scan_library():
    global _library
    items = []
    if not os.path.isdir(MUSIC_DIR):
        os.makedirs(MUSIC_DIR, exist_ok=True)
    for name in sorted(os.listdir(MUSIC_DIR)):
        ext = os.path.splitext(name)[1].lower()
        if ext not in AUDIO_EXT:
            continue
        path = os.path.join(MUSIC_DIR, name)
        title, artist = parse_name(name)
        t2, a2 = parse_id3v1(path)
        if t2:
            title = t2
        if a2:
            artist = a2
        sid = urllib.parse.quote(name, safe="")
        stem = os.path.splitext(name)[0]
        has_lyric = os.path.exists(os.path.join(MUSIC_DIR, stem + ".lrc"))
        cover = None
        for cext in (".jpg", ".jpeg", ".png", ".webp"):
            for base in (MUSIC_DIR, COVER_DIR):
                p = os.path.join(base, stem + cext)
                if os.path.exists(p):
                    cover = "/api/cover/" + sid
                    break
            if cover:
                break
        try:
            mtime = os.path.getmtime(path)
        except Exception:
            mtime = 0
        items.append({
            "id": sid, "file": name, "title": title, "artist": artist,
            "album": "本地曲库", "duration": 0, "hasLyric": has_lyric,
            "cover": cover, "mtime": int(mtime),
            "size": os.path.getsize(path),
            "mime": AUDIO_EXT[ext],
        })
    with _library_lock:
        _library = items
    log("曲库扫描完成: %d 首" % len(items))
    return items


def find_song(sid):
    with _library_lock:
        for s in _library:
            if s["id"] == sid:
                return s
    return None


def safe_music_path(sid):
    """防目录穿越"""
    name = urllib.parse.unquote(sid)
    if not name or "/" in name or "\\" in name or name.startswith("."):
        return None
    path = os.path.join(MUSIC_DIR, name)
    if not os.path.isfile(path):
        return None
    return path


def make_cover_svg(title):
    """无封面时生成渐变 SVG（沿用原项目 #FFAA85 → #B3315F 配色）"""
    ch = title.strip()[0] if title.strip() else "♪"
    ch = ch.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    seed = sum(ord(c) for c in title) % 40
    c1 = "#FF%02X%02X" % (0xAA - seed, 0x85 + seed // 2)
    c2 = "#B3%02X%02X" % (0x31 + seed // 2, 0x5F + seed)
    return ("""<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<rect width="400" height="400" fill="url(#g)"/>
<circle cx="200" cy="200" r="120" fill="none" stroke="rgba(255,255,255,.28)" stroke-width="2"/>
<circle cx="200" cy="200" r="86" fill="none" stroke="rgba(255,255,255,.2)" stroke-width="2"/>
<circle cx="200" cy="200" r="26" fill="rgba(255,255,255,.85)"/>
<text x="200" y="222" text-anchor="middle" font-size="88" font-family="-apple-system,Helvetica" fill="rgba(255,255,255,.95)">%s</text>
</svg>""" % (c1, c2, ch)).encode("utf-8")


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("223.5.5.5", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


# ---------------------------------------------------------------- 在线音源
# 上游是本机 3100 的 NeteaseCloudMusicApi Enhanced。旧版 3000 对 search / song/url
# 返回 -462（网易云出口 IP 行为验证）；3100 更新后这些端点已恢复，因此这里：
#   · 曲库：top/song + personalized/newsong + 一个真实榜单歌单
#   · 搜索：cloudsearch（真实全网结果），失败时降级为本地过滤
#   · 播放：song/url/v1 取带签名的真实 mp3，由本机代理转发并透传 Range
#           （手机只连 Mac，避免外链签名过期 / 混合内容 / 跨域问题）
# 风控状态仍如实上报，绝不伪造可播地址。
_online_cache = {}
_online_lock = threading.Lock()
_online_pic = {}       # 歌曲 id -> 封面原图 URL（含搜索结果，供 /cover 代理用）
_online_pic_lock = threading.Lock()


# ---------------------------------------------------------------- 首屏预加载
def save_home_disk(data):
    """把首页聚合落盘，服务重启后第一个页面就能直接内联渲染。"""
    try:
        with open(HOME_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump({"ts": time.time(), "data": data}, f, ensure_ascii=False)
    except Exception as e:
        log("首页缓存写入失败: %s" % e)


def load_home_disk():
    """启动时把未过期的磁盘缓存塞进内存，让 / 与 /api/online/home 立即可用。"""
    try:
        with open(HOME_CACHE_FILE, encoding="utf-8") as f:
            d = json.load(f)
        if time.time() - d.get("ts", 0) < HOME_CACHE_TTL and d.get("data"):
            with _online_lock:
                _online_cache["home"] = {"ts": d["ts"], "data": d["data"]}
            log("首屏磁盘缓存已恢复（%.0f 分钟前）" %
                ((time.time() - d["ts"]) / 60))
            return d["data"]
    except FileNotFoundError:
        pass
    except Exception as e:
        log("首页缓存读取失败: %s" % e)
    return None


def boot_payload():
    """给 index.html 内联的首屏数据；没有缓存时返回 null，前端走骨架屏。"""
    with _online_lock:
        hit = _online_cache.get("home")
    if not hit:
        return None
    data = dict(hit["data"])
    data["_cachedAt"] = hit["ts"]
    return data


def warmup():
    """后台预热：首页聚合 + 常用榜单详情，避免首次点开列表等上游 2 秒。"""
    try:
        t0 = time.time()
        home = online_home()
        log("预热首页完成 %.1fs" % (time.time() - t0))
        for c in (home.get("charts") or [])[:3]:
            cid = c.get("id")
            if cid:
                try:
                    online_playlist(cid)
                except Exception as e:
                    log("预热榜单 %s 失败: %s" % (cid, e))
        log("预热榜单详情完成 %.1fs" % (time.time() - t0))
    except Exception as e:
        log("预热失败（不影响服务）: %s" % e)


def online_get(path, params=None, timeout=ONLINE_TIMEOUT, cookie=None):
    """请求本地在线 API，返回 (dict, error_str)。cookie 用于已登录态的个人数据接口。"""
    url = ONLINE_API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "Accept": "application/json, */*",
    }
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
        return json.loads(raw.decode("utf-8", "replace")), None
    except urllib.error.HTTPError as e:
        # 上游被风控时也会用 400 承载 JSON body，仍尝试解析
        try:
            body = json.loads(e.read().decode("utf-8", "replace"))
            return body, None
        except Exception:
            return None, "HTTP %s" % e.code
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e)[:80])


def _norm_song(raw):
    """把网易云歌曲对象转成 KuXuan 前端统一格式"""
    sid = str(raw.get("id") or "")
    if not sid:
        return None
    artists = raw.get("artists") or raw.get("ar") or []
    names = [a.get("name") for a in artists if isinstance(a, dict) and a.get("name")]
    album = raw.get("album") or raw.get("al") or {}
    pic = album.get("picUrl") or raw.get("picUrl") or ""
    with _online_pic_lock:
        if pic:
            _online_pic[sid] = pic
    # 图片上游是 http，手机端混合内容会被 Safari 拦，统一走本地代理；
    # 即使此刻没拿到 picUrl，/cover 也会用 song/detail 现场补全
    cover = "/api/online/cover/" + urllib.parse.quote(sid, safe="")
    return {
        "id": "online:" + sid,
        "file": sid,
        "title": raw.get("name") or "未知歌曲",
        "artist": " / ".join(names) or "未知艺术家",
        "album": album.get("name") or "在线音源",
        # 网易云 playlist/detail 的曲目时长字段是 dt，top/song 用 duration
        "duration": int((raw.get("duration") or raw.get("dt") or 0) / 1000),
        "hasLyric": True,
        "cover": cover,
        "picUrl": pic,
        "online": True,
        "mtime": 0, "size": 0, "mime": "audio/mpeg",
    }


def online_songs(force=False):
    """聚合可用端点，返回 (songs, charts, status)"""
    key = "songs"
    with _online_lock:
        hit = _online_cache.get(key)
        if hit and not force and time.time() - hit["ts"] < 300:
            return hit["songs"], hit["charts"], hit["status"]

    songs, seen = [], set()
    status = {"api": ONLINE_API, "reachable": False, "riskControl": False,
              "endpoints": {}, "note": ""}

    root, err = online_get("/banner", {"type": 0})
    status["reachable"] = bool(root and root.get("code") == 200)
    if err:
        status["note"] = "在线接口连不上：%s" % err
        return [], [], status

    # 1) 新歌榜 / 热门单曲（字段最全，含封面与歌手）
    d, e = online_get("/top/song", {"type": 0})
    ok = bool(d and d.get("code") == 200)
    status["endpoints"]["top/song"] = ok
    for raw in (d or {}).get("data", [])[:100]:
        s = _norm_song(raw)
        if s and s["id"] not in seen:
            seen.add(s["id"])
            songs.append(s)

    # 2) 个性化新歌（补充）
    d2, _ = online_get("/personalized/newsong", {"limit": 10})
    ok2 = bool(d2 and d2.get("code") == 200)
    status["endpoints"]["personalized/newsong"] = ok2
    for item in (d2 or {}).get("result", []):
        raw = item.get("song") if isinstance(item, dict) else None
        if not raw:
            continue
        s = _norm_song(raw)
        if s and s["id"] not in seen:
            seen.add(s["id"])
            songs.append(s)

    # 3) 榜单列表 + 取一个榜单的真实曲目（3100 的 playlist/detail 已恢复）
    charts = []
    d3, _ = online_get("/toplist/detail")
    ok3 = bool(d3 and d3.get("code") == 200)
    status["endpoints"]["toplist/detail"] = ok3
    for c in (d3 or {}).get("list", [])[:12]:
        tracks = []
        for t in (c.get("tracks") or [])[:3]:
            if isinstance(t, dict) and t.get("first"):
                tracks.append("%s - %s" % (t.get("first"), t.get("second") or ""))
        charts.append({"id": c.get("id"), "name": c.get("name"),
                       "cover": c.get("coverImgUrl"), "tracks": tracks})
    chart_id = next((c.get("id") for c in (d3 or {}).get("list", [])[:5]
                     if c.get("id")), None)
    if chart_id:
        d4, _ = online_get("/playlist/detail", {"id": chart_id})
        ok4 = bool(d4 and d4.get("code") == 200)
        status["endpoints"]["playlist/detail"] = ok4
        for raw in (((d4 or {}).get("playlist") or {}).get("tracks") or [])[:40]:
            s = _norm_song(raw)
            if s and s["id"] not in seen:
                seen.add(s["id"])
                songs.append(s)

    # 4) 搜索能力（旧版 -462，3100 已恢复；失败时前端自动降级本地过滤）
    ds, _ = online_get("/cloudsearch", {"keywords": "音乐", "type": 1, "limit": 1})
    status["searchable"] = bool(ds and ds.get("code") == 200
                                and (ds.get("result") or {}).get("songs"))
    status["endpoints"]["cloudsearch"] = status["searchable"]

    # 5) 探测播放地址能力（不缓存结果，实时反映风控状态）
    probe_id = songs[0]["file"] if songs else "347230"
    u, _ = online_get("/song/url/v1", {"id": probe_id, "level": ONLINE_LEVEL})
    code = (u or {}).get("code")
    playable = False
    if code == 200:
        playable = any((x.get("url") for x in (u or {}).get("data", [])))
    status["endpoints"]["song/url"] = playable
    status["playable"] = playable
    status["riskControl"] = code == -462
    status["level"] = ONLINE_LEVEL
    if code == -462:
        status["note"] = "网易云上游风控(-462)：可浏览真实曲库，但取不到播放地址"
    elif not playable:
        status["note"] = "播放地址不可用（code=%s）" % code
    else:
        status["note"] = "在线接口正常：可搜索、可播放（%s）" % ONLINE_LEVEL

    with _online_lock:
        _online_cache[key] = {"ts": time.time(), "songs": songs,
                              "charts": charts, "status": status}
    log("在线音源: %d 首 | 榜单 %d 个 | 可播放: %s" %
        (len(songs), len(charts), playable))
    return songs, charts, status


def online_fetch_bytes(url, timeout=ONLINE_TIMEOUT):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0",
        "Referer": "https://music.163.com/",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), (r.headers.get("Content-Type") or "image/jpeg")


def online_play_url(sid, level=None):
    """取带签名的真实播放地址。返回 (url, meta, reason)，取不到时 reason 说明原因。"""
    d, err = online_get("/song/url/v1",
                        {"id": sid, "level": level or ONLINE_LEVEL})
    if err:
        return None, {}, "在线接口连接失败：%s" % err
    code = (d or {}).get("code")
    for item in (d or {}).get("data", []):
        if item.get("url"):
            return item["url"], item, None
    if code == -462:
        return None, {}, "网易云出口 IP 行为验证 (-462)，播放地址被拒"
    return None, {}, "无可用播放地址（可能 VIP / 无版权 / 下架，code=%s）" % code


def online_pic_url(sid):
    """封面优先取已归一化的缓存；搜索结果没缓存时现场用 song/detail 补。"""
    with _online_pic_lock:
        pic = _online_pic.get(sid)
    if pic:
        return pic
    d, _ = online_get("/song/detail", {"ids": sid})
    songs = (d or {}).get("songs") or []
    if songs:
        pic = ((songs[0].get("al") or songs[0].get("album") or {}).get("picUrl")
               or songs[0].get("picUrl"))
        if pic:
            with _online_pic_lock:
                _online_pic[sid] = pic
    return pic


def _pic_proxy(url):
    """外链图片统一走本地代理：上游是 http，手机 Safari 会拦混合内容。"""
    if not url:
        return ""
    return "/api/online/pic?u=" + urllib.parse.quote(url, safe="")


def _norm_playlist(raw):
    if not isinstance(raw, dict) or not raw.get("id"):
        return None
    pic = (raw.get("picUrl") or raw.get("coverImgUrl")
           or raw.get("cover") or "")
    return {
        "id": raw["id"],
        "name": raw.get("name") or "歌单",
        "cover": _pic_proxy(pic),
        "playCount": raw.get("playCount") or 0,
        "trackCount": raw.get("trackCount") or 0,
        "description": (raw.get("description") or "")[:140],
    }


def online_home(force=False):
    """首页聚合：轮播 / 推荐歌单 / 榜单 / 新歌 / 热搜。缓存 5 分钟。"""
    key = "home"
    with _online_lock:
        hit = _online_cache.get(key)
        if hit and not force and time.time() - hit["ts"] < 300:
            return hit["data"]

    data = {"code": 200, "banners": [], "playlists": [], "charts": [],
            "newsongs": [], "hot": [], "status": {}}

    b, _ = online_get("/banner", {"type": 0})
    for x in (b or {}).get("banners", [])[:6]:
        img = x.get("imageUrl") or x.get("picUrl")
        if img:
            data["banners"].append({"img": _pic_proxy(img),
                                   "title": x.get("typeTitle") or "",
                                   "id": x.get("targetId")})

    p, _ = online_get("/personalized", {"limit": 8})
    raws = (p or {}).get("result") or []
    if not raws:
        p2, _ = online_get("/top/playlist", {"limit": 8, "order": "hot"})
        raws = (p2 or {}).get("playlists") or []
    for x in raws[:8]:
        pl = _norm_playlist(x)
        if pl:
            data["playlists"].append(pl)

    d3, _ = online_get("/toplist/detail")
    for c in (d3 or {}).get("list", [])[:6]:
        tracks = []
        for t in (c.get("tracks") or [])[:3]:
            if isinstance(t, dict) and t.get("first"):
                tracks.append({"title": t.get("first"),
                               "artist": t.get("second") or ""})
        data["charts"].append({
            "id": c.get("id"), "name": c.get("name"),
            "cover": _pic_proxy(c.get("coverImgUrl")),
            "update": c.get("updateFrequency") or "",
            "tracks": tracks,
        })

    t, _ = online_get("/top/song", {"type": 0})
    for raw in (t or {}).get("data", [])[:12]:
        s = _norm_song(raw)
        if s:
            data["newsongs"].append(s)

    h, _ = online_get("/search/hot/detail")
    data["hot"] = [x.get("searchWord") for x in (h or {}).get("data", [])[:12]
                   if x.get("searchWord")]

    _, _, st = online_songs()
    data["status"] = st
    with _online_lock:
        _online_cache[key] = {"ts": time.time(), "data": data}
    save_home_disk(data)
    log("在线首页: 轮播 %d / 歌单 %d / 榜单 %d / 新歌 %d" %
        (len(data["banners"]), len(data["playlists"]),
         len(data["charts"]), len(data["newsongs"])))
    return data


def online_playlist(pid, force=False):
    """歌单 / 榜单详情，最多取前 60 首，避免首页点开等太久。"""
    key = "pl:" + str(pid)
    with _online_lock:
        hit = _online_cache.get(key)
        if hit and not force and time.time() - hit["ts"] < 300:
            return hit["data"]
    # 私有歌单（含「我喜欢的音乐」）需带网易云 cookie 才能取到完整曲目
    d, err = online_get("/playlist/detail", {"id": pid}, cookie=kv_get("ncm_cookie"))
    pl = (d or {}).get("playlist") or {}
    if not pl:
        return {"code": 404, "info": {}, "songs": [],
                "reason": err or "歌单不存在或上游不可用"}
    info = _norm_playlist(pl) or {"id": pid, "name": "歌单", "cover": ""}
    songs = []
    for raw in (pl.get("tracks") or [])[:60]:
        s = _norm_song(raw)
        if s:
            songs.append(s)
    out = {"code": 200, "info": info, "songs": songs}
    with _online_lock:
        _online_cache[key] = {"ts": time.time(), "data": out}
    return out


# ---------------------------------------------------------------- 账号数据层
def db_conn():
    c = sqlite3.connect(DB_PATH, timeout=5)
    c.row_factory = sqlite3.Row
    return c


def init_db():
    c = db_conn()
    try:
        c.execute("PRAGMA journal_mode=WAL")
        c.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                username    TEXT NOT NULL UNIQUE,
                nickname    TEXT NOT NULL,
                pwd_salt    TEXT NOT NULL,
                pwd_hash    TEXT NOT NULL,
                created_at  INTEGER NOT NULL,
                last_login  INTEGER
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash  TEXT PRIMARY KEY,
                user_id     INTEGER NOT NULL,
                created_at  INTEGER NOT NULL,
                expires_at  INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
            CREATE TABLE IF NOT EXISTS kv (
                k TEXT PRIMARY KEY,
                v TEXT
            );
        """)
        c.execute("DELETE FROM sessions WHERE expires_at<?", (int(time.time()),))
        c.commit()
    finally:
        c.close()


# ---------------------------------------------------------------- 网易云账号（全局绑定，存在本机）
# 设计说明：本机单机自用，3100 只能持有一个网易云会话，因此把网易云身份做成
# 全局 kv，而不是按「新感官」本地账号各存一份（避免 /user/playlist 调错 cookie）。
# 个人中心会显示「已绑定：<昵称>」，等价于把网易云身份挂到当前使用者名下。
NCM_KEYS = ("ncm_cookie", "ncm_uid", "ncm_nickname", "ncm_avatar", "ncm_bound_at")


def kv_get(k, default=None):
    c = db_conn()
    try:
        row = c.execute("SELECT v FROM kv WHERE k=?", (k,)).fetchone()
        return row["v"] if row else default
    finally:
        c.close()


def kv_set(k, v):
    c = db_conn()
    try:
        c.execute("INSERT INTO kv(k,v) VALUES(?,?) "
                  "ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, v))
        c.commit()
    finally:
        c.close()


def kv_del(k):
    c = db_conn()
    try:
        c.execute("DELETE FROM kv WHERE k=?", (k,))
        c.commit()
    finally:
        c.close()


def ncm_bound():
    return bool(kv_get("ncm_cookie"))


def ncm_session():
    """返回当前网易云绑定信息；未绑定时 cookie 为空。"""
    return {k: kv_get(k) for k in NCM_KEYS}


def ncm_profile():
    uid = kv_get("ncm_uid")
    if not uid:
        return None
    return {
        "uid": uid,
        "nickname": kv_get("ncm_nickname") or "",
        "avatar": kv_get("ncm_avatar") or "",
        "boundAt": int(kv_get("ncm_bound_at") or 0),
    }


def ncm_set_session(cookie, uid, nickname, avatar):
    kv_set("ncm_cookie", cookie or "")
    kv_set("ncm_uid", str(uid or ""))
    kv_set("ncm_nickname", nickname or "")
    kv_set("ncm_avatar", avatar or "")
    kv_set("ncm_bound_at", str(int(time.time())))


def ncm_clear():
    for k in NCM_KEYS:
        kv_del(k)


# ---- 网易云扫码监控：独立于前端定时器，避免 iOS PWA 后台挂起漏掉 803 ----
# 生成二维码时启动一个守护线程持续轮询 3100，拿到 803 立即写会话；
# 前端 qr/check 只读取这里的缓存状态，因此扫码期间前端被系统挂起也不影响绑定写入。
ncm_qr_lock = threading.Lock()
ncm_qr_state = {"key": "", "code": 801, "bound": False, "error": ""}


def _ncm_commit_qr_success(d):
    """803 成功：取 cookie、查资料、写会话。成功返回 True；游客态返回 False。"""
    raw = (d.get("data") or {}).get("cookie")
    if raw is None:
        raw = d.get("cookie")
    if isinstance(raw, dict):
        cookie = "; ".join("%s=%s" % (k, v) for k, v in raw.items())
    else:
        cookie = str(raw or "")
    if not cookie:
        return False
    uid = None
    nickname = ""
    avatar = ""
    s, _ = online_get("/login/status", cookie=cookie)
    acc = ((s or {}).get("data", {}) or {})
    prof = acc.get("profile") or {}
    uid = prof.get("userId") or (acc.get("account") or {}).get("id")
    nickname = prof.get("nickname") or ""
    avatar = prof.get("avatarUrl") or ""
    # profile 为空（偶发游客态）时，用 uid 补查一次个人资料
    if (not nickname or not avatar) and uid:
        det, _ = online_get("/user/detail?uid=%s" % uid, cookie=cookie)
        dp = (((det or {}).get("data", {}) or {}).get("profile") or {})
        nickname = nickname or dp.get("nickname") or ""
        avatar = avatar or dp.get("avatarUrl") or ""
    # 仍是游客态（无有效昵称）：不写会话
    if not nickname and (acc.get("account") or {}).get("anonimousUser"):
        return False
    ncm_set_session(cookie, uid, nickname, avatar)
    return True


def ncm_qr_monitor(key):
    """后台线程：持续轮询 3100 直到确认/过期，确认即写会话。"""
    deadline = time.time() + 200  # 最多轮询 ~3.3 分钟
    while time.time() < deadline:
        with ncm_qr_lock:
            if ncm_qr_state.get("key") != key:
                return  # 已被新二维码或关闭取代
        try:
            d, err = online_get("/login/qr/check", {"key": key})
        except Exception as e:
            with ncm_qr_lock:
                ncm_qr_state["error"] = "%s" % e
            time.sleep(1.5)
            continue
        if not d:
            time.sleep(1.5)
            continue
        code = d.get("code")
        if code == 803:
            ok = _ncm_commit_qr_success(d)
            with ncm_qr_lock:
                if ok:
                    ncm_qr_state["code"] = 803
                    ncm_qr_state["bound"] = True
                else:
                    ncm_qr_state["code"] = "GUEST"
                    ncm_qr_state["error"] = "拿到的是游客态，请重新扫码登录"
            return
        elif code == 800:
            with ncm_qr_lock:
                ncm_qr_state["code"] = 800
            return
        else:
            with ncm_qr_lock:
                ncm_qr_state["code"] = code or 801
            time.sleep(1.5)
    with ncm_qr_lock:
        ncm_qr_state["code"] = 800  # 超时当作过期


def ncm_get(path, params=None):
    """带网易云 cookie 的在线接口请求（仅个人数据需要）。"""
    return online_get(path, params, cookie=kv_get("ncm_cookie"))


def norm_username(s):
    s = (s or "").strip()
    if not (3 <= len(s) <= 64):
        return None
    # 允许手机号 / 邮箱 / 普通用户名，拒绝空白、控制字符与 HTML 危险字符
    if not re.match(r"^[A-Za-z0-9._@+\-]+$", s):
        return None
    return s.lower()


def norm_nickname(s):
    s = re.sub(r"[\x00-\x1f\x7f]", "", (s or "").strip())
    return s if 1 <= len(s) <= 24 else None


def hash_password(pwd, salt_b64=None):
    salt = base64.b64decode(salt_b64) if salt_b64 else secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", pwd.encode("utf-8"), salt, PBKDF2_ROUNDS)
    return (base64.b64encode(salt).decode("ascii"),
            base64.b64encode(dk).decode("ascii"))


def verify_password(pwd, salt_b64, hash_b64):
    try:
        _, calc = hash_password(pwd, salt_b64)
        return hmac.compare_digest(calc, hash_b64 or "")
    except Exception:
        return False


def public_user(row):
    return {"id": row["id"], "username": row["username"],
            "nickname": row["nickname"], "createdAt": row["created_at"],
            "lastLogin": row["last_login"]}


def token_digest(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_token(user_id):
    token = secrets.token_urlsafe(32)
    now = int(time.time())
    c = db_conn()
    try:
        c.execute("INSERT INTO sessions(token_hash,user_id,created_at,expires_at) "
                  "VALUES(?,?,?,?)",
                  (token_digest(token), user_id, now, now + SESSION_TTL))
        c.commit()
    finally:
        c.close()
    return token


def user_by_token(token):
    if not token or len(token) > 256:
        return None
    c = db_conn()
    try:
        return c.execute(
            "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id "
            "WHERE s.token_hash=? AND s.expires_at>?",
            (token_digest(token), int(time.time()))).fetchone()
    finally:
        c.close()


def revoke_token(token):
    if not token:
        return
    c = db_conn()
    try:
        c.execute("DELETE FROM sessions WHERE token_hash=?", (token_digest(token),))
        c.commit()
    finally:
        c.close()


# 轻量登录限流：同 IP 连续失败 5 次后冻结 60 秒（内存态，重启清零）
_auth_fail = {}
_auth_fail_lock = threading.Lock()


def auth_blocked(ip):
    with _auth_fail_lock:
        rec = _auth_fail.get(ip)
        if not rec:
            return 0
        count, until = rec
        if time.time() > until:
            _auth_fail.pop(ip, None)
            return 0
        return max(1, int(until - time.time())) if count >= 5 else 0


def auth_failed(ip):
    with _auth_fail_lock:
        count, until = _auth_fail.get(ip, (0, 0))
        count = 0 if time.time() > until else count
        _auth_fail[ip] = (count + 1, time.time() + 60)


def auth_succeeded(ip):
    with _auth_fail_lock:
        _auth_fail.pop(ip, None)


def auth_status():
    c = db_conn()
    try:
        n = c.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    finally:
        c.close()
    return {"ok": True, "requireAuth": AUTH_REQUIRE,
            "allowRegister": AUTH_ALLOW_REGISTER, "userCount": n,
            "sessionDays": SESSION_TTL // 86400}


def auth_register(body, ip):
    if not AUTH_ALLOW_REGISTER:
        return ({"ok": False, "code": "REGISTER_CLOSED",
                 "error": "注册已关闭（服务端 KUXUAN_ALLOW_REGISTER=0）"}, 403)
    u = norm_username(body.get("username"))
    n = norm_nickname(body.get("nickname"))
    p = body.get("password") or ""
    if not u:
        return ({"ok": False, "code": "BAD_USERNAME",
                 "error": "账号需 3-64 位，只能用字母、数字、@ . _ + -（手机号或邮箱也可以）"}, 400)
    if not n:
        return ({"ok": False, "code": "BAD_NICKNAME", "error": "昵称需 1-24 个字符"}, 400)
    if not (8 <= len(p) <= 128):
        return ({"ok": False, "code": "BAD_PASSWORD", "error": "密码需 8-128 位"}, 400)
    salt, digest = hash_password(p)
    now = int(time.time())
    c = db_conn()
    try:
        try:
            cur = c.execute(
                "INSERT INTO users(username,nickname,pwd_salt,pwd_hash,created_at,last_login) "
                "VALUES(?,?,?,?,?,?)", (u, n, salt, digest, now, now))
            uid = cur.lastrowid
            c.commit()
        except sqlite3.IntegrityError:
            return ({"ok": False, "code": "USERNAME_TAKEN",
                     "error": "该账号已注册，请直接登录"}, 409)
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    finally:
        c.close()
    auth_succeeded(ip)
    return {"ok": True, "token": issue_token(uid), "user": public_user(row)}, 201


def auth_login(body, ip):
    blocked = auth_blocked(ip)
    if blocked:
        return ({"ok": False, "code": "RATE_LIMITED",
                 "error": "尝试过于频繁，请 %d 秒后再试" % blocked}, 429)
    u = norm_username(body.get("username"))
    p = body.get("password") or ""
    if not u or not p:
        return ({"ok": False, "code": "BAD_INPUT", "error": "请输入账号和密码"}, 400)
    c = db_conn()
    try:
        row = c.execute("SELECT * FROM users WHERE username=?", (u,)).fetchone()
    finally:
        c.close()
    if not row or not verify_password(p, row["pwd_salt"], row["pwd_hash"]):
        auth_failed(ip)
        return ({"ok": False, "code": "BAD_CREDENTIALS",
                 "error": "账号或密码不正确"}, 401)
    auth_succeeded(ip)
    now = int(time.time())
    c = db_conn()
    try:
        c.execute("UPDATE users SET last_login=? WHERE id=?", (now, row["id"]))
        c.execute("DELETE FROM sessions WHERE expires_at<?", (now,))
        c.commit()
        row = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    finally:
        c.close()
    return {"ok": True, "token": issue_token(row["id"]), "user": public_user(row)}, 200


def auth_update_profile(user, body):
    n = norm_nickname(body.get("nickname"))
    if not n:
        return ({"ok": False, "code": "BAD_NICKNAME", "error": "昵称需 1-24 个字符"}, 400)
    c = db_conn()
    try:
        c.execute("UPDATE users SET nickname=? WHERE id=?", (n, user["id"]))
        c.commit()
        row = c.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone()
    finally:
        c.close()
    return {"ok": True, "user": public_user(row)}, 200


def auth_change_password(user, body):
    old = body.get("oldPassword") or ""
    new = body.get("newPassword") or ""
    if not (8 <= len(new) <= 128):
        return ({"ok": False, "code": "BAD_PASSWORD", "error": "新密码需 8-128 位"}, 400)
    c = db_conn()
    try:
        row = c.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone()
        if not row or not verify_password(old, row["pwd_salt"], row["pwd_hash"]):
            return ({"ok": False, "code": "BAD_OLD_PASSWORD", "error": "当前密码不正确"}, 401)
        salt, digest = hash_password(new)
        c.execute("UPDATE users SET pwd_salt=?,pwd_hash=? WHERE id=?",
                  (salt, digest, user["id"]))
        # 改密码后吊销该账号所有会话，需重新登录
        c.execute("DELETE FROM sessions WHERE user_id=?", (user["id"],))
        c.commit()
    finally:
        c.close()
    return {"ok": True, "relogin": True}, 200


# ---------------------------------------------------------------- 静态资源版本
# iOS 主屏 Web App 会把 HTML/CSS/JS 连同页面快照一起缓存，手工维护 ?v=2.0.x
# 极易漏改（已踩过两次：改了 CSS 但手机仍显示旧的悬浮播放条）。
# 改为由文件内容 + mtime 派生版本号：任何前端文件一改，URL 自动变化，
# 缓存必然失效；文件没变则 URL 稳定，可以放心让浏览器长缓存。
def asset_version():
    h = hashlib.md5()
    for name in ("index.html", "style.css", "app.js", "manifest.json"):
        p = os.path.join(WEB_DIR, name)
        try:
            st = os.stat(p)
            h.update(name.encode("utf-8"))
            h.update(str(st.st_mtime_ns).encode("ascii"))
            h.update(str(st.st_size).encode("ascii"))
        except OSError:
            pass
    return h.hexdigest()[:10]


# ---------------------------------------------------------------- HTTP 处理
class Handler(BaseHTTPRequestHandler):
    server_version = "KuXuan/1.0"

    def log_message(self, fmt, *args):
        pass  # 静音，避免刷屏

    def _cors(self, cache="no-cache"):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", cache)

    def _json(self, obj, code=200, cache=None):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._cors(cache or "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _bearer(self):
        """Token 走 Header 而非 Cookie：iOS 主屏 Web App 对 Cookie 的持久化不稳定，
        且 Header Token 天然不受 CSRF 影响。"""
        h = self.headers.get("Authorization", "")
        if h.lower().startswith("bearer "):
            return h[7:].strip()
        return (self.headers.get("X-KX-Token") or "").strip()

    def _auth_user(self):
        return user_by_token(self._bearer())

    def _auth_json(self, obj, code=200):
        return self._json(obj, code, cache="no-store")

    def _bytes(self, data, ctype, code=200, extra=None, cache=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Accept-Ranges", "bytes")
        self._cors(cache or "no-cache")
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if not path.startswith("/api/auth/"):
            return self._auth_json({"ok": False, "code": "NOT_FOUND", "error": "404"}, 404)
        try:
            size = int(self.headers.get("Content-Length", "0") or 0)
        except ValueError:
            size = 0
        if size > 8192:
            return self._auth_json({"ok": False, "code": "BAD_BODY",
                                    "error": "请求体过大"}, 400)
        try:
            # 空 body 视为 {}：登出等接口不需要传参；但注册/登录必须给到字段。
            body = json.loads(self.rfile.read(size).decode("utf-8")) if size > 0 else {}
        except Exception:
            return self._auth_json({"ok": False, "code": "BAD_JSON",
                                    "error": "请求体不是合法 JSON"}, 400)
        if not isinstance(body, dict):
            return self._auth_json({"ok": False, "code": "BAD_JSON",
                                    "error": "请求体必须是对象"}, 400)
        ip = self.client_address[0] if self.client_address else "?"

        if path in ("/api/auth/register", "/api/auth/login") and not body:
            return self._auth_json({"ok": False, "code": "BAD_BODY",
                                    "error": "请填写账号与密码"}, 400)
        if path == "/api/auth/register":
            out, code = auth_register(body, ip)
            return self._auth_json(out, code)
        if path == "/api/auth/login":
            out, code = auth_login(body, ip)
            return self._auth_json(out, code)

        user = self._auth_user()
        if not user:
            return self._auth_json({"ok": False, "code": "UNAUTHORIZED",
                                    "error": "未登录或会话已过期"}, 401)
        if path == "/api/auth/logout":
            revoke_token(self._bearer())
            return self._auth_json({"ok": True})
        if path == "/api/auth/profile":
            out, code = auth_update_profile(user, body)
            return self._auth_json(out, code)
        if path == "/api/auth/password":
            out, code = auth_change_password(user, body)
            return self._auth_json(out, code)
        return self._auth_json({"ok": False, "code": "NOT_FOUND", "error": "404"}, 404)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        # ---------------- 账号
        if path == "/api/auth/status":
            out = auth_status()
            u = self._auth_user()
            out["user"] = public_user(u) if u else None
            return self._auth_json(out)
        if path == "/api/auth/me":
            u = self._auth_user()
            if not u:
                return self._auth_json({"ok": False, "code": "UNAUTHORIZED",
                                        "error": "未登录或会话已过期"}, 401)
            return self._auth_json({"ok": True, "user": public_user(u)})

        # 可选强制登录：除 auth 接口外的数据接口都要求 Token（静态资源仍放行，
        # 否则登录页自己也打不开）。默认关闭，由 KUXUAN_REQUIRE_AUTH=1 开启。
        if (AUTH_REQUIRE and path.startswith("/api/")
                and not path.startswith("/api/auth/")
                and not path.startswith("/api/ncm/") and not self._auth_user()):
            return self._auth_json({"ok": False, "code": "UNAUTHORIZED",
                                    "error": "请先登录"}, 401)

        # ---------------- 网易云账号（扫码登录 + 个人歌单）
        if path == "/api/ncm/qr/key":
            d, err = online_get("/login/qr/key")
            if err or not d:
                return self._auth_json({"ok": False, "code": "NCM_ERR",
                                        "error": "取二维码密钥失败：" + (err or "空响应")}, 502)
            return self._auth_json({"ok": True, "unikey": d.get("data", {}).get("unikey", "")})
        if path == "/api/ncm/qr/create":
            key = (qs.get("key", [""])[0] or "").strip()
            if not key:
                return self._auth_json({"ok": False, "code": "BAD_PARAM",
                                        "error": "缺少 key"}, 400)
            d, err = online_get("/login/qr/create", {"key": key, "qrimg": "true"})
            if err or not d:
                return self._auth_json({"ok": False, "code": "NCM_ERR",
                                        "error": "生成二维码失败：" + (err or "空响应")}, 502)
            data = d.get("data", {})
            qrimg = data.get("qrimg") or ""
            # 部分版本直接返回完整 data URI，统一规整成可用值
            if qrimg and not qrimg.startswith("data:"):
                qrimg = "data:image/png;base64," + qrimg
            # 重置监控状态并启动后台轮询线程（独立于前端定时器，抗 PWA 挂起）
            with ncm_qr_lock:
                ncm_qr_state["key"] = key
                ncm_qr_state["code"] = 801
                ncm_qr_state["bound"] = False
                ncm_qr_state["error"] = ""
            threading.Thread(target=ncm_qr_monitor, args=(key,),
                            name="ncm-qr", daemon=True).start()
            return self._auth_json({"ok": True,
                                    "qrimg": qrimg,
                                    "qrurl": data.get("qrurl") or ""})
        if path == "/api/ncm/qr/check":
            key = (qs.get("key", [""])[0] or "").strip()
            if not key:
                return self._auth_json({"ok": False, "code": "BAD_PARAM",
                                        "error": "缺少 key"}, 400)
            # 直接读后台监控线程的缓存状态（监控线程已独立轮询 3100 并写会话）
            with ncm_qr_lock:
                st = dict(ncm_qr_state)
            if st.get("key") != key:
                # 前端持有的 key 与服务端当前监控的不一致（已过期/被替换）
                return self._auth_json({"ok": True, "code": 800,
                                        "waiting": False,
                                        "message": "二维码已失效，请刷新"})
            if st.get("bound"):
                return self._auth_json({"ok": True, "bound": True,
                                        "profile": ncm_profile()})
            code = st.get("code", 801)
            if code == "GUEST":
                return self._auth_json({"ok": False, "code": "NCM_GUEST",
                                        "error": st.get("error")
                                                or "登录态异常，请重新扫码"})
            if code == 800:
                return self._auth_json({"ok": True, "code": 800,
                                        "waiting": False,
                                        "message": "二维码已过期，请点击刷新"})
            return self._auth_json({"ok": True, "code": code, "waiting": code != 800,
                                    "message": "等待扫码"})
        if path == "/api/ncm/me":
            return self._auth_json({"ok": True, "bound": ncm_bound(),
                                    "profile": ncm_profile()})
        if path == "/api/ncm/playlists":
            if not ncm_bound():
                return self._auth_json({"ok": False, "code": "NOT_BOUND",
                                        "error": "尚未绑定网易云，请先扫码登录"}, 401)
            d, err = ncm_get("/user/playlist", {"uid": kv_get("ncm_uid")})
            if err or not d:
                return self._auth_json({"ok": False, "code": "NCM_ERR",
                                        "error": "拉取歌单失败：" + (err or "空响应")}, 502)
            playlists = []
            for pl in (d.get("playlist") or []):
                if not isinstance(pl, dict):
                    continue
                creator = (pl.get("creator") or {}).get("nickname") or ""
                playlists.append({
                    "id": str(pl.get("id")),
                    "name": pl.get("name") or "未命名歌单",
                    "cover": pl.get("coverImgUrl") or pl.get("picUrl") or "",
                    "trackCount": int(pl.get("trackCount") or 0),
                    "creator": creator,
                    "specialType": pl.get("specialType") or 0,
                })
            return self._auth_json({"ok": True, "playlists": playlists,
                                    "nickname": kv_get("ncm_nickname") or ""})
        if path == "/api/ncm/unbind":
            ncm_clear()
            return self._auth_json({"ok": True})

        # ---------------- API
        if path == "/api/status":
            return self._json({"ok": True, "library": len(_library),
                               "ip": lan_ip(), "port": PORT, "onlineApi": ONLINE_API,
                               "unsupported": sorted(UNSUPPORTED_EXT)})

        # ---------------- 在线音源
        if path == "/api/online/home":
            return self._json(online_home(
                force=(qs.get("refresh", [""])[0] == "1")))

        if path.startswith("/api/online/playlist/"):
            pid = urllib.parse.unquote(path[len("/api/online/playlist/"):])
            if not pid.isdigit():
                return self._json({"error": "bad id"}, 400)
            return self._json(online_playlist(
                pid, force=(qs.get("refresh", [""])[0] == "1")))

        if path == "/api/online/pic":
            u = (qs.get("u", [""])[0] or "")
            host = (urllib.parse.urlparse(u).hostname or "").lower()
            allowed = (host == "music.126.net" or host.endswith(".music.126.net")
                       or host.endswith(".music.163.com"))
            if not u.startswith(("http://", "https://")) or not allowed:
                return self._json({"error": "bad image host"}, 400)
            try:
                data, ct = online_fetch_bytes(u.replace("http://", "https://", 1))
                return self._bytes(data, ct)
            except Exception:
                return self._bytes(make_cover_svg("♪"), "image/svg+xml")

        if path == "/api/online/status":
            _, _, st = online_songs(force=(qs.get("refresh", [""])[0] == "1"))
            return self._json(st)

        if path == "/api/online/songs":
            songs, charts, st = online_songs(
                force=(qs.get("refresh", [""])[0] == "1"))
            return self._json({"code": 200, "songs": songs,
                               "charts": charts, "status": st})

        if path == "/api/online/search":
            q = (qs.get("q", [""])[0] or "").strip()
            if not q:
                songs, _, st = online_songs()
                return self._json({"code": 200, "songs": songs,
                                   "localFilter": False, "status": st})
            # 3100 的 cloudsearch 已可用：返回真实全网搜索结果
            d, err = online_get("/cloudsearch",
                                {"keywords": q, "type": 1, "limit": 30})
            raws = ((d or {}).get("result") or {}).get("songs") or []
            if raws:
                out = []
                for raw in raws[:30]:
                    s = _norm_song(raw)
                    if s:
                        out.append(s)
                return self._json({"code": 200, "songs": out, "keyword": q,
                                   "remote": True, "localFilter": False})
            # 上游被风控时降级：只在已拉取的真实曲库里过滤，并如实标记
            songs, _, st = online_songs()
            ql = q.lower()
            hits = [s for s in songs
                    if ql in (s["title"] + " " + s["artist"] + " " + s["album"]).lower()]
            return self._json({"code": 200, "songs": hits, "keyword": q,
                               "localFilter": True, "status": st})

        if path == "/api/online/cover/":
            return self._json({"error": "missing id"}, 400)

        if path.startswith("/api/online/cover/"):
            sid = urllib.parse.unquote(path[len("/api/online/cover/"):])
            pic = online_pic_url(sid)
            if not pic:
                return self._bytes(make_cover_svg("♪"), "image/svg+xml")
            try:
                data, ct = online_fetch_bytes(pic.replace("http://", "https://", 1))
                return self._bytes(data, ct)
            except Exception:
                return self._bytes(make_cover_svg("♪"), "image/svg+xml")

        if path.startswith("/api/online/lyric/"):
            sid = urllib.parse.unquote(path[len("/api/online/lyric/"):])
            d, err = online_get("/lyric", {"id": sid})
            text = ((d or {}).get("lrc") or {}).get("lyric") or ""
            return self._bytes(text.encode("utf-8"), "text/plain; charset=utf-8")

        # 歌曲评论：上游 3100 有 /comment/music，这里做只读代理 + 字段清洗。
        # 单机自用版原本没有评论能力（web/app.js 里明确标注未实现），此端点为新增。
        # 只暴露展示所需字段，避免把上游含用户隐私的完整对象透传给客户端。
        if path.startswith("/api/online/comment/"):
            sid = urllib.parse.unquote(path[len("/api/online/comment/"):])
            if not sid.isdigit():
                return self._json({"ok": False, "error": "bad song id"}, 400)
            try:
                limit = max(1, min(int(qs.get("limit", ["20"])[0]), 50))
            except ValueError:
                limit = 20
            try:
                offset = max(0, int(qs.get("offset", ["0"])[0]))
            except ValueError:
                offset = 0
            d, err = online_get("/comment/music",
                                {"id": sid, "limit": limit, "offset": offset})
            if err or not isinstance(d, dict):
                return self._json({"ok": False,
                                   "error": "评论拉取失败：" + (err or "空响应")}, 502)
            if d.get("code") not in (None, 200):
                return self._json({"ok": False,
                                   "error": "上游返回 code=%s" % d.get("code")}, 502)

            def pack_comments(arr):
                out = []
                for c in (arr or []):
                    if not isinstance(c, dict):
                        continue
                    u = c.get("user") if isinstance(c.get("user"), dict) else {}
                    replied = c.get("beReplied")
                    quote = ""
                    if isinstance(replied, dict):
                        quote = str(replied.get("content") or "")
                        ru = replied.get("user")
                        if isinstance(ru, dict) and ru.get("nickname"):
                            quote = "@%s：%s" % (ru.get("nickname"), quote)
                    out.append({
                        "id": str(c.get("commentId") or ""),
                        "user": u.get("nickname") or "匿名用户",
                        "avatar": u.get("avatarUrl") or "",
                        "content": str(c.get("content") or ""),
                        "time": int(c.get("time") or 0),
                        "timeStr": c.get("timeStr") or "",
                        "liked": int(c.get("likedCount") or 0),
                        "quote": quote,
                    })
                return out

            return self._json({
                "ok": True, "id": sid,
                "total": int(d.get("total") or 0),
                # 热评只在第一页返回，翻页时不重复显示
                "hot": pack_comments(d.get("hotComments")) if offset == 0 else [],
                "comments": pack_comments(d.get("comments")),
                "more": bool(d.get("more")),
            })

        if path.startswith("/api/online/resolve/"):
            sid = urllib.parse.unquote(path[len("/api/online/resolve/"):])
            url, meta, reason = online_play_url(sid)
            if url:
                return self._json({
                    "playable": True, "br": meta.get("br"),
                    "level": meta.get("level"), "size": meta.get("size"),
                    # 上游对 VIP 歌曲只给试听片段，如实上报，别让用户以为能听全曲
                    "trial": bool(meta.get("freeTrialInfo")),
                    "fee": meta.get("fee"),
                })
            return self._json({"playable": False, "reason": reason})

        if path.startswith("/api/online/stream/"):
            sid = urllib.parse.unquote(path[len("/api/online/stream/"):])
            level = (qs.get("level", [ONLINE_LEVEL])[0] or ONLINE_LEVEL)
            url, meta, reason = online_play_url(sid, level)
            if not url:
                return self._json({"error": "unplayable", "reason": reason,
                                   "hint": "可浏览真实曲库；播放需解除上游风控或使用本地文件"}, 451)
            # 强制 https，Mac 侧代理转发：手机只连 8765，签名过期也每次重新解析
            target = url.replace("http://", "https://", 1)
            if qs.get("direct", [""])[0] == "1":
                self.send_response(302)
                self.send_header("Location", target)
                self._cors()
                self.end_headers()
                return
            fwd = {"User-Agent": "Mozilla/5.0",
                   "Referer": "https://music.163.com/"}
            if self.headers.get("Range"):
                fwd["Range"] = self.headers.get("Range")
            try:
                up = urllib.request.urlopen(
                    urllib.request.Request(target, headers=fwd), timeout=25)
            except urllib.error.HTTPError as e:
                return self._json({"error": "upstream",
                                   "reason": "音频源 HTTP %s（签名可能过期，重试通常可恢复）" % e.code}, 502)
            except Exception as e:
                return self._json({"error": "upstream", "reason": str(e)[:120]}, 502)
            self.send_response(up.status)
            ct = up.headers.get("Content-Type") or "audio/mpeg"
            # 网易 CDN 会给 audio/mpeg 附上 charset，去掉避免 Safari 误判
            if ct.startswith("audio/"):
                ct = ct.split(";")[0].strip()
            self.send_header("Content-Type", ct)
            for h in ("Content-Length", "Content-Range",
                      "ETag", "Last-Modified"):
                v = up.headers.get(h)
                if v:
                    self.send_header(h, v)
            self.send_header("Accept-Ranges", "bytes")
            self._cors()
            self.end_headers()
            if self.command == "HEAD":
                up.close()
                return
            try:
                while True:
                    chunk = up.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                up.close()
            return

        if path == "/api/songs":
            return self._json({"code": 200, "songs": scan_library()})

        if path == "/api/search":
            q = (qs.get("q", [""])[0] or "").strip().lower()
            songs = scan_library()
            if q:
                songs = [s for s in songs if q in s["title"].lower()
                         or q in s["artist"].lower() or q in s["file"].lower()]
            return self._json({"code": 200, "songs": songs})

        if path.startswith("/api/stream/"):
            sid = path[len("/api/stream/"):]
            song = find_song(sid) or (scan_library() and find_song(sid))
            if not song:
                return self._json({"error": "not found"}, 404)
            fpath = safe_music_path(sid)
            if not fpath:
                return self._json({"error": "bad path"}, 400)
            size = os.path.getsize(fpath)
            ctype = song["mime"]
            start, end = 0, size - 1
            rng = self.headers.get("Range")
            partial = False
            if rng:
                m = re.match(r"bytes=(\d*)-(\d*)", rng.strip())
                if m:
                    partial = True
                    if m.group(1):
                        start = int(m.group(1))
                    if m.group(2):
                        end = min(int(m.group(2)), size - 1)
                    if start > end or start >= size:
                        self.send_response(416)
                        self.send_header("Content-Range", "bytes */%d" % size)
                        self._cors()
                        self.end_headers()
                        return
            length = end - start + 1
            self.send_response(206 if partial else 200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            if partial:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self._cors()
            self.end_headers()
            if self.command == "HEAD":
                return
            try:
                with open(fpath, "rb") as f:
                    f.seek(start)
                    left = length
                    while left > 0:
                        chunk = f.read(min(65536, left))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        left -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        if path.startswith("/api/lyric/"):
            sid = path[len("/api/lyric/"):]
            song = find_song(sid) or (scan_library() and find_song(sid))
            if not song:
                return self._json({"error": "not found"}, 404)
            stem = os.path.splitext(song["file"])[0]
            lp = os.path.join(MUSIC_DIR, stem + ".lrc")
            if os.path.exists(lp):
                with open(lp, "rb") as f:
                    return self._bytes(f.read(), "text/plain; charset=utf-8")
            return self._bytes(b"", "text/plain; charset=utf-8")

        if path.startswith("/api/cover/"):
            sid = path[len("/api/cover/"):]
            song = find_song(sid) or (scan_library() and find_song(sid))
            if not song:
                return self._json({"error": "not found"}, 404)
            stem = os.path.splitext(song["file"])[0]
            for cext in (".jpg", ".jpeg", ".png", ".webp"):
                for base in (MUSIC_DIR, COVER_DIR):
                    p = os.path.join(base, stem + cext)
                    if os.path.exists(p):
                        ct = mimetypes.guess_type(p)[0] or "image/jpeg"
                        with open(p, "rb") as f:
                            return self._bytes(f.read(), ct)
            return self._bytes(make_cover_svg(song["title"]), "image/svg+xml")

        # ---------------- 静态前端
        if path == "/" or path == "":
            path = "/index.html"
        rel = path.lstrip("/")
        if ".." in rel:
            return self._json({"error": "bad path"}, 400)
        fpath = os.path.join(WEB_DIR, rel)
        if not os.path.isfile(fpath):
            return self._json({"error": "404 " + path}, 404)
        ctype = mimetypes.guess_type(fpath)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/javascript", "application/json", "image/svg+xml"):
            ctype += "; charset=utf-8"
        with open(fpath, "rb") as f:
            data = f.read()

        # 首屏内联：把已预热/磁盘恢复的首页数据直接塞进 HTML，
        # 前端无需再发一次 /api/online/home 才能看到内容。
        if rel == "index.html":
            ver = asset_version()
            payload = boot_payload()
            boot = ("window.__KX_BOOT__=" +
                    (json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
                     if payload else "null") + ";")
            inject = ('<script>window.__KX_BUILD__="' + ver + '";</script>\n'
                      '<script>' + boot + '</script>\n'
                      '<script src="app.js?v=' + ver + '"></script>')
            text = (data.decode("utf-8")
                    .replace("__KX_VER__", ver)
                    .replace('<script src="app.js?v=' + ver + '"></script>', inject))
            # 入口页绝不缓存：iOS 主屏 Web App 从后台恢复时会直接复用快照，
            # 只有 no-store + Pragma/Expires 三重声明能把它拉回网络。
            return self._bytes(text.encode("utf-8"),
                               "text/html; charset=utf-8",
                               cache="no-store, no-cache, must-revalidate, max-age=0",
                               extra={"Pragma": "no-cache", "Expires": "0"})

        # 代码 URL 已带内容派生版本号，可安全长缓存；改版后 URL 变化立即生效。
        # 图片/图标走更长缓存，减少每次开屏的重复下载。
        if ctype.startswith("text/css") or ctype.startswith("application/javascript"):
            cc = "public, max-age=600, must-revalidate"
        elif ctype.startswith("image/") or ctype.startswith("audio/"):
            cc = "public, max-age=86400"
        else:
            cc = "no-cache, must-revalidate"
        return self._bytes(data, ctype, cache=cc)


def main():
    os.makedirs(MUSIC_DIR, exist_ok=True)
    os.makedirs(COVER_DIR, exist_ok=True)
    init_db()
    make_demo_tracks()
    scan_library()
    load_home_disk()                      # 先恢复磁盘缓存，首屏立即可用
    threading.Thread(target=warmup, daemon=True).start()  # 后台刷新，不阻塞监听
    ip = lan_ip()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    print("=" * 58, flush=True)
    print("  KuXuan Music  本地服务已启动", flush=True)
    print("  本机:     http://127.0.0.1:%d" % PORT, flush=True)
    print("  iPhone:   http://%s:%d   (需同一 WiFi)" % (ip, PORT), flush=True)
    print("  曲库目录: %s" % MUSIC_DIR, flush=True)
    print("  账号:     注册%s · 强制登录%s · 已有 %d 个账号" % (
        "开放" if AUTH_ALLOW_REGISTER else "关闭",
        "开" if AUTH_REQUIRE else "关", auth_status()["userCount"]), flush=True)
    print("  按 Ctrl+C 停止", flush=True)
    print("=" * 58, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log("服务已停止")
        srv.shutdown()


if __name__ == "__main__":
    main()
