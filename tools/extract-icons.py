#!/usr/bin/env python3
"""从原版截图抠出 UI 图标,存成带 alpha 的 PNG 资源。

为什么抠图而不是手绘路径:原版是 Segoe MDL2 字形,曲线和端点圆角都很难用
bezier 逼近。直接抠成位图才能做到逐像素一致。

抠法有三种,脚本会逐个试,挑还原误差最小的那个:
  调色板  —— 前聚成 ≤8 色的调色板,逐像素解 p = a·c + (1-a)·bg
  色偏    —— 按「与背景的偏差方向」聚类,同方向即同色相,取最饱和的当纯色
  实心    —— 整块不透明拷贝(适合背景在局部几乎是常数的多色图标)

用法: extract-icons.py [原版png]
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "raw", "4db8b22c7b5a996a230c43ae5b547887.png")
OUT = os.path.join(ROOT, "Resources", "icons")

# ── 状态栏 / 标题栏(纯黑线性字形,前景单一) ────────────────────────────────
SIMPLE_REGIONS = {
    "status_cursor":  (16, 951, 32, 970),
    "status_dash":    (179, 951, 197, 970),
    "status_size":    (344, 951, 362, 970),
    "floppy":         (515, 950, 536, 971),
    "title_min":      (1325, 3, 1348, 29),
    "title_max":      (1382, 3, 1406, 29),
    "title_close":    (1440, 3, 1466, 29),
    # 状态栏缩放框里的小箭头
    "zoom_chev":      (1182, 955, 1198, 967),
    # 状态栏右端「适应窗口」(墨迹 1061..1078 / 953..966)
    "status_fit":     (1056, 949, 1083, 971),
}

# ── 功能区图标(可能带彩色) ────────────────────────────────────────────────
# 坐标 = 原版绝对像素矩形(x0,y0,x1,y1)
RIBBON_REGIONS = {
    # 图像组
    "img_crop":        (93, 105, 121, 133),
    "img_rotate":      (144, 106, 172, 134),
    "img_chev1":       (177, 112, 193, 126),
    "img_removebg":    (92, 156, 120, 184),
    "img_flip":        (142, 155, 170, 183),
    "img_chev2":       (177, 160, 193, 174),
    "img_resize":      (216, 127, 254, 163),
    # 工具组
    "tool_pencil":     (290, 105, 316, 131),
    "tool_fillcan":    (340, 105, 366, 131),
    "tool_text":       (392, 106, 418, 132),
    "tool_eraser":     (292, 154, 318, 180),
    "tool_dropper":    (340, 156, 366, 182),
    "tool_magnifier":  (390, 156, 416, 182),
    # 画笔组
    "brush_paint":     (458, 117, 491, 151),
    "brush_chev":      (466, 154, 482, 170),
    # 形状组
    "shape_outline":   (694, 109, 722, 137),
    "shape_chev1":     (728, 113, 744, 127),
    "shape_fill":      (760, 123, 794, 157),
    "shape_thick":     (694, 156, 720, 182),
    "shape_chev2":     (728, 162, 744, 176),
    "shape_chev3":     (771, 162, 787, 176),
    # 选择组的小箭头
    "select_chev":     (29, 160, 43, 170),
    # 菜单行图标
    "menu_share":      (285, 48, 311, 74),
    "menu_undo":       (343, 47, 369, 73),
    "menu_redo":       (392, 47, 418, 73),
    "menu_megaphone":  (1397, 49, 1425, 77),
    "menu_gear":       (1444, 48, 1472, 76),
    # 状态栏右端放大镜(带蓝色手柄)
    "status_zoomout":  (1231, 946, 1259, 973),
    "status_zoomin":   (1444, 946, 1472, 973),
    # 「层」组图标:三层堆叠,中间一层是蓝的(墨迹 1366..1389 / 133..156)
    "group_layers":    (1360, 127, 1396, 161),
}

# ── 标题栏调色板图标(多色渐变,alpha 反解必然丢色,整块拷贝) ────────────────
TITLE_REGIONS = {
    "title_palette":  (8, 7, 32, 31),
}

# 形状库网格:cell 22×22,列距 28、行距 27,左上角 cell 在 (528, 102)
SHAPE_COLS, SHAPE_ROWS = 5, 4
SHAPE_X0, SHAPE_Y0 = 528, 102
SHAPE_DX, SHAPE_DY = 28, 27
SHAPE_CELL = 22
# 只抠前三行:第四行在原版里被面板底边裁掉了,抠不全
SHAPE_BITMAP_ROWS = 3


def background_of(flat):
    """背景色 = 出现最多的颜色(Mica 渐变在这么小的区域里基本是常数)。"""
    q = (flat // 3).astype(int)
    key = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
    vals, counts = np.unique(key, return_counts=True)
    best = vals[counts.argmax()]
    sel = key == best
    return flat[sel].mean(axis=0)


def palette_of(fg, max_colors=8):
    """把前景像素聚成调色板(粗量化后取高频桶,再合并相近的)。"""
    q = (fg // 16).astype(int)
    key = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
    vals, counts = np.unique(key, return_counts=True)
    order = np.argsort(-counts)[:max_colors * 3]
    pal = []
    for idx in order:
        c = fg[key == vals[idx]].mean(axis=0)
        if all(np.abs(c - p).max() > 14 for p in pal):
            pal.append(c)
        if len(pal) >= max_colors:
            break
    return np.array(pal) if pal else np.array([[26.0, 26.0, 26.0]])


def alpha_rgba_linear(reg):
    """线性字形:单一前景色,alpha = (bg - p) / (bg - fg)。

    前景色取暗部 2 分位(取均值会把纯黑按钮平均成深灰)。
    """
    h, w = reg.shape[:2]
    flat = reg.reshape(-1, 3).astype(float)
    bg = background_of(flat)
    dist = np.abs(flat - bg).max(axis=1)
    lum = flat.mean(axis=1)
    bgl = bg.mean()
    dark = flat[lum < bgl - 40]
    pal = (np.percentile(dark, 2, axis=0) if len(dark)
           else np.array([26.0, 26.0, 26.0]))[None, :]

    denom = bg[None, :] - pal
    a_ch = np.where(np.abs(denom) > 4, (bg[None, :] - flat[:, None, :]) / denom, np.nan)
    with np.errstate(invalid="ignore"):
        a_all = np.nanmedian(a_ch, axis=2)
    a = np.clip(np.nan_to_num(a_all, nan=0.0), 0.0, 1.0)

    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = np.clip(pal.reshape(1, 1, 3), 0, 255)
    out[..., 3] = (a.reshape(h, w) * 255).round().astype(np.uint8)
    out[dist.reshape(h, w) <= 12, 3] = 0
    return out


def alpha_rgba_palette(reg):
    """调色板聚类抠法:前景聚成 ≤8 色,逐像素在调色板里找最匹配的一色解 alpha。"""
    h, w = reg.shape[:2]
    flat = reg.reshape(-1, 3).astype(float)
    bg = background_of(flat)
    dist = np.abs(flat - bg).max(axis=1)
    fg = flat[dist > 12]
    if len(fg) == 0:
        return np.zeros((h, w, 4), dtype=np.uint8)

    pal = palette_of(fg)
    denom = bg[None, :] - pal
    a_ch = np.where(np.abs(denom) > 4, (bg[None, :] - flat[:, None, :]) / denom, np.nan)
    with np.errstate(invalid="ignore"):
        a_all = np.nanmedian(a_ch, axis=2)
    a_all = np.clip(np.nan_to_num(a_all, nan=0.0), 0.0, 1.0)

    recon = a_all[:, :, None] * pal[None, :, :] + (1 - a_all[:, :, None]) * bg[None, None, :]
    residual = np.abs(recon - flat[:, None, :]).max(axis=2)
    best = residual.argmin(axis=1)
    a = a_all[np.arange(len(flat)), best]
    resid = residual[np.arange(len(flat)), best]
    a[resid > 14] = 0.0
    a[dist <= 12] = 0.0

    out = np.zeros((h, w, 4), dtype=np.uint8)
    color = pal[best].reshape(h, w, 3)
    out[..., :3] = np.clip(color, 0, 255)
    out[..., 3] = (a.reshape(h, w) * 255).round().astype(np.uint8)
    return out


def alpha_rgba_rich(reg, iters=6):
    """多色图标专用:按「与背景的色偏方向」聚类 + EM 精修。

        d = p - bg          颜色偏差向量
        u = d / |d|         方向 = 前景色的色相(与 alpha 无关)
    同一方向的一组像素说明前景色相同。然后用 EM 迭代精修每簇的纯色 fg 和 alpha:
        fg  = bg + Σ(α·d) / Σ(α²)        (给定 alpha 的最优纯色)
        α_i = (d_i · (fg-bg)) / |fg-bg|²   (给定 fg 的最优 alpha)
    迭代几轮后重建误差能从 8 降到 2 以内,彩色笔触不再丢色。
    """
    h, w = reg.shape[:2]
    flat = reg.reshape(-1, 3).astype(float)
    bg = background_of(flat)
    d = flat - bg[None, :]
    mag = np.linalg.norm(d, axis=1)

    out = np.zeros((h, w, 4), dtype=np.uint8)
    idx = np.where(mag > 10)[0]
    if len(idx) == 0:
        return out
    u = d[idx] / mag[idx][:, None]

    # 初值:按方向余弦 > 0.985 聚类
    labels = np.full(len(idx), -1, int)
    reps = []
    for i in range(len(idx)):
        placed = False
        for k, r in enumerate(reps):
            if float(u[i] @ r) > 0.985:
                labels[i] = k
                placed = True
                break
        if not placed:
            reps.append(u[i])
            labels[i] = len(reps) - 1
    nk = len(reps)

    di = d[idx]
    fg = np.zeros((nk, 3))
    for k in range(nk):
        sel = labels == k
        if not sel.any():
            continue
        b = idx[sel][np.argmax(mag[idx][sel])]
        fg[k] = flat[b]

    alphas = np.zeros(len(idx))
    for _ in range(iters):
        # E 步:每个像素按当前 fg 解 alpha,再改判到残差最小的那一簇
        for k in range(nk):
            axis = fg[k] - bg
            den = float(axis @ axis)
            if den < 1:
                continue
            a = np.clip((di @ axis) / den, 0.0, 1.0)
            sel = labels == k
            alphas[sel] = a[sel]
        resid = np.array([float(np.abs(di[i] - alphas[i] * (fg[labels[i]] - bg)).max())
                          for i in range(len(idx))])
        newlab = labels.copy()
        for i in range(len(idx)):
            best_k, best_r = labels[i], resid[i]
            for k in range(nk):
                axis = fg[k] - bg
                den = float(axis @ axis)
                if den < 1:
                    continue
                a = float(np.clip((di[i] @ axis) / den, 0.0, 1.0))
                r = float(np.abs(di[i] - a * axis).max())
                if r < best_r:
                    best_r, best_k = r, k
            newlab[i] = best_k
        labels = newlab
        # M 步:用当前 alpha 重解每簇的最优纯色
        for k in range(nk):
            sel = labels == k
            if not sel.any():
                continue
            a = alphas[sel][:, None]
            num = (a * di[sel]).sum(axis=0)
            den = float((a * a).sum())
            if den > 1e-6:
                fg[k] = bg + num / den

    rgb = np.zeros((len(idx), 3))
    for k in range(nk):
        rgb[labels == k] = fg[k]
    pix = np.zeros((h * w, 4))
    pix[idx, :3] = np.clip(rgb, 0, 255)
    pix[idx, 3] = np.clip(alphas, 0, 1) * 255
    return pix.reshape(h, w, 4).astype(np.uint8)


def alpha_rgba_opaque(reg):
    """不透明整块拷贝。

    适合「背景在局部几乎是常数」的多色图标(标题栏调色板图标):
    原版那块 Mica 是 (245,243,238),复刻版是 (244,243,237),差 1 级肉眼不可见;
    而 alpha 反解对这种多色图形(浅青底 + 亮蓝颜料 + 绿/黄/红笔触)必然丢色。
    """
    h, w = reg.shape[:2]
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = np.clip(reg, 0, 255)
    out[..., 3] = 255
    return out


def recon_error(arr, reg):
    """把抠出来的图标合成回原背景,看能还原多少(越小越好)。"""
    flat = reg.reshape(-1, 3).astype(float)
    bg = background_of(flat)
    a = arr[..., 3:4].astype(float) / 255.0
    recon = arr[..., :3].astype(float) * a + bg[None, None, :] * (1 - a)
    return float(np.abs(recon - reg.astype(float)).mean())


def save(name, arr, mode=""):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    Image.fromarray(arr, "RGBA").save(path)
    nz = int((arr[..., 3] > 0).sum())
    print(f"  {name:18s} {arr.shape[1]}x{arr.shape[0]}  有像素 {nz:5d}  {mode}")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else RAW
    img = np.asarray(Image.open(src).convert("RGB")).astype(int)
    print(f"原版:{src}  {img.shape[1]}x{img.shape[0]}")

    for name, (x0, y0, x1, y1) in SIMPLE_REGIONS.items():
        save(name, alpha_rgba_linear(img[y0:y1, x0:x1]))

    for name, (x0, y0, x1, y1) in RIBBON_REGIONS.items():
        reg = img[y0:y1, x0:x1]
        # 三种抠法都试一遍,哪能把原像素还原得最准就用哪一
        cands = [("调色板", alpha_rgba_palette(reg)),
                 ("色偏", alpha_rgba_rich(reg))]
        best = min(cands, key=lambda kv: recon_error(kv[1], reg))
        save(name, best[1], best[0])

    for name, (x0, y0, x1, y1) in TITLE_REGIONS.items():
        reg = img[y0:y1, x0:x1]
        # 调色板聚类会把这个多色图标抠丢笔触(误差 16),色偏+EM 精修能到 2.4
        save(name, alpha_rgba_rich(reg), "色偏")

    for j in range(SHAPE_BITMAP_ROWS):
        for i in range(SHAPE_COLS):
            x0 = SHAPE_X0 + SHAPE_DX * i
            y0 = SHAPE_Y0 + SHAPE_DY * j
            save(f"shape_{j * SHAPE_COLS + i:02d}",
                 alpha_rgba_linear(img[y0:y0 + SHAPE_CELL, x0:x0 + SHAPE_CELL]))

    print(f"\n共 {len(os.listdir(OUT))} 个图标 -> {OUT}")


if __name__ == "__main__":
    main()
