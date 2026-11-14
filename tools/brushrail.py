#!/usr/bin/env python3
"""竖向滑轨逐行量:量原版和复刻的两条轨(灰轨/蓝轨)的起止行、把手位置、颜色。

用法: brushrail.py <mine.png>
"""
import sys

import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def is_gray(p):
    return abs(p[0] - p[1]) < 8 and abs(p[1] - p[2]) < 8 and p[0] < 200


def is_blue(p):
    return p[2] > 110 and p[2] - p[0] > 40


def report(img, label):
    print(f"\n===== {label} =====")
    # 左卡:灰轨 x 39..43,右卡:蓝轨 x 99..103
    for name, xs, pred in (("灰轨", range(39, 44), is_gray), ("蓝轨", range(99, 104), is_blue)):
        rows = [y for y in range(300, 820)
                if any(pred(img[y, x]) for x in xs)]
        if not rows:
            print(f"  {name}: 没找到")
            continue
        # 连续区间
        segs, start = [], rows[0]
        for a, b in zip(rows, rows[1:]):
            if b != a + 1:
                segs.append((start, a)); start = b
        segs.append((start, rows[-1]))
        print(f"  {name}: x{xs.start}..{xs.stop-1}  行段 {segs}")
        for y in (segs[0][0], segs[0][1]):
            print(f"     y={y} 颜色 {tuple(img[y, (xs.start+xs.stop)//2])}")


def knob_report(img, label, xcenter):
    print(f"\n  --- {label} 把手列 x={xcenter} 附近 ---")
    for y in range(300, 820):
        row = img[y, xcenter - 12:xcenter + 13]
        blue = sum(1 for p in row if is_blue(p))
        white = sum(1 for p in row if p.min() > 235)
        if blue > 6 or white > 16:
            print(f"     y={y} blue={blue} white={white}")


def main():
    mine = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v67.png"
    o = np.asarray(Image.open(ORIG).convert("RGB")).astype(int)
    a = np.asarray(Image.open(mine).convert("RGB")).astype(int)
    report(o, "原版")
    report(a, "复刻")
    print("\n===== 把手 =====")
    knob_report(o, "原版左卡", 41)
    knob_report(a, "复刻左卡", 41)


if __name__ == "__main__":
    main()
