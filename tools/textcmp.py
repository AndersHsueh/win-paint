#!/usr/bin/env python3
"""生成「原版 | 候选 | 差异」三联对照图,肉眼核对文字形状。

用法: textcmp.py <orig.png> <sweepDir> <x0> <y0> <x1> <y1> <out.png> [pick]
  pick = index.tsv 里的文件名(默认取打分最优的第一个)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from textscore import read_pgm  # noqa: E402


def ink_alpha(lum):
    bg = np.percentile(lum, 95)
    ink = lum.min()
    if bg - ink < 1:
        bg = ink + 1
    return np.clip((bg - lum) / (bg - ink), 0, 1)


def main():
    orig, sweep = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
    out = sys.argv[7]
    pick = sys.argv[8] if len(sys.argv) > 8 else None

    if pick is None:
        # 取 index.tsv 第一个(调用方一般先排序)
        pick = sorted(f for f in os.listdir(sweep) if f.endswith(".pgm"))[0]

    a = ink_alpha(np.asarray(Image.open(orig).convert("RGB")).astype(float)[y0:y1, x0:x1].max(axis=2))
    b = read_pgm(os.path.join(sweep, pick))
    if b.shape != a.shape:
        raise SystemExit(f"尺寸不符 {b.shape} vs {a.shape}")

    # 三联:原版墨迹(黑底白墨)、候选墨迹、差异(红=原版多,蓝=候选多)
    pa = np.zeros((a.shape[0], a.shape[1], 3), np.uint8)
    pa[..., :] = (255 * (1 - a))[..., None].astype(np.uint8)
    pb = np.zeros_like(pa)
    pb[..., :] = (255 * (1 - b))[..., None].astype(np.uint8)
    d = np.zeros_like(pa)
    d[..., 0] = (255 * np.clip(a - b, 0, 1)).astype(np.uint8)
    d[..., 2] = (255 * np.clip(b - a, 0, 1)).astype(np.uint8)
    d[..., 1] = (255 * (1 - np.abs(a - b))).astype(np.uint8)

    sc = max(1, 1400 // max(a.shape))
    sep = np.full((a.shape[0], 2, 3), 255, np.uint8)
    trio = np.concatenate([pa, sep, pb, sep, d], axis=1)
    trio = np.repeat(np.repeat(trio, sc, axis=0), sc, axis=1)
    Image.fromarray(trio).save(out)
    print(f"{out}  {trio.shape[1]}x{trio.shape[0]}  pick={pick}")


if __name__ == "__main__":
    main()
