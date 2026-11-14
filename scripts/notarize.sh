#!/usr/bin/env bash
#
# 把已签名的 WinPaint.app 提交给 Apple 公证服务,完成后 stapling 票据。
#
# 前置:先在钥匙串里存好公证凭据(密码不要进聊天/仓库):
#
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#       --apple-id <你的 Apple ID> \
#       --team-id BP6XLRFH4K \
#       --password <app-specific-password>
#
# 然后:
#   ./scripts/notarize.sh AC_PASSWORD
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROFILE="${1:-AC_PASSWORD}"
APP="$ROOT/dist/WinPaint.app"

[ -d "$APP" ] || { echo "❌ 找不到 $APP,先跑 ./scripts/build-app.sh"; exit 1; }

echo "==> 校验签名"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo "==> 提交公证(profile:$PROFILE)"
xcrun notarytool submit "$APP" --keychain-profile "$PROFILE" --wait --timeout 30m

echo "==> stapling 票据"
xcrun stapler staple "$APP"

echo "==> 验收"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /'

echo "✅ 公证完成:$APP"
echo "   现在可以分发了 —— 双击打开不会弹 Gatekeeper 拦截。"
