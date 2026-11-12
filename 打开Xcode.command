#!/bin/bash
# 打开 KuXuan Xcode 工程（已绕过 Homebrew：xcodegen 装在 ~/bin）
set -e
cd "$(dirname "$0")"

# 让 ~/bin 里的 xcodegen 可被找到（无需 Homebrew）
export PATH="$HOME/bin:$PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "仍未找到 xcodegen，请确认 ~/bin/xcodegen 存在"
  exit 1
fi

echo "正在用 xcodegen 生成 Xcode 工程…"
xcodegen generate

# 检查是否安装了完整的 Xcode.app（命令行工具无法编译/运行 iOS App）
if [ ! -d "/Applications/Xcode.app" ]; then
  echo ""
  echo "⚠️  未检测到完整 Xcode.app（本机只有 Command Line Tools，无法编译 iOS App）。"
  echo "请先从甲 mac App Store 安装 Xcode（约 7GB），安装完成后再运行本脚本。"
  echo "安装后首次打开 Xcode 需同意许可并安装 iOS 组件。"
  exit 1
fi

echo "生成完成，正在打开 KuXuan.xcodeproj…"
open KuXuan.xcodeproj
