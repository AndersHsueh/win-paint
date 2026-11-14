#!/usr/bin/env python3
"""图标 / 色块的「墨迹包围盒」逐项对比:原版 vs 自截图。

用法:
    python3 tools/diffbox.py <我的截图.png>

对每个取样区域,分别算出原版和复刻版的墨迹 bbox,打印 dx/dy/dw/dh,
方便直接照着改 Swift 里的 offset 与 size。

注意:截图必须在 sRGB 空间(DevSnapshot 已经做了 CI 转换),
否则饱和色的墨迹阈值会误判。
"""
import sys
import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"

# 名称 -> 取样窗口 (x0, y0, x1, y1),窗口要框住原版图标
REGIONS = {
    # 标题栏
    "title_palette":   (4,   2,  36,  32),
    "title_text":      (36,  2, 320,  32),
    "win_close":       (1430, 0, 1484, 32),
    # 菜单行
    "menu_file":       (14,  44,  60,  80),
    "menu_edit":       (86,  44, 130,  80),
    "menu_view":       (156, 44, 200,  80),
    "menu_save":       (226, 44, 258,  80),
    "menu_share":      (276, 44, 308,  80),
    "menu_undo":       (332, 44, 364,  80),
    "menu_redo":       (382, 44, 414,  80),
    "menu_speaker":    (1400,44, 1432,  80),
    "menu_gear":       (1440,44, 1470,  80),
    # 功能区
    "sel_rect":        (6,  112,  40, 146),
    "sel_dash":        (44, 108,  72, 138),
    "img_crop":        (90, 104, 122, 134),
    "img_rotate":      (140,104, 172, 134),
    "img_flip":        (180,104, 208, 134),
    "img_resize":      (212,124, 256, 164),
    "img_removebg":    (88, 152, 124, 188),
    "tool_pencil":     (286,104, 320, 136),
    "tool_fillcan":    (332,104, 368, 136),
    "tool_textA":      (386,104, 420, 136),
    "tool_eraser":     (286,152, 322, 188),
    "tool_eyedrop":    (332,152, 372, 188),
    "tool_magnifier":  (386,156, 420, 192),
    "brush_big":       (452,110, 496, 178),
    "brush_bucket":    (456,192, 496, 216),
    "style_outline":   (688,104, 728, 136),
    "style_fill":      (754,118, 798, 156),
    "style_bucket":    (688,152, 728, 188),
    "color_ring":      (828, 96, 876, 144),
    "color_wheel":     (1196,124,1240, 166),
    "copilot":         (1276,116,1318, 156),
    "layer_icon":      (1358,126,1398, 164),
    # 状态栏
    "sb_cursor":       (12, 944,  36,  976),
    "sb_size":         (176,946, 300,  974),
    "sb_filesize":     (340,946, 470,  974),
    "sb_fit":          (1054,940,1084, 976),
    "sb_zoombox":      (1094,938,1220, 980),
    "sb_zoomout":      (1228,938,1258, 976),
    "sb_slider":       (1264,938,1440, 976),
    "sb_zoomin":       (1442,938,1472, 976),
    # 形状库
    "shape_row1":      (524, 98,  682, 124),
    "shape_row2":      (524,126,  682, 152),
    "shape_row3":      (524,154,  682, 180),
}


def ink_bbox(arr, box, bg_tol=30):
    x0, y0, x1, y1 = box
    reg = arr[y0:y1, x0:x1].astype(int)
    # 背景色 = 区域内出现最多的颜色(取中位数更稳)
    bg = np.median(reg.reshape(-1, 3), axis=0)
    diff = np.abs(reg - bg).max(axis=2)
    mask = diff > bg_tol
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max(), y0 + ys.max())


def main():
    mine_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v34.png"
    o = np.asarray(Image.open(ORIG).convert("RGB"))
    m = np.asarray(Image.open(mine_path).convert("RGB"))
    print(f"原版 {o.shape}  我的 {m.shape}")
    print(f"{'名称':<16}{'原版 bbox':<28}{'我的 bbox':<28}{'dx dy dw dh'}")
    for name, box in REGIONS.items():
        bo = ink_bbox(o, box)
        bm = ink_bbox(m, box)
        if bo is None or bm is None:
            print(f"{name:<16} {'—' if bo is None else bo!s:<28}{'—' if bm is None else bm!s:<28}  (一方没墨迹)")
            continue
        dx = bm[0] - bo[0]
        dy = bm[1] - bo[1]
        dw = (bm[2] - bm[0]) - (bo[2] - bo[0])
        dh = (bm[3] - bm[1]) - (bo[3] - bo[1])
        flag = "  <<<" if (abs(dx) > 2 or abs(dy) > 2 or abs(dw) > 2 or abs(dh) > 2) else ""
        print(f"{name:<16}{str(bo):<28}{str(bm):<28}  {dx:+3d} {dy:+3d} {dw:+3d} {dh:+3d}{flag}")


if __name__ == "__main__":
    main()
