#!/usr/bin/env bash
#
# 构建 WinPaint.app 并用 Apple 开发者证书签名。
#
#   ./scripts/build-app.sh            # release + Developer ID 签名
#   ./scripts/build-app.sh debug      # debug 构建(仍然签名)
#   WINPAINT_UNIVERSAL=1 ./scripts/build-app.sh   # arm64 + x86_64 通用二进制
#   WINPAINT_ADHOC=1 ./scripts/build-app.sh       # 仅 ad-hoc 签名(不公证,本机自用)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="WinPaint"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONFIG="${1:-release}"

# Developer ID 分发身份(团队 BP6XLRFH4K)。公证必须用它,Apple Development 证书不行。
SIGN_IDENTITY="${WINPAINT_SIGN_IDENTITY:-Apple Distribution: Anders Hsueh (BP6XLRFH4K)}"

echo "==> swift build ($CONFIG)"
if [ "${WINPAINT_UNIVERSAL:-0}" = "1" ]; then
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
else
  swift build -c "$CONFIG"
fi

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -f "$BIN" ] || { echo "❌ 找不到可执行文件:$BIN"; exit 1; }

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  echo "    已包含 AppIcon.icns"
fi

# 彩虹轮按钮(从原版截图抠出的 34×34 资源图)
if [ -f "$ROOT/Resources/colorwheel.png" ]; then
  cp "$ROOT/Resources/colorwheel.png" "$APP/Contents/Resources/colorwheel.png"
  echo "    已包含 colorwheel.png"
fi

# 从原版抠出来的 UI 图标(状态栏 4 个 / 形状库 15 个 / 窗口按钮 3 个)
if [ -d "$ROOT/Resources/icons" ]; then
  mkdir -p "$APP/Contents/Resources/icons"
  cp "$ROOT"/Resources/icons/*.png "$APP/Contents/Resources/icons/"
  echo "    已包含 icons/($(ls -1 "$ROOT/Resources/icons" | wc -l | tr -d ' ') 个)"
fi

echo "==> 签名"
if [ "${WINPAINT_ADHOC:-0}" = "1" ]; then
  codesign --force --sign - "$APP"
  echo "    ad-hoc 签名(未公证,只适合本机)"
else
  if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
    echo "❌ 钥匙串里找不到签名身份:$SIGN_IDENTITY"
    echo "   可用身份:"
    security find-identity -v -p codesigning | sed 's/^/   /'
    exit 1
  fi
  # --options runtime = hardened runtime,公证的硬性要求
  # --timestamp       = 签名带时间戳,公证也要求
  codesign --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
echo "==> 完成:$APP"
echo
echo "下一步:"
echo "  open \"$APP\"                                # 本机运行"
echo "  ./scripts/notarize.sh <keychain-profile>    # 上传公证并 stapling"
