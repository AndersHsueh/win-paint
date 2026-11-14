#!/usr/bin/env python3
"""粗网格差异热区:把整图切成格子,按 meanΔ 排序,指出真正的热点。

用途:手工划的分区会漏掉大块区域(比如画布四周的留白),这个脚本先把
「差异质量」都装在哪儿找出来,再决定改哪儿。

用法: grid.py <mine.png> [cols] [rows] [topN]
"""
import sys

import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def main():
    mine = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v67.png"
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    topn = int(sys.argv[4]) if len(sys.argv) > 4 else 20

    o = np.asarray(Image.open(ORIG).convert("RGB")).astype(int)
    a = np.asarray(Image.open(mine).convert("RGB")).astype(int)
    d = np.abs(o - a).max(axis=2)
    mask = np.ones(d.shape, bool)
    mask[264:896, 142:1342] = False
    mask[0:2, :] = False; mask[-2:, :] = False
    mask[:, 0:2] = False; mask[:, -2:] = False
    d = np.where(mask, d, 0)

    H, W = d.shape
    cw, ch = W // cols, H // rows
    cells = []
    for j in range(rows):
        for i in range(cols):
            x0, x1 = i * cw, (W if i == cols - 1 else (i + 1) * cw)
            y0, y1 = j * ch, (H if j == rows - 1 else (j + 1) * ch)
            reg = d[y0:y1, x0:x1]
            m = mask[y0:y1, x0:x1]
            if not m.any():
                continue
            cells.append((reg.sum() / m.sum(), reg.sum(), x0, y0, x1, y1, m.sum()))

    total = d.sum()
    print(f"全局 meanΔ={total/mask.sum():.3f}   非空格子 {len(cells)}")
    print("\n按贡献排序(贡献 = 该格 sum,占总差异的百分比):")
    cells.sort(key=lambda c: -c[1])
    print(f"{'meanΔ':>7} {'贡献%':>6}  区域(x0,y0)-(x1,y1)")
    for mean, s, x0, y0, x1, y1, n in cells[:topn]:
        print(f"{mean:7.2f} {s/total*100:6.2f}  ({x0},{y0})-({x1},{y1})")

    print("\n热区图(每格 meanΔ,数字越大越热):")
    grid = np.zeros((rows, cols))
    for mean, s, x0, y0, x1, y1, n in cells:
        j, i = y0 // ch, x0 // cw
        grid[j, i] = mean
    for j in range(rows):
        print("  " + " ".join(f"{grid[j, i]:5.1f}" if grid[j, i] > 0 else "    ." for i in range(cols)))


if __name__ == "__main__":
    main()
