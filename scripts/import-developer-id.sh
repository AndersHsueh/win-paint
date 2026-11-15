#!/usr/bin/env bash
#
# 把 Apple 签发的 Developer ID Application 证书导入钥匙串,并绑定私钥。
#
# 用法:
#   ./scripts/import-developer-id.sh ~/Downloads/developerID_application.cer
#
# 关键点 1:私钥是 openssl 生成的 PEM,Apple 只发了 .cer 公钥部分。
#   必须把「私钥 + 证书 + 中间证书」打包成 p12 再导入,
#   否则钥匙串里会出现一张没有私钥的证书 —— 那种证书 codesign 认不出身份,
#   等于没装(find-identity 也不会列出来)。
#
# 关键点 2:中间证书要**按签发方匹配**,不能瞎拿一张。
#   Apple 现在给 Developer ID Application 用的签发方是
#   「Developer ID Certification Authority (G2)」,
#   **不是**那个 WWDR 的 —— 拿错了链就断了。
#
# 关键点 3:中间证书优先用 **Xcode 自带的那份**。
#   www.apple.com/certificateauthority/ 在墙内直接 403,
#   但 Xcode 装了 DeveloperIDCA-G2.cer,离线就有。
set -euo pipefail

CER="${1:?用法: $0 <DeveloperIDApplication.cer>}"
KEY="${2:-$HOME/Desktop/WinPaint-DID/WinPaint-DID.key}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$CER" ]] || { echo "找不到证书文件: $CER" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "找不到私钥: $KEY" >&2; exit 1; }

# 把 .cer 统一转成 PEM(.cer 既可能是 DER 也可能是 PEM)
if openssl x509 -inform der -in "$CER" -out "$WORK/leaf.pem" 2>/dev/null; then
  :
else
  openssl x509 -in "$CER" -out "$WORK/leaf.pem"
fi

echo "==> 证书"
openssl x509 -in "$WORK/leaf.pem" -noout -subject -issuer -dates | sed 's/^/    /'

# 从 openssl 的 "issuer=..." / "subject=..." 行里取 CN= 和 OU=
#
# ⚠️ 两个坑:
#   - openssl 输出的是 `issuer=CN=...,OU=...`(前缀带 "issuer="),
#     所以先 sed 掉前缀再按逗号切
#   - 切出来的段可能没有也可能有空格,grep 要容忍
#   - 取不到就让 pick 返回空,**不能**让它非零退出 ——
#     `set -e` 会把整个脚本带走(这坑踩过)
pick() {
  echo "$1" \
    | sed 's/^[^=]*=//' \
    | tr ',' '\n' \
    | grep -E "^[[:space:]]*$2=" \
    | head -1 \
    | sed "s/.*$2=//; s/^[[:space:]]*//; s/[[:space:]]*$//" \
    || true
}

leaf_issuer="$(openssl x509 -in "$WORK/leaf.pem" -noout -issuer)"
want_cn="$(pick "$leaf_issuer" CN)"
want_ou="$(pick "$leaf_issuer" OU)"
echo "    签发方:CN=$want_cn  OU=$want_ou"

# ---------------------------------------------------------------------------
# 找中间证书
# ---------------------------------------------------------------------------
echo
echo "==> 找中间证书(按签发方匹配)"

XCODE_CERTS=(
  "/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/DeveloperIDCA-G2.cer"
  "/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/DeveloperIDCA.cer"
  "/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/AppleWWDRCAG6.cer"
  "/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/AppleWWDRCA-2030.cer"
)

INTERMEDIATE=""
for f in "${XCODE_CERTS[@]}"; do
  [[ -f "$f" ]] || continue
  subj="$(openssl x509 -inform der -in "$f" -noout -subject 2>/dev/null \
       || openssl x509 -in "$f" -noout -subject 2>/dev/null)" || continue
  cn="$(pick "$subj" CN)"
  ou="$(pick "$subj" OU)"
  if [[ "$cn" == "$want_cn" && "$ou" == "$want_ou" ]]; then
    echo "    ✅ 命中 Xcode 自带副本:$f"
    echo "       subject=$subj"
    if openssl x509 -inform der -in "$f" -out "$WORK/chain.pem" 2>/dev/null; then
      :
    else
      cp "$f" "$WORK/chain.pem"
    fi
    INTERMEDIATE="$WORK/chain.pem"
    break
  fi
done

# 兜底:从 Apple CDN 下(墙内通常 403)
if [[ -z "$INTERMEDIATE" ]]; then
  echo "    本机没有匹配的,试 Apple CDN…"
  for url in \
    "https://www.apple.com/certificateauthority/DeveloperIDCertificationAuthority.cer" \
    "https://www.apple.com/certificateauthority/AppleWWDRCA.cer"
  do
    if curl -fsSL -o "$WORK/dl.cer" "$url" 2>/dev/null; then
      subj="$(openssl x509 -inform der -in "$WORK/dl.cer" -noout -subject 2>/dev/null \
           || openssl x509 -in "$WORK/dl.cer" -noout -subject 2>/dev/null)" || continue
      cn="$(pick "$subj" CN)"; ou="$(pick "$subj" OU)"
      if [[ "$cn" == "$want_cn" && "$ou" == "$want_ou" ]]; then
        echo "    ✅ 命中 CDN:$url"
        openssl x509 -inform der -in "$WORK/dl.cer" -out "$WORK/chain.pem" 2>/dev/null \
          || cp "$WORK/dl.cer" "$WORK/chain.pem"
        INTERMEDIATE="$WORK/chain.pem"
        break
      fi
    fi
  done
fi

if [[ -z "$INTERMEDIATE" ]]; then
  echo "    ⚠️  没找到匹配的中间证书,只导入叶证书。"
  echo "       (macOS 信任库里通常有,多半还是能用;但签名里不会带链,公证可能挑刺)"
fi

# ---------------------------------------------------------------------------
# 打包 + 导入
# ---------------------------------------------------------------------------
echo
echo "==> 打包 p12(私钥 + 证书链)"
PP12_PASS="$(openssl rand -base64 18)"
PKCS12_ARGS=(-inkey "$KEY" -in "$WORK/leaf.pem" -out "$WORK/id.p12" -passout "pass:${PP12_PASS}")
if [[ -n "$INTERMEDIATE" ]]; then
  PKCS12_ARGS+=(-certfile "$INTERMEDIATE")
fi
# ⚠️ 必须显式指定老的加密算法:
#   OpenSSL 3 的 pkcs12 默认改成 AES-256-CBC + PBKDF2,
#   而 macOS 的 SecKeychainItemImport 只认 RC2/3DES + 传统 KDF ——
#   用默认参数导出会报 "MAC verification failed during PKCS12 import"。
openssl pkcs12 -export "${PKCS12_ARGS[@]}" \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -name "Developer ID Application"

echo "==> 导入钥匙串"
security import "$WORK/id.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PP12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

echo
echo "==> 当前 codesigning 身份"
security find-identity -v -p codesigning

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo
  echo "✅ Developer ID Application 已就位,可以签名公证了:"
  echo "   ./scripts/build-app.sh release && ./scripts/notarize.sh AC_PASSWORD"
else
  echo
  echo "⚠️  还没看到 'Developer ID Application'。"
  echo "   多半是私钥没绑上。上面 security import 的输出里有报错的话贴给我。"
  exit 1
fi
