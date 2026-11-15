#!/usr/bin/env bash
# 冒烟自检:一条命令跑完「构建 → 启动 App → 自截图 → 比对原版」。
#
# 用法:
#   tools/smoke.sh            # 构建 + 快照 + 指标
#   tools/smoke.sh --test     # 额外跑一遍单元/功能测试
#
# 快照靠 App 自己的 DevSnapshot(自渲染,不碰屏幕录制权限)。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG="smoke"
SHOT="/tmp/wp_${TAG}.png"

echo "==> 构建 release"
swift build -c release

if [[ "${1:-}" == "--test" ]]; then
  echo "==> 跑测试"
  swift test
fi

echo "==> 启动 App 自截图(1484x985,标题栏用原版同名文档)"
rm -f "$SHOT"
WINPAINT_SNAPSHOT="$SHOT" \
WINPAINT_SNAPSHOT_SIZE="1484x985" \
WINPAINT_SNAPSHOT_EXIT="1" \
WINPAINT_SNAPSHOT_TITLE="pragmata-capcom-spotlight-social" \
  .build/release/WinPaint >/dev/null 2>&1 || true

if [[ ! -s "$SHOT" ]]; then
  echo "!! 冒烟失败:没生成快照 $SHOT" >&2
  exit 1
fi

echo "==> 与原版逐像素比对"
/opt/homebrew/bin/python3 tools/metric.py "$SHOT"
