#!/usr/bin/env bash
# 组装发布说明：CHANGELOG.md 中对应版本的「本版更新 / What's New」在前，
# .github/release-notes.md 的下载与安装说明在后。
#
# 用法：Scripts/release-notes.sh <版本号，如 0.4.0> [输出文件]
# CHANGELOG 缺少该版本一节时以非零退出，发布流程借此拒绝发出空说明。
set -euo pipefail

VERSION="${1:?usage: Scripts/release-notes.sh <version> [out]}"
OUT="${2:-/dev/stdout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
TEMPLATE="$ROOT/.github/release-notes.md"

# 取 `## [VERSION]` 到下一个二级标题之间的内容（不含标题行本身）。
SECTION="$(awk -v v="$VERSION" '
  index($0, "## [" v "]") == 1 { found = 1; next }
  found && /^## / { exit }
  found { print }
' "$CHANGELOG")"

if [ -z "$(printf '%s' "$SECTION" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md has no section for [$VERSION]; add one before releasing." >&2
  exit 1
fi

[ "$OUT" = /dev/stdout ] || mkdir -p "$(dirname "$OUT")"

{
  printf '%s\n\n' "$SECTION" | sed -e '/./,$!d'
  sed "s/{{VERSION}}/${VERSION}/g" "$TEMPLATE"
} > "$OUT"
