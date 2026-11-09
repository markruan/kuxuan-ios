#!/bin/bash
# 双击运行：一键建仓 → 云端编译 → 下载 IPA
cd "$(dirname "$0")" || exit 1
clear
echo "=============================================="
echo "  KuXuan iOS · 一键编译"
echo "=============================================="
echo ""
echo "本脚本会："
echo "  1. 用你的 GitHub 账号建一个公开仓库并上传工程"
echo "  2. 触发 GitHub Actions 云端编译（本机无需 Xcode）"
echo "  3. 自动下载编译好的 KuXuan-unsigned.ipa 到「下载」文件夹"
echo ""
echo "需要：一个 GitHub PAT（勾选 repo 权限）"
echo "      https://github.com/settings/tokens"
echo ""
echo "说明：token 只用于本次 API 调用，不回显、不写盘、不上传给第三方。"
echo "      编译约 5–15 分钟，请保持这个窗口开着。"
echo ""
python3 one_click.py
echo ""
echo "=============================================="
echo "按回车键关闭窗口..."
read -r _
