#!/usr/bin/env python3
"""把原版和复刻的同一区域裁出来、放大、并排拼成一张对照图,便于肉眼核对。

用法: crop.py <x0> <y0> <x1> <y1> [scale] [mine.png] [out.png]
默认对比 raw/4db8b22c7b5a996a230c43ae5b547887.png 与 /tmp/wp_v67.png。
"""
import sys
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def main():
    x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
    scale = int(sys.argv[5]) if len(sys.argv) > 5 else 4
    mine = sys.argv[6] if len(sys.argv) > 6 else "/tmp/wp_v67.png"
    out = sys.argv[7] if len(sys.argv) > 7 else "/tmp/crop.png"

    a = Image.open(ORIG).convert("RGB").crop((x0, y0, x1, y1))
    b = Image.open(mine).convert("RGB").crop((x0, y0, x1, y1))
    w, h = a.size
    a = a.resize((w * scale, h * scale), Image.NEAREST)
    b = b.resize((w * scale, h * scale), Image.NEAREST)

    gap = 8
    canvas = Image.new("RGB", (a.width + b.width + gap, max(a.height, b.height)), (255, 0, 255))
    canvas.paste(a, (0, 0))
    canvas.paste(b, (a.width + gap, 0))
    canvas.save(out)
    print(f"{out}  {canvas.width}x{canvas.height}  region=({x0},{y0})-({x1},{y1}) scale={scale}")


if __name__ == "__main__":
    main()
