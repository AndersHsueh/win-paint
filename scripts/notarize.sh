#!/usr/bin/env bash
#
# 把已签名的 WinPaint.app 提交给 Apple 公证服务,完成后 stapling 票据。
#
# 【第 1 步 · 只能你本人做】把公证凭据存进钥匙串。
# 不带 --password 参数,Apple 会在终端弹安全输入框,
# 密码不会进 shell 历史、也不会进聊天记录:
#
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#       --apple-id <你的 Apple ID> \
#       --team-id BP6XLRFH4K
#
# 这里要填的是 **app-specific password**(Apple ID 网页 → 登录 → 安全 → 生成 app 专用密码),
# 不是 Apple ID 的登录密码。
#
# 【第 2 步】提交公证 + stapling:
#
#   ./scripts/notarize.sh AC_PASSWORD
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROFILE="${1:-AC_PASSWORD}"
APP="$ROOT/dist/WinPaint.app"
TEAM="BP6XLRFH4K"

[ -d "$APP" ] || { echo "❌ 找不到 $APP,先跑 ./scripts/build-app.sh"; exit 1; }

# 凭据没存的话先提示,别等提交到一半才失败
if ! security find-generic-password -s "notarytool" -a "${PROFILE}" >/dev/null 2>&1; then
  echo "❌ 钥匙串里没有公证凭据 profile=${PROFILE}。先执行:"
  echo "     xcrun notarytool store-credentials $PROFILE --apple-id <你的 Apple ID> --team-id ${TEAM}"
  echo "   (终端会弹安全输入框要密码,用 app-specific password,不要用 Apple ID 登录密码)"
  exit 1
fi

echo "==> 校验签名"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# notarytool 收包,dmg 之类容易被改坏;用 ditto 压 zip 最稳(保留符号链接和扩展属性)
echo "==> 打包提交件"
ZIP="$ROOT/dist/WinPaint-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 提交公证(profile:$PROFILE)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --timeout 30m

echo "==> stapling 票据"
xcrun stapler staple "$APP"

echo "==> 验收"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /'

echo "✅ 公证完成:$APP"
echo "   现在可以分发了 —— 双击打开不会弹 Gatekeeper 拦截。"
