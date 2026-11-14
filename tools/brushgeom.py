#!/usr/bin/env python3
"""紧凑测量画笔浮出面板(原版 vs 复刻)的卡片/轨道/把手几何。

用法: brushgeom.py <mine.png>
"""
import sys

import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def blue(p):
    return p[2] > 110 and p[2] - p[0] > 40


def gray(p):
    return abs(p[0] - p[1]) < 8 and abs(p[1] - p[2]) < 8 and 100 < p[0] < 215


def segs(rows):
    if not rows:
        return []
    out, start = [], rows[0]
    for a, b in zip(rows, rows[1:]):
        if b != a + 1:
            out.append((start, a)); start = b
    out.append((start, rows[-1]))
    return out


def analyze(img, label, x0, x1, y0, y1, trackx):
    print(f"\n=== {label} ===")
    # 轨道列的灰/蓝行段
    bl = [y for y in range(y0, y1) if any(blue(img[y, x]) for x in trackx)]
    gr = [y for y in range(y0, y1) if any(gray(img[y, x]) for x in trackx)]
    print(f"  蓝像素行段: {segs(bl)}")
    print(f"  灰像素行段: {segs(gr)}")
    # 卡片左右边界:找与画布底色不同的白卡片
    row = img[(y0 + y1) // 2]
    whites = [x for x in range(x0, x1) if row[x].min() > 248]
    if whites:
        print(f"  卡片白列: {segs(whites)}")
    # 把手:该卡区内蓝点最密集的行
    best = []
    for y in range(y0, y1):
        n = sum(1 for x in range(x0, x1) if blue(img[y, x]))
        best.append((n, y))
    top = sorted(best, reverse=True)[:1]
    if top:
        n, y = top[0]
        xs = [x for x in range(x0, x1) if blue(img[y, x])]
        print(f"  最蓝行 y={y} 蓝像素={n} x={xs[:1]}..{xs[-1:]} 颜色={tuple(img[y, xs[len(xs)//2]])}")


def main():
    mine = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v67.png"
    for path, lab in ((ORIG, "原版"), (mine, "复刻")):
        im = np.asarray(Image.open(path).convert("RGB")).astype(int)
        analyze(im, f"{lab} 左卡", 8, 58, 330, 820, range(39, 44))
        analyze(im, f"{lab} 右卡", 60, 126, 330, 820, range(99, 104))


if __name__ == "__main__":
    main()
