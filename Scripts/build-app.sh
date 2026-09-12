#!/bin/bash
# 组装 MiVibe.app。
#
# 本机只有 Command Line Tools（无 Xcode），所以 xcodebuild 不可用：
# SwiftPM 编译出裸可执行文件，bundle 由这里手工搭。
#
# 用法：Scripts/build-app.sh [debug|release]
#
# 签名：默认 ad-hoc（-s -）。ad-hoc 的签名标识每次重编都变，macOS 会因此反复
# 要求重新授权辅助功能。想一次授权长期有效，需要一个**固定的自签名身份**：
#   1. 打开「钥匙串访问」→ 证书助理 → 创建证书
#   2. 名称 MiVibe Self Signed，身份类型「自签名根」，证书类型「代码签名」
#   3. 然后 export MIVIBE_SIGN_IDENTITY="MiVibe Self Signed" 再跑本脚本
# 这一步需要图形界面操作，脚本不代劳。

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MiVibe.app"
IDENTITY="${MIVIBE_SIGN_IDENTITY:--}"

cd "$ROOT"

echo "▸ 编译（${CONFIG}）"
swift build -c "$CONFIG" --product MiVibe

BINARY="$(swift build -c "$CONFIG" --product MiVibe --show-bin-path)/MiVibe"
[ -f "$BINARY" ] || { echo "找不到可执行文件：$BINARY" >&2; exit 1; }

echo "▸ 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MiVibe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>MiVibe</string>
	<key>CFBundleDisplayName</key>
	<string>MiVibe</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.taliove.mivibe</string>
	<key>CFBundleExecutable</key>
	<string>MiVibe</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<!-- 菜单栏常驻，不进 Dock、无主窗口 -->
	<key>LSUIElement</key>
	<true/>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>MiVibe 需要蓝牙来接收小米遥控器的语音与按键。</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>语音来自遥控器麦克风，不使用本机麦克风。</string>
	<key>NSHumanReadableCopyright</key>
	<string>个人使用</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" > /dev/null

echo "▸ 签名（identity: ${IDENTITY}）"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP" 2>&1 | sed 's/^/  /'
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'

if [ "$IDENTITY" = "-" ]; then
  echo
  echo "⚠️  ad-hoc 签名：每次重编都会重新要求授权辅助功能。"
  echo "   固定身份的做法见本脚本顶部注释。"
fi

echo
echo "✅ $APP"
echo "   运行：open '$APP'"
