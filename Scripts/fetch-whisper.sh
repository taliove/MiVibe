#!/bin/zsh
# 拉取 whisper.cpp 源码到 Vendor/whisper.cpp（gitignore，不入库）。
#
# 为什么用 tarball 而不是 git submodule：本仓库的构建环境只有 Command Line Tools，
# tarball + 钉死 SHA256 对 CI 和本地都最少意外。升级版本时改 VERSION 与 SHA256 两个值。
#
# 用法：Scripts/fetch-whisper.sh [--force]
#   已存在且版本匹配时跳过；--force 强制重下。
set -euo pipefail

VERSION="v1.9.4"
SHA256="57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/Vendor"
TARGET_DIR="$VENDOR_DIR/whisper.cpp"
STAMP="$TARGET_DIR/.mivibe-version"
TARBALL="$VENDOR_DIR/whisper.cpp-$VERSION.tar.gz"

if [[ "${1:-}" != "--force" && -f "$STAMP" && "$(cat "$STAMP")" == "$VERSION" ]]; then
    echo "whisper.cpp $VERSION 已就绪：$TARGET_DIR"
    exit 0
fi

mkdir -p "$VENDOR_DIR"

echo "下载 whisper.cpp $VERSION ..."
curl -fSL --retry 3 -o "$TARBALL" \
    "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$VERSION.tar.gz"

ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [[ "$ACTUAL" != "$SHA256" ]]; then
    rm -f "$TARBALL"
    echo "错误：SHA256 校验失败（期望 $SHA256，实际 $ACTUAL）" >&2
    exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xzf "$TARBALL" -C "$TARGET_DIR" --strip-components 1
rm -f "$TARBALL"

# SwiftPM 的 publicHeadersPath（include/）对下游只暴露本目录；whisper.h 引用的
# ggml 头文件实际在 ggml/include/，SPM 的 headerSearchPath 不会传播给模块导入方。
# 用符号链接把公共头拉平进 include/，让 CWhisper 模块可被 Swift 正常 import。
for header in ggml.h ggml-cpu.h ggml-alloc.h ggml-backend.h ggml-opt.h gguf.h; do
    ln -sf "../ggml/include/$header" "$TARGET_DIR/include/$header"
done

echo "$VERSION" > "$STAMP"
echo "完成：$TARGET_DIR"
