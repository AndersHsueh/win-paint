#!/usr/bin/env python3
"""文字参数扫描驱动器:生成 spec → 调 textprobe 渲染 → 调 textscore 打分排序。

用法: sweep.py <text> <x0> <y0> <x1> <y1> <originX> <originY> <outDir> <stage>
  stage = coarse : 字号 13~17 step 0.25 × 字重 5 档
  stage = fine   : 在指定字号附近 step 0.05,字重 5 档 × tracking -1~1 step 0.25
  stage = xscale : 固定字号/字重,scaleX 0.9~1.3 step 0.01
环境变量调参:
  SWEEP_SIZE_MIN / SWEEP_SIZE_MAX / SWEEP_SIZE_STEP
  SWEEP_WEIGHTS      (空格分隔)
  SWEEP_TRACK        (起始 tracking)
  SWEEP_SCX_MIN / SWEEP_SCX_MAX / SWEEP_SCX_STEP
"""
import json
import os
import subprocess
import sys

text, x0, y0, x1, y1, ox, oy, outdir, stage = sys.argv[1:10]
x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
ox, oy = float(ox), float(oy)
W, H = x1 - x0, y1 - y0

smin = float(os.environ.get("SWEEP_SIZE_MIN", 13))
smax = float(os.environ.get("SWEEP_SIZE_MAX", 17))
sstep = float(os.environ.get("SWEEP_SIZE_STEP", 0.25))
weights = os.environ.get("SWEEP_WEIGHTS", "ultraLight light regular medium semibold").split()
track = float(os.environ.get("SWEEP_TRACK", 0))
cxmin = float(os.environ.get("SWEEP_SCX_MIN", 1.0))
cxmax = float(os.environ.get("SWEEP_SCX_MAX", 1.0))
cxstep = float(os.environ.get("SWEEP_SCX_STEP", 0.01))

cands = []
if stage == "coarse":
    n = int(round((smax - smin) / sstep))
    for i in range(n + 1):
        size = round(smin + i * sstep, 4)
        for w in weights:
            cands.append({"size": size, "weight": w, "tracking": track, "scaleX": 1.0})
elif stage == "fine":
    n = int(round((smax - smin) / sstep))
    for i in range(n + 1):
        size = round(smin + i * sstep, 4)
        for w in weights:
            for t in (track,):
                cands.append({"size": size, "weight": w, "tracking": t, "scaleX": 1.0})
elif stage == "fonts":
    # 跨字体扫描:SWEEP_FONTS 是 "PostScript名:字号起点" 列表,逗号分隔
    # 例: SWEEP_FONTS="PingFangSC-UltraLight,PingFangSC-Light,HiraginoSansGB-W3"
    ps_list = os.environ.get("SWEEP_FONTS", "PingFangSC-UltraLight,PingFangSC-Light,PingFangSC-Regular").split(",")
    n = int(round((smax - smin) / sstep))
    for ps in ps_list:
        for i in range(n + 1):
            size = round(smin + i * sstep, 4)
            cands.append({"size": size, "weight": "regular", "tracking": track, "scaleX": 1.0, "ps": ps})
elif stage == "xscale":
    n = int(round((cxmax - cxmin) / cxstep))
    for i in range(n + 1):
        cx = round(cxmin + i * cxstep, 4)
        for w in weights:
            cands.append({"size": smin, "weight": w, "tracking": track, "scaleX": cx})
else:
    raise SystemExit("unknown stage " + stage)

os.makedirs(outdir, exist_ok=True)
spec = {"text": text, "W": W, "H": H, "originX": ox, "originY": oy,
        "outDir": outdir, "candidates": cands}
sp = os.path.join(outdir, "spec.json")
json.dump(spec, open(sp, "w"))
subprocess.run(["/tmp/textprobe", sp], check=True)
subprocess.run(["/opt/homebrew/bin/python3", "tools/textscore.py",
                "raw/4db8b22c7b5a996a230c43ae5b547887.png", outdir,
                str(x0), str(y0), str(x1), str(y1), "15", "5"], check=True)
