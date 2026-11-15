#!/usr/bin/env bash
#
# 打 macOS 分发用的 DMG,并完成签名 / 公证 / stapling。
#
#   ./scripts/make-dmg.sh              # 打 DMG(不公证)
#   ./scripts/make-dmg.sh --notarize   # 打 DMG + 签名 + 公证 + stapling
#
# 为什么要有 DMG 而不是只发 zip:
#   macOS 的分发惯例是「拖进应用程序文件夹」。DMG 有卷图标、有 /Applications
#   软链、有窗口布局,用户双击就知道该干嘛;zip 里的 .app 是个裸目录,
#   拖不动、也看不出该放哪。
#
# ⚠️ DMG 本身也要公证。公证过的 .app 装进**没公证**的 DMG,Apple 照样拒。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/WinPaint.app"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
DO_NOTARIZE=0
[[ "${1:-}" == "--notarize" ]] && DO_NOTARIZE=1

[[ -d "$APP" ]] || { echo "❌ 找不到 $APP,先跑 ./scripts/build-app.sh"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0.1.0")"
DMG="$ROOT/dist/WinPaint-${VERSION}.dmg"

echo "==> 组装暂存目录"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/WinPaint.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'EOF'
安装 WinPaint
================

1. 把左边的 WinPaint 图标拖到右边的「应用程序」文件夹
2. 从「应用程序」里打开 WinPaint

首次打开如果 macOS 提示「无法验证开发者」,说明下载没走完或文件被改过,
请到项目页重新下载。

本应用已通过 Apple 公证(Developer ID),正常情况下不会出现拦截。
EOF

echo "==> 生成 DMG"
rm -f "$DMG"
hdiutil create -volname "WinPaint ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | sed 's/^/    /'
echo "    $DMG"

if [[ "$DO_NOTARIZE" == "1" ]]; then
  echo "==> 签名 DMG"
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/' || true)"
  [[ -n "$SIGN_IDENTITY" ]] || { echo "❌ 钥匙串里没有 Developer ID Application"; exit 1; }
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

  echo "==> 提交公证(profile:$PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --timeout 30m

  echo "==> stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "✅ DMG 已公证:$DMG"
else
  echo "ℹ️  跳过签名与公证(要公证加 --notarize)"
fi
