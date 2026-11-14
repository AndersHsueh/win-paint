# UI 复刻对照

> 生成时间:2026-11-15 · 来源:`raw/4db8b22c7b5a996a230c43ae5b547887.png` vs 本机自渲染快照

## 文件

| 文件 | 说明 |
|------|------|
| `原版vs复刻_整窗对照.png` | 上半是 Windows 11 原版画图截图,下半是 macOS 复刻版(同尺寸 1484×985,同 sRGB) |
| `像素差异热力图.png` | 逐像素绝对差的伪彩图。**黑色 = 完全一致**,越亮差得越多。已排除画布照片区(原版是照片、复刻是空白画布)和最外 2px 窗口阴影框 |
| `复刻快照_1484x985.png` | 复刻版单张快照(`WINPAINT_SNAPSHOT` 自渲染,不经屏幕录制) |

## 当前指标

`tools/metric.py` 口径(排除画布照片区 + 最外 2px DWM 阴影框):

- 全图 meanΔ = **3.06**,>6 像素占比 5.2%

## 差异热力图里还亮着的地方,以及原因

| 区域 | 原因 | 能不能修 |
|------|------|---------|
| 标题文字 / 菜单文字 / 组名 / 状态栏读数 | macOS 没有 Segoe UI 与微软雅黑。用系统字体按实测字宽、字高、笔画墨量对齐后,残留的是字形本身不同 | 除非拿到正版 Segoe UI / 雅黑,否则到顶了 |
| 色板圆环边缘、选择框、浮层把手 | 1px 抗锯齿边缘的亚像素差异 | 收益极小 |
| 左侧浮动滑块(笔刷预览图标) | 原版是 4 条平行斜线的位图纹理,复刻是矢量画的 | 可以改成抠图,收益小 |
| 画布照片区 | 原版是照片,复刻是空白画布 | 指标已排除 |

## 怎么重新生成

```bash
swift build -c release
./scripts/build-app.sh release

WINPAINT_SNAPSHOT=/tmp/wp.png WINPAINT_SNAPSHOT_SIZE=1484x985 WINPAINT_SNAPSHOT_EXIT=1 \
WINPAINT_SNAPSHOT_TITLE=pragmata-capcom-spotlight-social \
  ./dist/WinPaint.app/Contents/MacOS/WinPaint

/opt/homebrew/bin/python3 tools/metric.py /tmp/wp.png
```
