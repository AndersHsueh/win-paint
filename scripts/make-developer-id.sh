#!/usr/bin/env bash
#
# 生成 Developer ID Application 证书申请用的 CSR + 私钥。
#
# 为什么不用钥匙串的「证书助理」？
#   证书助理要在 GUI 里敲 Apple ID 密码 + 2FA，交互多、容易中途失败；
#   而「本地生成 CSR → 门户上传 → 下载 .cer → 导入钥匙串」这条路里，
#   本地这一步完全可脚本化，门户那一步本来就得人来做。
#
# 产物（默认放桌面，**故意不放仓库**，仓库是 public GitHub 仓库）：
#   WinPaint-DID.key   私钥（600）
#   WinPaint-DID.csr   证书签名请求，上传给 Apple 用
#
# 后续步骤见 scripts/import-developer-id.sh。
set -euo pipefail

TEAM_ID="${TEAM_ID:-BP6XLRFH4K}"
CN="${CN:-Anders Hsueh}"
EMAIL="${EMAIL:-xue.anders.yh@gmail.com}"
COUNTRY="${COUNTRY:-US}"

OUT_DIR="${1:-$HOME/Desktop/WinPaint-DID}"
KEY="$OUT_DIR/WinPaint-DID.key"
CSR="$OUT_DIR/WinPaint-DID.csr"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [[ -f "$KEY" ]]; then
  echo "私钥已存在，复用：$KEY"
else
  echo "==> 生成 RSA 2048 私钥"
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$KEY" \
    -out "$CSR" \
    -subj "/CN=${CN}/OU=${TEAM_ID}/O=${CN}/emailAddress=${EMAIL}/C=${COUNTRY}" \
    2>/dev/null
  chmod 600 "$KEY"
fi

if [[ ! -f "$CSR" ]]; then
  # 私钥在但 CSR 不在（被删了），用私钥重签一份
  openssl req -new -key "$KEY" -out "$CSR" \
    -subj "/CN=${CN}/OU=${TEAM_ID}/O=${CN}/emailAddress=${EMAIL}/C=${COUNTRY}" \
    2>/dev/null
fi

echo
echo "==> CSR 内容校验"
openssl req -in "$CSR" -noout -subject -verify 2>&1 | sed 's/^/    /'

cat <<EOF

==> 接下来（门户那一步只能你本人做）
  1. 打开 https://developer.apple.com/account/resources/certificates/list
  2. 右上角「+」→ Certificate Type 选 **Developer ID Application**
     （注意别选 Mac App Distribution —— 那个公证会被拒，Xcode 14.3 之后
       两者在钥匙串里都显示成 "Apple Distribution"，极易搞混）
  3. 上传这个 CSR 文件：
       $CSR
  4. 点 Download，拿到 DeveloperIDApplication.cer
  5. 双击 .cer → 登录钥匙串 → 确认「证书」分类
     或直接跑：./scripts/import-developer-id.sh <路径>/DeveloperIDApplication.cer

==> 装好之后自检（应该多出第 3 条）
  security find-identity -v -p codesigning
EOF
