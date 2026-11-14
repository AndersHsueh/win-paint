#!/usr/bin/env python3
"""文字候选打分:把 textprobe 渲染的候选掩码和原版截图的墨迹做最优对齐打分。

原版的「墨迹浓度」从亮度反推:
    alpha = clip((bg - lum) / (bg - ink), 0, 1)
其中 bg 取区域亮度的 95 分位(背景占多数),ink 取最小值。

对每个候选在 ±range 像素内穷举平移,取 mean|alpha_orig - alpha_cand| 最小者。
评分单位是「每像素平均浓度差」,越小越像;同区域内可直接横向比较。

用法: textscore.py <orig.png> <sweepDir> <x0> <y0> <x1> <y1> [topN] [range]
"""
import os
import sys

import numpy as np
from PIL import Image

ORIG_DEFAULT = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def read_pgm(path):
    with open(path, "rb") as f:
        data = f.read()
    # P5\nW H\n255\n
    parts, idx = [], 0
    while len(parts) < 4:
        while idx < len(data) and data[idx:idx + 1].isspace():
            idx += 1
        if data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx] != 0x0A:
                idx += 1
            continue
        start = idx
        while idx < len(data) and not data[idx:idx + 1].isspace():
            idx += 1
        parts.append(data[start:idx])
    idx += 1
    w, h = int(parts[1]), int(parts[2])
    return np.frombuffer(data[idx:idx + w * h], dtype=np.uint8).reshape(h, w).astype(float) / 255.0


def main():
    orig = sys.argv[1] if len(sys.argv) > 1 else ORIG_DEFAULT
    sweep = sys.argv[2]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
    topn = int(sys.argv[7]) if len(sys.argv) > 7 else 15
    rng = int(sys.argv[8]) if len(sys.argv) > 8 else 4

    img = np.asarray(Image.open(orig).convert("RGB")).astype(float)
    reg = img[y0:y1, x0:x1]
    lum = reg.max(axis=2)
    bg = np.percentile(lum, 95)
    ink = lum.min()
    if bg - ink < 1:
        bg = ink + 1
    ao = np.clip((bg - lum) / (bg - ink), 0, 1)

    rows = []
    for fn in sorted(os.listdir(sweep)):
        if not fn.endswith(".pgm"):
            continue
        ac = read_pgm(os.path.join(sweep, fn))
        if ac.shape != ao.shape:
            continue
        best = None
        for dy in range(-rng, rng + 1):
            for dx in range(-rng, rng + 1):
                shifted = np.roll(np.roll(ac, dy, axis=0), dx, axis=1)
                if dy > 0:
                    shifted[:dy, :] = 0
                elif dy < 0:
                    shifted[dy:, :] = 0
                if dx > 0:
                    shifted[:, :dx] = 0
                elif dx < 0:
                    shifted[:, dx:] = 0
                score = np.abs(ao - shifted).mean()
                if best is None or score < best[0]:
                    best = (score, dx, dy)

        # 和 metric.py 同口径:把候选按「墨色合成到原版底色」算亮度 meanΔ
        # (掩码分只看形状,亮度分才和整图指标可比)
        al = np.roll(np.roll(ac, best[1], axis=0), best[2], axis=1)
        if best[2] > 0:
            al[:best[2], :] = 0
        elif best[2] < 0:
            al[best[2]:, :] = 0
        if best[1] > 0:
            al[:, :best[1]] = 0
        elif best[1] < 0:
            al[:, best[1]:] = 0
        ink = lum.min()
        cand = bg - al * (bg - ink)
        md = float(np.abs(cand - lum).mean())

        rows.append((best[0], fn, best[1], best[2], md))

    rows.sort()
    print(f"区域 ({x0},{y0})-({x1},{y1})  bg={bg:.0f} ink={ink:.0f}  候选 {len(rows)} 个")
    print(f"{'score':>8} {'md':>8}  {'dx':>4} {'dy':>4}  file")
    for s, fn, dx, dy, md in rows[:topn]:
        print(f"{s:8.4f} {md:8.2f}  {dx:4d} {dy:4d}  {fn}")


if __name__ == "__main__":
    main()
