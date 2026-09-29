#!/bin/bash
# 一次性创建本地代码签名身份，让 macOS 权限授权能跨重新编译存活。
#
# 为什么需要：macOS 的隐私授权（辅助功能、蓝牙）不是记在「app 叫什么」上，而是记在
# 代码签名推导出的 **designated requirement** 上。ad-hoc 签名（`codesign -s -`）没有
# 证书可锚定，DR 只能退化成二进制自身的哈希（cdhash）——
#
#     designated => cdhash H"65731d93…"      ← 改一行代码就变
#
# 于是每次重编，系统都当成一个全新的 app，重新要授权。用一张**固定的自签证书**签名后，
# DR 变成锚定在证书上：
#
#     designated => identifier "io.github.taliove.mivibe" and certificate root = H"bd9a9c19…"
#
# 证书不变，重编多少次都算同一个 app，授权一次长期有效。
#
# 本脚本全程命令行，不需要 Xcode，不需要 Apple 开发者账号，不需要图形界面。
# 证书**故意不标为受信任**——它的作用只是当个稳定的锚点，不该让系统上别的东西也信任它。
# codesign 接受未受信任的证书（已实测）。
#
# 用法：
#   Scripts/setup-signing.sh          # 创建（已存在则跳过，绝不重建）
#   Scripts/setup-signing.sh --status # 只看现状
#
# **证书一旦重建，锚点哈希就变，所有已授权限作废。** 所以本脚本幂等且从不覆盖。

set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/mivibe-signing.keychain-db"
PASSFILE="$HOME/.config/mivibe/signing-password"
CERT_CN="MiVibe Local Signing"
VALIDITY_DAYS=3650

status() {
  echo "钥匙串：$KEYCHAIN"
  if [ ! -f "$KEYCHAIN" ]; then
    echo "  状态：不存在"
    return 1
  fi
  echo "  状态：已存在"
  echo "身份："
  security find-identity -p codesigning "$KEYCHAIN" 2>&1 | sed 's/^/  /'
  if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_CN"; then
    return 0
  fi
  return 1
}

if [ "${1:-}" = "--status" ]; then
  status || true
  echo ""
  echo "搜索列表中的自签钥匙串："
  security list-keychains -d user | grep -i mivibe || echo "  （无）"
  exit 0
fi

echo "▸ MiVibe 本地签名身份"
echo ""

if status; then
  echo ""
  echo "✅ 身份已存在，不做任何改动。"
  echo "   证书就是权限的锚点，重建会让所有已授权限作废，所以这里绝不覆盖。"
  echo "   要彻底重来，先手动删掉钥匙串再跑本脚本。"
  exit 0
fi

echo ""
echo "▸ 创建钥匙串与自签证书"
mkdir -p "$(dirname "$PASSFILE")"

# 密码只用于保护这个专用钥匙串；存在 600 的文件里，供构建脚本解锁用。
if [ -f "$PASSFILE" ]; then
  KC_PASS="$(cat "$PASSFILE")"
  echo "  沿用已有密码文件"
else
  KC_PASS="$(openssl rand -base64 24)"
  (umask 077; printf '%s' "$KC_PASS" > "$PASSFILE")
  echo "  已生成密码 → ${PASSFILE}（权限 600）"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 注意：**不要**在 -addext 里再写 basicConstraints。`openssl req -x509` 会自动加上一条
# critical 的 Basic Constraints，重复的那条会让证书带上 security 框架不认识的 critical
# 扩展，结果是 codesign 报 "no identity found"——证书看上去一切正常，就是用不了。
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days "$VALIDITY_DAYS" \
  -subj "/CN=$CERT_CN/O=MiVibe/C=US" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" > /dev/null 2>&1

# 上次跑到一半中断时钥匙串可能已存在（但里面没有身份）：只解锁，不重建。
if [ -f "$KEYCHAIN" ]; then
  echo "  钥匙串已存在（身份缺失），沿用"
else
  security create-keychain -p "$KC_PASS" "$KEYCHAIN"
fi
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

# OpenSSL 3 生成的 p12 默认用 SHA256 MAC，Security 框架不认，import 报
# "MAC verification failed"；LibreSSL（macOS 自带）没有 -legacy 选项但默认就兼容。
# 探测一次，支持就加。
PKCS12_FLAGS=()
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
  PKCS12_FLAGS=(-legacy)
fi
openssl pkcs12 -export "${PKCS12_FLAGS[@]}" -out "$WORK/id.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout "pass:$KC_PASS" -name "$CERT_CN" > /dev/null 2>&1
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$KC_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security

# 放行 codesign 使用这把私钥，避免每次签名弹授权框。
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KC_PASS" "$KEYCHAIN" > /dev/null 2>&1

# 加进用户搜索列表（追加，不替换）。
EXISTING="$(security list-keychains -d user | tr -d ' "')"
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo ""
status
echo ""
echo "✅ 完成。之后跑 Scripts/build-app.sh（或 deploy.sh）会自动用它签名。"
echo ""
echo "⚠️  切到固定身份后，系统会**再要一次**授权——因为签名变了，旧授权绑在 ad-hoc 的"
echo "    cdhash 上。这一次之后就不再反复要了。"
echo "   系统设置 → 隐私与安全性 → 辅助功能里可能同时躺着新旧两个「MiVibe」条目，"
echo "   把旧的（ad-hoc 留下的）删掉，只保留能用的那个。"
