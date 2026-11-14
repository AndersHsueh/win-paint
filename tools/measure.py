#!/usr/bin/env python3
"""逐项测量原版截图与自截图在同一批特征上的位置,直接给出差值。
用法: python3 tools/measure.py
"""
import sys, colorsys
from PIL import Image

ORIG = "raw/4db8b22c7b5a996a230c43ae5b547887.png"
MINE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wp_v6.png"

def load(p):
    im = Image.open(p).convert("RGB")
    return im.load(), im.size

def bbox(pts):
    if not pts: return None
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))

def probes(px):
    W,H = 1484, 985
    out = {}
    def rng(x0,x1,y0,y1): return range(x0,x1), range(y0,y1)
    # 黑色实心块(主色盘 / 色板黑)
    out["primary_black"] = bbox([(x,y) for x in range(825,880) for y in range(95,145) if px[x,y]==(0,0,0)])
    out["swatch_black"]  = bbox([(x,y) for x in range(880,912) for y in range(95,145) if px[x,y]==(0,0,0)])
    # 蓝色高亮环
    out["primary_ring"] = bbox([(x,y) for x in range(820,880) for y in range(95,150)
                                if px[x,y][2]>140 and px[x,y][0]<110 and 80<px[x,y][1]<150 and px[x,y][2]-px[x,y][0]>60])
    # 白盘副色槽
    out["secondary_white"] = bbox([(x,y) for x in range(826,876) for y in range(140,195) if px[x,y]==(255,255,255)])
    # 第二行第一个白格(纯白 + 描边)
    out["swatch2_white"] = bbox([(x,y) for x in range(882,912) for y in range(128,160) if px[x,y]==(255,255,255)])
    # 第三行空位描边
    out["empty_slot"] = bbox([(x,y) for x in range(882,912) for y in range(158,195)
                              if abs(px[x,y][0]-px[x,y][2])<12 and 170<px[x,y][0]<225])
    # 选择组虚线方框(深色虚线段)
    out["select_dash"] = bbox([(x,y) for x in range(10,62) for y in range(95,145)
                               if sum(px[x,y])<620 and abs(px[x,y][0]-px[x,y][2])<40])
    # 工具组:铅笔黄
    out["pencil"] = bbox([(x,y) for x in range(285,320) for y in range(100,140)
                          if px[x,y][0]>180 and px[x,y][1]>130 and px[x,y][2]<130])
    # 工具组:文本 A
    out["textA"] = bbox([(x,y) for x in range(390,420) for y in range(100,140) if sum(px[x,y])<250])
    # 画笔组蓝框
    out["brush_frame"] = bbox([(x,y) for x in range(445,505) for y in range(100,190)
                               if px[x,y][2]>140 and px[x,y][0]<80 and 90<px[x,y][1]<150])
    # 形状库白面板(比周围功能区底色更白)
    out["shape_panel"] = bbox([(x,y) for x in range(510,700) for y in range(90,200)
                               if px[x,y][0]>250 and px[x,y][1]>250 and px[x,y][2]>248])
    # 图像组旋转蓝楔
    out["rotate_blue"] = bbox([(x,y) for x in range(135,175) for y in range(100,145)
                               if px[x,y][2]>140 and px[x,y][0]<110 and px[x,y][2]-px[x,y][0]>60])
    # 图像组翻转蓝
    out["flip_blue"] = bbox([(x,y) for x in range(135,175) for y in range(145,195)
                             if px[x,y][2]>140 and px[x,y][0]<110 and px[x,y][2]-px[x,y][0]>60])
    # 调整大小蓝
    out["resize_blue"] = bbox([(x,y) for x in range(205,260) for y in range(100,195)
                               if px[x,y][2]>140 and px[x,y][0]<110 and px[x,y][2]-px[x,y][0]>60])
    # 层图标(黑菱形)
    out["layers"] = bbox([(x,y) for x in range(1350,1410) for y in range(120,165) if sum(px[x,y])<300])
    # 状态栏:滑轨灰条
    out["slider_track"] = bbox([(x,y) for x in range(1300,1440) for y in range(950,975)
                                if 120<px[x,y][0]<185 and abs(px[x,y][0]-px[x,y][2])<12])
    out["slider_knob"] = bbox([(x,y) for x in range(1275,1315) for y in range(940,980)
                               if px[x,y][2]>170 and px[x,y][0]<120])
    # 100% 组合框(比 chrome 底色更白)
    out["zoom_box"] = bbox([(x,y) for x in range(1090,1225) for y in range(935,982)
                            if px[x,y][0]>250 and px[x,y][1]>250])
    # 组名文字底色(取"颜色"二字附近的深色像素)
    out["label_color"] = bbox([(x,y) for x in range(1010,1065) for y in range(190,215) if sum(px[x,y])<450])
    return out

def main():
    po, so = load(ORIG); pm, sm = load(MINE)
    print(f"orig {so}  mine {sm}\n")
    o = probes(po); m = probes(pm)
    print(f"{'feature':<18} {'ORIG (l,t,r,b)':<26} {'MINE (l,t,r,b)':<26} {'Δl,Δt':>12}")
    for k in o:
        a, b = o[k], m[k]
        if a is None or b is None:
            print(f"{k:<18} {str(a):<26} {str(b):<26} {'-':>12}")
            continue
        d = (b[0]-a[0], b[1]-a[1])
        flag = "" if (abs(d[0])<=3 and abs(d[1])<=3) else "   <<<"
        print(f"{k:<18} {str(a):<26} {str(b):<26} {str(d):>12}{flag}")

if __name__ == "__main__":
    main()
