#!/usr/bin/env python3
"""从原版截图抠出 Windows 画图色板的 30 个图块(20 个颜色块 + 10 个空自定义色位)。

为什么要抠位图而不是用同心圆画:
  原版色块在 45° 对角线上的边缘像素是 (160,73,76) 这种「更暗更饱和」的暗红,
  正上/正右方向却是 (162,116,117) 的中性灰边。这是原图缩放/锐化留下的
  通道相关残留(纯色 237,28,36 不可能混出 R=160),用任何解析公式都复刻不出来。
  所以直接抠成位图 —— 和 Resources/colorwheel.png、copilot_badge.png 同一套路。

抠取规则:
  - 纯 Mica 底色的像素写成 alpha=0(运行时用 App 自己的底色透出来)
  - 其余像素原样拷贝(alpha=255)
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.path.join(ROOT, "raw", "4db8b22c7b5a996a230c43ae5b547887.png")
OUT = os.path.join(ROOT, "Resources", "palette")

# 色板原点:ColorGroupView 在功能区 x=817,组内 offset x=70+col*30, y=15+row*30
GROUP_X, GROUP_Y = 817, 89
ORIG_X, ORIG_Y = 70, 15
TILE = 20
STEP = 30
# 空自定义色位:组内 offset y=75
EMPTY_Y = 75


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.open(ORIG).convert("RGB")
    px = img.load()

    def grab(col, row):
        x0 = GROUP_X + ORIG_X + col * STEP
        y0 = GROUP_Y + (ORIG_Y + row * STEP)
        # 用图块四角附近的像素估计 Mica 底色
        bg = px[x0 - 3, y0 - 3]
        tile = Image.new("RGBA", (TILE, TILE))
        tp = tile.load()
        for y in range(y0, y0 + TILE):
            for x in range(x0, x0 + TILE):
                c = px[x, y]
                if max(abs(c[i] - bg[i]) for i in range(3)) <= 1:
                    tp[x - x0, y - y0] = (bg[0], bg[1], bg[2], 0)
                else:
                    tp[x - x0, y - y0] = (c[0], c[1], c[2], 255)
        return tile

    n = 0
    for row in range(2):
        for col in range(10):
            p = os.path.join(OUT, f"swatch-r{row}c{col}.png")
            grab(col, row).save(p)
            n += 1
    for col in range(10):
        x0 = GROUP_X + ORIG_X + col * STEP
        y0 = GROUP_Y + EMPTY_Y
        bg = px[x0 - 3, y0 - 3]
        tile = Image.new("RGBA", (TILE, TILE))
        tp = tile.load()
        for y in range(y0, y0 + TILE):
            for x in range(x0, x0 + TILE):
                c = px[x, y]
                if max(abs(c[i] - bg[i]) for i in range(3)) <= 1:
                    tp[x - x0, y - y0] = (bg[0], bg[1], bg[2], 0)
                else:
                    tp[x - x0, y - y0] = (c[0], c[1], c[2], 255)
        tile.save(os.path.join(OUT, f"slot-c{col}.png"))
        n += 1
    print(f"写出 {n} 个图块 → {OUT}")


if __name__ == "__main__":
    main()
