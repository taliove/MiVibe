#!/bin/bash
# 一键重新编译、打包、安装到 /Applications 并启动。
#
# 用法：Scripts/deploy.sh [debug|release]

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

echo "▸ 关闭旧进程"
pkill -x MiVibe 2>/dev/null || true
sleep 0.5

echo "▸ 编译并打包（${CONFIG}）"
Scripts/build-app.sh "$CONFIG"

echo "▸ 安装到 /Applications"
rm -rf /Applications/MiVibe.app
cp -R build/MiVibe.app /Applications/

echo "▸ 启动"
open /Applications/MiVibe.app
sleep 2

if pgrep -x MiVibe > /dev/null; then
  echo "✅ MiVibe 已启动"
else
  echo "⚠️  进程未找到，可能启动失败"
fi
