#!/bin/bash
# 组装 MiVibe.app。
#
# 本机只有 Command Line Tools（无 Xcode），所以 xcodebuild 不可用：
# SwiftPM 编译出裸可执行文件，bundle 由这里手工搭。
#
# 用法：Scripts/build-app.sh [debug|release]
#
# 签名：默认用 `Scripts/setup-signing.sh` 建的本地自签身份。为什么必须是固定身份，
# 见那支脚本的头部注释——一句话：ad-hoc 签名的 designated requirement 是二进制哈希，
# 改一行代码就变，macOS 会把重编后的 app 当成陌生程序，反复要授权。
# 身份不存在时退回 ad-hoc，并把后果明确喊出来。

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MiVibe.app"

SIGNING_KEYCHAIN="$HOME/Library/Keychains/mivibe-signing.keychain-db"
SIGNING_PASSFILE="$HOME/.config/mivibe/signing-password"
LOCAL_IDENTITY="MiVibe Local Signing"

# 身份优先级：环境变量 > 本地自签身份 > ad-hoc。
if [ -n "${MIVIBE_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$MIVIBE_SIGN_IDENTITY"
elif [ -f "$SIGNING_KEYCHAIN" ] && [ -f "$SIGNING_PASSFILE" ] \
     && security find-identity -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
  IDENTITY="$LOCAL_IDENTITY"
  # codesign 要用私钥，得先解锁并确保钥匙串在搜索列表里。
  security unlock-keychain -p "$(cat "$SIGNING_PASSFILE")" "$SIGNING_KEYCHAIN" 2>/dev/null || true
  if ! security list-keychains -d user | grep -q "mivibe-signing"; then
    security list-keychains -d user -s "$SIGNING_KEYCHAIN" $(security list-keychains -d user | tr -d ' "')
  fi
else
  IDENTITY="-"
fi

cd "$ROOT"

# 本地识别引擎的 vendored 源码（不存在时拉取，钉死 SHA256，见脚本头部注释）。
if [ ! -d "$ROOT/Vendor/whisper.cpp" ]; then
  echo "▸ 拉取 whisper.cpp 源码"
  "$ROOT/Scripts/fetch-whisper.sh"
fi

echo "▸ 编译（${CONFIG}）"
swift build -c "$CONFIG" --product MiVibe

BINARY="$(swift build -c "$CONFIG" --product MiVibe --show-bin-path)/MiVibe"
[ -f "$BINARY" ] || { echo "找不到可执行文件：$BINARY" >&2; exit 1; }

echo "▸ 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MiVibe"

# SwiftPM 把 .process("Resources") 打成 MiVibe_MiVibe.bundle 放在可执行文件旁边，
# 而 .app 的 Bundle.main 找资源要去 Contents/Resources——不拷的话 AppIcon.icns
# 不在 CFBundleIconFile 指向的位置，打包后的 App 就没有图标。
RESOURCE_BUNDLE="$(dirname "$BINARY")/MiVibe_MiVibe.bundle"
if [ -d "$RESOURCE_BUNDLE/Contents/Resources" ]; then
  cp -R "$RESOURCE_BUNDLE/Contents/Resources/" "$APP/Contents/Resources/"
elif [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE/" "$APP/Contents/Resources/"
fi

# whisper.cpp 的 Metal 内核是运行时编译的（本机没有 metal 编译器）：ggml 从
# mainBundle 找 kernels/*.metal 与 flatten 所需的头文件（ggml-common.h、
# ggml-metal-impl.h 须在 Resources 根，与 kernels/ 平级——flatten 的搜索路径是
# 内核文件所在目录、其父、其祖父）。
WHISPER_BUNDLE="$(dirname "$BINARY")/MiVibe_CWhisper.bundle"
if [ -d "$WHISPER_BUNDLE" ]; then
  cp -R "$WHISPER_BUNDLE/kernels" "$APP/Contents/Resources/"
  cp "$WHISPER_BUNDLE/ggml-common.h" "$WHISPER_BUNDLE/ggml-metal-impl.h" "$APP/Contents/Resources/"
else
  echo "⚠️  未找到 MiVibe_CWhisper.bundle，本地识别的 Metal 加速将不可用（回落 CPU）"
fi

# 分发二进制须附带第三方许可（whisper.cpp 为 MIT），与本项目许可一起放进 Resources。
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

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
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.5.0</string>
	<key>CFBundleVersion</key>
	<string>6</string>
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

# 把签名身份说清楚：锚在证书上 = 授权能活；锚在 cdhash 上 = 下次重编又要重授权。
REQ="$(codesign -d -r- "$APP" 2>/dev/null | tail -1)"
echo "  签名锚点：${REQ#\# }"
if printf '%s' "$REQ" | grep -q 'cdhash'; then
  echo
  echo "⚠️  当前是 ad-hoc 签名，designated requirement 锚在二进制哈希上——"
  echo "   每次重编 macOS 都会当成新 app，重新要一遍辅助功能授权。"
  echo "   跑一次 Scripts/setup-signing.sh 建个固定的自签身份即可根治。"
elif [ "$IDENTITY" = "-" ]; then
  echo
  echo "⚠️  指定了 ad-hoc 签名（MIVIBE_SIGN_IDENTITY=-），同理会反复要授权。"
fi

echo
echo "✅ $APP"
echo "   运行：open '$APP'"
