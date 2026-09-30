#!/bin/bash
# 把 build/MiVibe.app 打成可分发的 DMG（拖进「应用程序」即安装）。
#
# 用法：Scripts/make-dmg.sh            # 需先跑 Scripts/build-app.sh release
# 产物：build/MiVibe-<版本>-arm64.dmg，版本取自 bundle 的 CFBundleShortVersionString。
#
# 只用系统自带的 hdiutil，不依赖 create-dmg 等第三方工具，CI 与本机同一条路径。
# 不做 Finder 窗口布局（背景图、图标位置）：那需要 AppleScript 驱动 Finder，
# 在无图形会话的 CI 上不可靠。卷里放 App、指向 /Applications 的替身和一份安装说明。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MiVibe.app"
[ -d "$APP" ] || { echo "找不到 $APP，先运行 Scripts/build-app.sh release" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/MiVibe" | tr ' ' '-')"
DMG="$ROOT/build/MiVibe-${VERSION}-${ARCH}.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "▸ 准备 DMG 内容（${VERSION}，${ARCH}）"
# ditto 保留签名与扩展属性；cp -R 可能破坏 bundle 签名。
ditto "$APP" "$STAGING/MiVibe.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明 · Install.txt" <<'TXT'
MiVibe 安装说明

1. 把 MiVibe 拖到「Applications / 应用程序」文件夹。
2. 首次打开若提示"无法验证开发者"：打开「系统设置 → 隐私与安全性」，
   在页面底部点「仍要打开」。
   也可以在终端执行下面这行，去掉下载隔离标记后再打开：
     xattr -dr com.apple.quarantine /Applications/MiVibe.app
3. 按应用内提示授予蓝牙、辅助功能等权限。

Install

1. Drag MiVibe into the Applications folder.
2. If macOS says the developer cannot be verified, open System Settings →
   Privacy & Security and click "Open Anyway". Or run this in Terminal
   to remove the download quarantine flag:
     xattr -dr com.apple.quarantine /Applications/MiVibe.app
3. Grant Bluetooth, Accessibility and the other permissions MiVibe asks for.
TXT

echo "▸ 生成 DMG"
rm -f "$DMG"
hdiutil create -volname "MiVibe ${VERSION}" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo "✅ $DMG"
