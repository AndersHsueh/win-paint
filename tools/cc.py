#!/usr/bin/env python3
"""连通域比对:把两个 PNG 的同一区域拆成连通块,逐个对齐比较 bbox。

用法: cc.py <orig.png> <mine.png> <x0> <y0> <x1> <y1> [thr]
thr 越小越宽松(只取更暗的像素)。默认 150。
"""
import sys
from collections import deque
import numpy as np
from PIL import Image


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(int)


def components(img, x0, y0, x1, y1, thr=150):
    reg = img[y0:y1, x0:x1]
    mask = reg.max(axis=2) < thr
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for j in range(h):
        for i in range(w):
            if not mask[j, i] or seen[j, i]:
                continue
            q = deque([(j, i)])
            seen[j, i] = True
            minj = maxj = j
            mini = maxi = i
            n = 0
            while q:
                cj, ci = q.popleft()
                n += 1
                minj = min(minj, cj); maxj = max(maxj, cj)
                mini = min(mini, ci); maxi = max(maxi, ci)
                for dj in (-1, 0, 1):
                    for di in (-1, 0, 1):
                        nj, ni = cj + dj, ci + di
                        if 0 <= nj < h and 0 <= ni < w and mask[nj, ni] and not seen[nj, ni]:
                            seen[nj, ni] = True
                            q.append((nj, ni))
            if n >= 6:
                out.append((x0 + mini, y0 + minj, x0 + maxi, y0 + maxj, n))
    out.sort(key=lambda t: (t[0], t[1]))
    return out


def main():
    orig, mine = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    thr = int(sys.argv[7]) if len(sys.argv) > 7 else 150
    O = load(orig); M = load(mine)
    co = components(O, x0, y0, x1, y1, thr)
    cm = components(M, x0, y0, x1, y1, thr)
    print(f"orig {len(co)} 块 / mine {len(cm)} 块   区域=({x0},{y0})-({x1},{y1}) thr={thr}\n")
    print(f"{'ORIG x0..x1  y0..y1  n':<34} | {'MINE x0..x1  y0..y1  n':<34} | dx dy  dw dh")
    for i in range(max(len(co), len(cm))):
        a = co[i] if i < len(co) else None
        b = cm[i] if i < len(cm) else None
        sa = f"{a[0]:4d}..{a[2]:4d} {a[1]:4d}..{a[3]:4d} {a[4]:5d}" if a else " " * 24
        sb = f"{b[0]:4d}..{b[2]:4d} {b[1]:4d}..{b[3]:4d} {b[4]:5d}" if b else " " * 24
        if a and b:
            d = f"{b[0]-a[0]:+4d} {b[1]-a[1]:+3d} {b[2]-b[2]:+4d} {b[3]-a[3]:+3d}"
        else:
            d = "    -"
        print(f"{sa:<34} | {sb:<34} | {d}")


if __name__ == "__main__":
    main()
