#!/usr/bin/env bash
#
# 把 Apple 签发的 Developer ID Application 证书导入钥匙串，并绑定私钥。
#
# 用法：
#   ./scripts/import-developer-id.sh ~/Downloads/DeveloperIDApplication.cer
#
# 关键点：私钥是 openssl 生成的 PEM，Apple 只发了 .cer 公钥部分。
# 必须把「私钥 + 证书 + Apple 中间证书」打包成 p12 再导入，
# 否则 keychain 里会出现一张没有私钥的证书 —— 那种证书
# codesign 认不出身份，等于没装（find-identity 也不会列出来）。
set -euo pipefail

CER="${1:?用法: $0 <DeveloperIDApplication.cer>}"
KEY="${2:-$HOME/Desktop/WinPaint-DID/WinPaint-DID.key}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$CER" ]] || { echo "找不到证书文件: $CER" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "找不到私钥: $KEY" >&2; exit 1; }

echo "==> 读取证书主体"
openssl x509 -inform der -in "$CER" -noout -subject -dates 2>/dev/null \
  || openssl x509 -in "$CER" -noout -subject -dates 2>/dev/null \
  || { echo "证书解析失败（既不是 DER 也不是 PEM）" >&2; exit 1; }

# Apple 中间证书：Developer ID 证书的签发者，需要进 p12 才能验通
WWDR="https://www.apple.com/certificateauthority/AppleWWDRCA.cer"
echo "==> 取 Apple WWDR 中间证书"
curl -fsSL -o "$WORK/wwdr.cer" "$WWDR"

# .cer 可能是 DER 也可能是 PEM，统一转成 PEM
if openssl x509 -inform der -in "$CER" -out "$WORK/cert.pem" 2>/dev/null; then
  :
else
  cp "$CER" "$WORK/cert.pem"
fi
if openssl x509 -inform der -in "$WORK/wwdr.cer" -out "$WORK/wwdr.pem" 2>/dev/null; then
  :
else
  cp "$WORK/wwdr.cer" "$WORK/wwdr.pem"
fi

echo "==> 打包 p12（私钥 + 证书链）"
PP12_PASS="$(openssl rand -base64 18)"
openssl pkcs12 -export \
  -inkey "$KEY" \
  -in "$WORK/cert.pem" \
  -certfile "$WORK/wwdr.pem" \
  -out "$WORK/id.p12" \
  -passout "pass:${PP12_PASS}" \
  -name "Developer ID Application"

echo "==> 导入钥匙串"
security import "$WORK/id.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PP12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

# 让私钥允许 codesign 使用
echo "==> 设置私钥 ACL（允许 codesign 访问）"
KEY_ID="$(security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PP12_PASS" -T /usr/bin/codesign -A -f pkcs12 2>&1 \
  | grep -oE 'SHA-1 hash: [0-9a-f]+' | grep -oE '[0-9a-f]{40}' | head -1 || true)"
if [[ -n "$KEY_ID" ]]; then
  security set-key-partition-list -S apple-tool:,apple: \
    -s "$KEY_ID" "$HOME/Library/Keychains/login.keychain-db" \
    >/dev/null 2>&1 || true
fi

echo
echo "==> 当前 codesigning 身份"
security find-identity -v -p codesigning

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo
  echo "✅ Developer ID Application 已就位，可以签名公证了："
  echo "   ./scripts/build-app.sh release && ./scripts/notarize.sh AC_PASSWORD"
else
  echo
  echo "⚠️  还没看到 'Developer ID Application'。"
  echo "   多半是私钥没绑上，或钥匙串拒绝了导入。检查："
  echo "   security list-keychains && security import 报的具体错误"
fi
