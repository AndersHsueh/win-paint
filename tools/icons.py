#!/usr/bin/env python3
"""逐个图标对比原版与自截图的「墨迹包围盒」。

用法:
    python3 tools/icons.py <我的截图.png>

对每个图标区域,取「和区域背景色不同的像素」的包围盒,打印原版 / 我的 / 差值。
坐标是整张图上的绝对像素,方便直接改 Swift 里的 offset 与 size。
"""
import sys
import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"

# 名称 -> (x0, y0, x1, y1) 取样窗口(要框住原版图标,原版是基准)
REGIONS = {
    "title_palette": (6, 2, 36, 32),
    "crop":          (92, 104, 120, 132),
    "rotate":        (143, 104, 173, 134),
    "removeBG":      (90, 155, 124, 187),
    "resize":        (215, 126, 255, 163),
    "pencil":        (290, 106, 318, 134),
    "fillCan":       (336, 104, 366, 134),
    "textA":         (390, 105, 418, 133),
    "eraser":        (290, 154, 322, 185),
    "eyedropper":    (336, 154, 372, 186),
    "magnifier":     (390, 158, 418, 190),
    "brush":         (462, 116, 490, 152),
    "style_outline": (694, 108, 724, 133),
    "style_fill":    (758, 121, 796, 154),
    "style_bucket":  (694, 156, 724, 186),
    "copilot":       (1276, 116, 1318, 156),
}


def ink_bbox(arr, box, bg_tol=26):
    x0, y0, x1, y1 = box
    reg = arr[y0:y1, x0:x1].astype(int)
    # 背景 = 区域内出现最多的颜色
    cols, counts = np.unique(reg.reshape(-1, 3), axis=0, return_counts=True)
    bg = cols[counts.argmax()]
    d = np.abs(reg - bg).sum(axis=2)
    ys, xs = np.where(d > bg_tol)
    if len(xs) == 0:
        return None
    return (xs.min() + x0, ys.min() + y0, xs.max() + x0, ys.max() + y0)


def main():
    mine_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v12.png"
    o = np.array(Image.open(ORIG).convert("RGB"))
    m = np.array(Image.open(mine_path).convert("RGB"))
    print(f"feature        ORIG (l,t,r,b)            MINE (l,t,r,b)             Δl,Δt  Δw,Δh")
    for name, box in REGIONS.items():
        bo = ink_bbox(o, box)
        bm = ink_bbox(m, box)
        if bo is None or bm is None:
            print(f"{name:14s} {bo} {bm}")
            continue
        dl, dt = bm[0] - bo[0], bm[1] - bo[1]
        dw = (bm[2] - bm[0]) - (bo[2] - bo[0])
        dh = (bm[3] - bm[1]) - (bo[3] - bo[1])
        flag = "  <<<" if abs(dl) > 3 or abs(dt) > 3 or abs(dw) > 3 or abs(dh) > 3 else ""
        print(f"{name:14s} {str(bo):26s} {str(bm):26s} ({dl},{dt}) ({dw},{dh}){flag}")


if __name__ == "__main__":
    main()
