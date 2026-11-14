#!/usr/bin/env python3
"""全图差异指标 + 分区拆解。

排除两块「不是 App UI」的像素:
  1. 画布照片内容区(原版画布里是照片,复刻版是空白画布)
  2. 最外 2px 边框(原版截图把 Win11 的 DWM 窗口阴影一起截进来了,
     左列亮度 58/右列 174/顶行是壁纸色渐变,这些是操作系统装饰,不是界面)
"""
import sys
import numpy as np
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(int)


def main():
    mine = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_final.png"
    o = load(ORIG)
    a = load(mine)
    d = np.abs(o - a).max(axis=2)
    m = np.ones(d.shape, bool)
    m[264:896, 142:1342] = False          # 画布照片区
    m[0:2, :] = False; m[-2:, :] = False  # 窗口阴影框
    m[:, 0:2] = False; m[:, -2:] = False
    d2 = np.where(m, d, 0)
    tot = d2.sum()
    print(f"全图 meanΔ={tot/m.sum():.2f}   >6 像素占比={(d[m]>6).sum()*100/m.sum():.1f}%")

    def c(x0, y0, x1, y1, label):
        reg = d2[y0:y1, x0:x1]
        print(f"  {label:20s} meanΔ={reg.mean():6.2f}  占全局={reg.sum()/tot*100:5.1f}%")

    print("\n标题栏:")
    c(0, 0, 30, 32, "  调色板图标"); c(30, 0, 320, 32, "  标题文字")
    c(320, 0, 1320, 32, "  空白"); c(1320, 0, 1484, 32, "  窗口按钮")
    print("\n菜单行:")
    c(0, 32, 220, 88, "  菜单文字区"); c(220, 32, 420, 88, "  图标区")
    c(1380, 32, 1484, 88, "  喇叭齿轮")
    print("\n功能区:")
    for n, x0, x1 in [("  选择组", 0, 71), ("  图像组", 72, 269), ("  工具组", 270, 440),
                      ("  画笔组", 441, 505), ("  形状组", 506, 816), ("  颜色组", 817, 1257),
                      ("  Copilot", 1258, 1337), ("  层", 1338, 1420)]:
        c(x0, 89, x1, 225, n)
    print("\n状态栏:")
    c(0, 937, 700, 985, "  左半"); c(700, 937, 1484, 985, "  右半")
    print("\n其它:")
    c(0, 225, 1484, 264, "  画布上方留白"); c(0, 896, 1484, 937, "  画布下方留白")


if __name__ == "__main__":
    main()
