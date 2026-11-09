#!/usr/bin/env python3
"""检测 USB 连接的 iPhone 是否完成「信任此电脑」，并读取设备信息。

纯 Python 标准库实现 usbmuxd + lockdown 协议，
不依赖 Xcode / libimobiledevice / 管理员权限。

用法: python3 check_device.py
"""
import plistlib
import socket
import struct
import sys

USBMUX = "/var/run/usbmuxd"
LOCKDOWN_PORT = 62078


def mux(pl, keep=False):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(8)
    s.connect(USBMUX)
    body = plistlib.dumps(pl, fmt=plistlib.FMT_XML)
    s.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, 1) + body)
    hdr = b""
    while len(hdr) < 16:
        c = s.recv(16 - len(hdr))
        if not c:
            break
        hdr += c
    if len(hdr) < 16:
        s.close()
        raise RuntimeError("usbmuxd 无响应")
    total = struct.unpack("<I", hdr[:4])[0]
    data = b""
    while len(data) < total - 16:
        c = s.recv(total - 16 - len(data))
        if not c:
            break
        data += c
    resp = plistlib.loads(data) if data else {}
    if not keep:
        s.close()
        return resp, None
    return resp, s


def ld_send(s, pl):
    b = plistlib.dumps(pl, fmt=plistlib.FMT_XML)
    s.sendall(struct.pack(">I", len(b)) + b)


def ld_recv(s):
    hdr = b""
    while len(hdr) < 4:
        c = s.recv(4 - len(hdr))
        if not c:
            raise RuntimeError("lockdown 连接中断")
        hdr += c
    n = struct.unpack(">I", hdr)[0]
    buf = b""
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c:
            break
        buf += c
    return plistlib.loads(buf) if buf else {}


def main():
    print("=== KuXuan 设备检测 ===\n")
    try:
        listing, _ = mux({
            "MessageType": "ListDevices",
            "ClientVersionString": "kuxuan-check",
            "ProgName": "kuxuan",
            "kLibUSBMuxVersion": 3,
        })
    except Exception as e:
        print("❌ 无法连接 usbmuxd：%s" % e)
        print("   请确认 iPhone 已用数据线连接 Mac（不是仅充电线）。")
        return 1

    devs = listing.get("DeviceList", [])
    if not devs:
        print("❌ 未检测到 iPhone。请插上数据线，并在手机上点「信任此电脑」。")
        return 1

    dev = devs[0]
    props = dev.get("Properties", {})
    did = dev.get("DeviceID")
    udid = props.get("SerialNumber", "?")
    print("✅ USB 已连接")
    print("   DeviceID : %s" % did)
    print("   UDID     : %s" % udid)

    # 关键：能否读到配对记录 = 手机是否已点「信任」
    pair = None
    try:
        r, _ = mux({
            "MessageType": "ReadPairRecord",
            "PairRecordID": udid,
            "ClientVersionString": "kuxuan-check",
            "ProgName": "kuxuan",
            "kLibUSBMuxVersion": 3,
        })
        raw = r.get("PairRecordData")
        if raw:
            pair = plistlib.loads(raw)
    except Exception as e:
        print("   （读取配对记录失败：%s）" % e)

    if not pair:
        print("\n⚠️ 尚未完成信任配对（本机无配对记录）")
        print("   请在 iPhone 上：解锁 → 拔掉数据线重插 → 弹窗点「信任」→ 输入锁屏密码")
        print("   点完后再运行本脚本，直到显示「✅ 已完成信任配对」。")
        return 2
    print("\n✅ 已完成信任配对（Mac 与 iPhone 已可交换数据）")
    print("   HostID   : %s" % str(pair.get("HostID", "?"))[:40])

    # 建立 lockdown 会话读取设备详情
    try:
        r, s = mux({
            "MessageType": "Connect",
            "DeviceID": did,
            "PortNumber": socket.htons(LOCKDOWN_PORT),
            "ClientVersionString": "kuxuan-check",
            "ProgName": "kuxuan",
            "kLibUSBMuxVersion": 3,
        }, keep=True)
        if r.get("Number", -1) != 0:
            raise RuntimeError("usbmuxd Connect 失败：%s" % r)
        ld_send(s, {"Label": "kuxuan", "Request": "QueryType", "ProtocolVersion": "2"})
        q = ld_recv(s)
        if q.get("Type") != "com.apple.mobile.lockdown":
            raise RuntimeError("不是 lockdown 服务：%s" % q.get("Type"))

        ld_send(s, {
            "Label": "kuxuan", "Request": "StartSession",
            "HostID": pair.get("HostID"), "SystemBUID": pair.get("SystemBUID"),
        })
        sess = ld_recv(s)
        if sess.get("Error"):
            print("   ⚠️ StartSession: %s" % sess["Error"])
        session_id = sess.get("SessionID")

        req = {"Label": "kuxuan", "Request": "GetValue"}
        if session_id:
            req["SessionID"] = session_id
        for key in ("DeviceName", "ProductType", "ProductVersion", "BuildVersion",
                    "UniqueDeviceID", "ModelNumber", "DeveloperModeStatus"):
            q = dict(req)
            q["Key"] = key
            ld_send(s, q)
            v = ld_recv(s).get("Value")
            if v is not None:
                print("   %-20s: %s" % (key, v))
        s.close()
    except Exception as e:
        print("   （读取设备详情失败：%s，不影响配对结论）" % e)

    print("\n结论：USB 信任链路已就绪，可以用 Sideloadly 通过数据线安装 App。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
