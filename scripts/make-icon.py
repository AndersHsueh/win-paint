#!/usr/bin/env python3
"""
生成 WinPaint 的应用图标(调色板 + 画笔),输出 Resources/AppIcon.icns。

    python3 scripts/make-icon.py

设计取向:macOS 风格 —— 圆角方形浅色底 + 一块木色调色板 + 四颗彩色颜料点 + 一支斜着的画笔。
刻意不用 Windows 画图的调色板造型,避免和 Microsoft Paint 的商标观感撞车。
"""

import os
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PNG = os.path.join(ROOT, "Resources", "AppIcon.png")
OUT_ICNS = os.path.join(ROOT, "Resources", "AppIcon.icns")
ICONSET = os.path.join(ROOT, ".build", "AppIcon.iconset")

S = 1024


def rounded_mask(size, radius_ratio=0.2237, inset_ratio=0.0):
    """macOS squircle 近似:圆角矩形"""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    inset = int(size * inset_ratio)
    r = int(size * radius_ratio)
    d.rounded_rectangle([inset, inset, size - inset - 1, size - inset - 1], radius=r, fill=255)
    return img


def build_base():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # 底:浅灰白渐变
    bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / (S - 1)
        c = (int(250 - 18 * t), int(250 - 20 * t), int(252 - 16 * t), 255)
        bd.line([(0, y), (S, y)], fill=c)

    mask = rounded_mask(S)
    img.paste(bg, (0, 0), mask)

    d = ImageDraw.Draw(img)

    # 调色板主体(木色椭圆)
    pal = (226, 184, 132, 255)
    d.ellipse([130, 250, 800, 760], fill=pal)

    # 调色板边缘微暗,增加体积感
    d.ellipse([130, 250, 800, 760], outline=(196, 150, 96, 255), width=6)

    # 拇指孔
    d.ellipse([560, 545, 700, 685], fill=(248, 247, 250, 255))

    # 颜料点
    dots = [
        ((250, 355), (232, 76, 60, 255)),
        ((380, 320), (245, 196, 66, 255)),
        ((300, 480), (86, 164, 118, 255)),
        ((430, 470), (72, 118, 214, 255)),
    ]
    for (cx, cy), color in dots:
        r = 52
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)

    # 画笔:斜着的木柄 + 金属箍 + 刷头
    # 用旋转图层实现斜放
    brush = Image.new("RGBA", (520, 140), (0, 0, 0, 0))
    bd2 = ImageDraw.Draw(brush)
    # 刷毛(左)
    bd2.polygon([(10, 45), (150, 12), (150, 128), (10, 95)], fill=(64, 52, 44, 255))
    # 金属箍
    bd2.rectangle([150, 8, 190, 132], fill=(178, 180, 186, 255))
    # 木柄(右)
    bd2.rounded_rectangle([190, 46, 512, 94], radius=24, fill=(196, 140, 78, 255))
    bd2.rounded_rectangle([190, 46, 512, 70], radius=12, fill=(214, 162, 98, 255))

    brush = brush.rotate(38, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(brush, (int(S * 0.30), int(S * 0.03)))

    return img


def write_iconset(base):
    os.makedirs(ICONSET, exist_ok=True)
    sizes = {
        "icon_16x16": 16, "icon_16x16@2x": 32,
        "icon_32x32": 32, "icon_32x32@2x": 64,
        "icon_128x128": 128, "icon_128x128@2x": 256,
        "icon_256x256": 256, "icon_256x256@2x": 512,
        "icon_512x512": 512, "icon_512x512@2x": 1024,
    }
    for name, px in sizes.items():
        base.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, f"{name}.png"))
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", OUT_ICNS], check=True)


def main():
    base = build_base()
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    base.save(OUT_PNG)
    write_iconset(base)
    print(f"✅ {OUT_ICNS}")


if __name__ == "__main__":
    sys.exit(main())
