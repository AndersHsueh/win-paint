#!/usr/bin/env python3
"""从原版 Windows 画图截图里提取「颜色」组的彩虹轮按钮,输出 Resources/colorwheel.png。

为什么用位图而不是矢量重画:
原版那个 32×32 的彩虹轮不是简单的色相环 —— 同一半径上 V 值最大差到 30(带一圈
明暗过渡),而且 ⊕ 徽标压在右上角遮住了一块色相。任何解析模型(SV 锥、径向渐变)
都只能逼近到 Δ5~15,肉眼在 32px 下仍能看出偏差。Windows 自己也是把这张图当资源图
发布的,所以这里直接抠原版像素,保证"一模一样"。

抠图算法(踩过的坑都写在这了):
  1. **不能用"和底色的差"当唯一判据** —— 彩虹轮中心是白色,而功能区 Mica 底色也是
     浅色(250,249,248),白心比底色只差 4,只按差值判会把圆心整块抠成透明,轮子上
     出现一个洞。所以差值判之外,再加**椭圆几何**兜底(轮盘内部一律算内容)。
  2. **边缘不要做半透明**。原版最外圈那些像素本身就是"色相 ⊕ 底色"的混合色,
     直接按不透明烘进去,叠回功能区后渲染出来的颜色与原版**完全一致**;真做成
     半透明反而要反解覆盖率,一旦覆盖率算错就会差几十。之前就是在这上面绕了
     半天才发现:不透明才是对的。
  3. ⊕ 徽标整体烘进位图(Windows 原版本来就是一张图)。徽标白盘与底色只差 5,
     所以徽标区域按"圆形几何 + 低饱和"圈,不能只靠差值。
"""

import json
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "raw", "4db8b22c7b5a996a230c43ae5b547887.png")
OUT = os.path.join(ROOT, "Resources", "colorwheel.png")

# ---- 原版实测几何(逐像素量取)----
# 色相环外框是椭圆(原截图本身有约 3% 纵向压缩):中心 (1216.8, 146.95),半径 15.7 / 15.6
ELL_CX, ELL_CY = 1216.8, 146.95
ELL_RX, ELL_RY = 15.7, 15.6
# ⊕ 徽标圆心与外圈半径
BADGE_CX, BADGE_CY, BADGE_R = 1226.4, 135.8, 7.6
# 取景框左上角(绝对像素)与尺寸
FRAME_X, FRAME_Y = 1201, 128
SIZE = 34
# 功能区 Mica 在该处的底色
BG = np.array([250.0, 249.0, 248.0])
STEP = 5  # 色相表步长(度)


def hue_angle(c):
    r, g, b = c
    mx, mn = max(c), min(c)
    d = mx - mn
    if d < 1e-6:
        return None
    if mx == r:
        return 60 * (((g - b) / d) % 6)
    if mx == g:
        return 60 * ((b - r) / d + 2)
    return 60 * ((r - g) / d + 4)


def hsv_rgb(h, s, v=254.0):
    h = h % 360
    c = v * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = v - c
    tbl = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
    r, g, b = tbl[int(h // 60) % 6]
    return np.array([r + m, g + m, b + m])


def build_hue_table(img):
    """从原版饱和像素里取每个角度的纯色相角(徽标遮住的角用解析式补)。"""
    angles = np.zeros(360)
    for deg in range(360):
        phi = math.radians(deg)
        vals = []
        for rr in np.arange(12.2, 14.3, 0.2):
            px = ELL_CX + rr * math.sin(phi)
            py = ELL_CY - rr * math.cos(phi)
            xi, yi = int(round(px)), int(round(py))
            if 0 <= xi < img.shape[1] and 0 <= yi < img.shape[0]:
                vals.append(img[yi, xi])
        if not vals:
            continue
        arr = np.array(vals)
        mx, mn = arr.max(axis=1), arr.min(axis=1)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
        sel = arr[sat > 0.92] if (sat > 0.92).any() else arr
        hs = [h for h in (hue_angle(c) for c in sel) if h is not None]
        if not hs:
            continue
        a = np.array(hs)
        med = np.median(a)
        angles[deg] = med + np.median((a - med + 180) % 360 - 180)
    for deg in range(360):
        if 6 <= deg <= 72:          # 徽标遮住的区间
            angles[deg] = 90.0 + deg
    return angles


def main():
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(float)

    out = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)

    for py in range(SIZE):
        for px in range(SIZE):
            ax = FRAME_X + px + 0.5
            ay = FRAME_Y + py + 0.5
            C = img[int(ay), int(ax)]
            diff = float(np.abs(C - BG).max())

            dx = ax - ELL_CX
            dy = ay - ELL_CY
            r_ell = math.hypot(dx / ELL_RX, dy / ELL_RY)

            # 徽标:低饱和 + 落在徽标圆内(白盘与底色只差 5,不能只靠差值)
            grayish = (C.max() - C.min()) < 26
            in_badge = math.hypot(ax - BADGE_CX, ay - BADGE_CY) <= BADGE_R

            content = (diff > 3) or (r_ell <= 0.93) or (grayish and in_badge)
            if not content:
                continue
            # 一律不透明:边缘像素本身就是原版的混合色,烘进去渲染结果与原版一致
            out[py, px] = [int(C[0]), int(C[1]), int(C[2]), 255]

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(out, "RGBA").save(OUT)

    # 自检:叠回底色后与原版逐像素比较
    comp = np.asarray(Image.open(OUT).convert("RGBA")).astype(float)
    a = comp[..., 3:4] / 255.0
    over = comp[..., :3] * a + BG * (1 - a)
    ref = img[FRAME_Y:FRAME_Y + SIZE, FRAME_X:FRAME_X + SIZE]
    d = np.abs(over - ref).max(axis=2)
    print(f"输出 {OUT}  {SIZE}x{SIZE}")
    print(f"  叠回底色 vs 原版: meanΔ={d.mean():.3f} p95={np.percentile(d, 95):.1f} max={d.max():.0f}")
    bad = np.where(d > 6)
    if len(bad[0]):
        print("  差异>6 的位置(绝对像素):",
              sorted({(int(x) + FRAME_X, int(y) + FRAME_Y) for x, y in zip(bad[0], bad[1])})[:24])

    meta = {
        "origin_x": FRAME_X,
        "origin_y": FRAME_Y,
        "width": SIZE,
        "height": SIZE,
        "note": "原版截图中彩虹轮(含 ⊕ 徽标)的取景框绝对像素",
    }
    with open(os.path.join(ROOT, "tools", "colorwheel-frame.json"), "w") as f:
        json.dump(meta, f, indent=2)


if __name__ == "__main__":
    main()
