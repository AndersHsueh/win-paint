import AppKit
import SwiftUI

/// 底部状态栏。字段顺序、图标与间距对齐 Windows 画图:
/// 光标 → 选区 → 画布尺寸 → 文件大小 …… 适应窗口 → 100% 下拉框 → 缩放滑块。
///
/// 全部按原版截图逐像素量的坐标排版(窗口宽 1484 时):
///   光标 19 | 分隔 155 | 选区 180 | 分隔 340 | 尺寸图标 350 | 文本 372
///   分隔 492 | 软盘 524 | 文本 550
///   适应 1061 | 100%框 1100..1215 | 缩小 1235 | 滑轨 1270..1431 | 放大 1449
///
/// 右侧缩放组不用 HStack 排版,改成「右端锚定 + 组内绝对坐标」。
/// 原版这组元素的间距是手工排的(100% 框右边到「缩小」之间空 21px、
/// 滑轨和「放大」之间空 17px),用 HStack 拼出来的间距总会差几个像素。
struct StatusBarView: View {
    @Bindable var controller: CanvasController
    let document: PaintDocument
    var onFitToWindow: () -> Void
    var onZoom: (CGFloat) -> Void

    /// 「大小」显示的是 PNG 编码后的字节数(和 Windows 画图一致)。
    /// PNG 编码一张 1200×630 的图要几十毫秒,拖动画笔时每帧都算会卡,
    /// 所以防抖 300ms 再更新。
    @State private var encodedSize: Int = 0

    /// 原版状态栏实际高度:938..983,共 46pt(不是 28)
    private static let barHeight: CGFloat = 46

    /// 右侧缩放组:从「适应」位图左缘(原版 1056)到「放大」位图右缘(原版 1472),
    /// 一共 428px;整组右端离窗口右边 12px。
    private static let zoomGroupWidth: CGFloat = 428
    private static let zoomGroupTrailing: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            // 左侧读数:绝对坐标排版,和原版逐像素对齐
            ZStack(alignment: .topLeading) {
                // 这四个图标是 Segoe MDL2 字形,手绘路径对不上(虚线框描边不足 1px
                // 会被抗锯齿压成灰色),直接用从原版抠下来的位图,原位贴回。
                WIBitmapIcon(name: "status_cursor")
                    .offset(x: 16, y: 13)
                    .help("光标模式")

                hairline.offset(x: 169, y: 10)

                WIBitmapIcon(name: "status_dash")
                    .offset(x: 179, y: 13)
                    .help("选区")

                hairline.offset(x: 334, y: 10)

                WIBitmapIcon(name: "status_size")
                    .offset(x: 344, y: 13)

                // 原版「1200 × 630像素」:数字走 Segoe UI,汉字走微软雅黑。
                // macOS 没有雅黑,汉字这一段单独换字面(Noto Sans CJK SC Thin 15.5),
                // 数字保持系统 light —— 混排用 Text + Text 拼,基线自动对齐。
                // 数字字号 13.7:实测 14.5 会让数字变宽 2~3px,和原版对不上,
                // 状态栏左半的 meanΔ 反而从 5.33 涨到 5.99 —— 别改。
                (Text(verbatim: "\(Int(document.size.width)) × \(Int(document.size.height))")
                    .font(.system(size: 13.7, weight: .light))
                 + Text(verbatim: "像素")
                    .font(WIFont.font(WIFont.Face.statusPixelCJK))
                    // 汉字字号比数字大,共享基线时整行被顶下去 5px,
                    // 数字归位后汉字还高 2px,再单独压回来
                    .baselineOffset(-2))
                    .monospacedDigit()
                    .foregroundStyle(WIPaint.ink)
                    .offset(x: 371, y: 10)

                hairline.offset(x: 499, y: 10)

                WIBitmapIcon(name: "floppy")
                    .offset(x: 515, y: 12)

                (Text(verbatim: "大小")
                    .font(WIFont.font(WIFont.Face.statusSizeCJK))
                 + Text(verbatim: ": \(ByteFormat.string(encodedSize))")
                    .font(.system(size: 13.7, weight: .light)))
                    .monospacedDigit()
                    .foregroundStyle(WIPaint.ink)
                    .offset(x: 546, y: 14)
            }
            .frame(width: 700, height: Self.barHeight, alignment: .topLeading)

            Spacer(minLength: 0)

            zoomGroup
                .frame(width: Self.zoomGroupWidth, height: Self.barHeight, alignment: .topLeading)
                .padding(.trailing, Self.zoomGroupTrailing)
        }
        .font(.system(size: 13, weight: .medium))
        .frame(height: Self.barHeight)
        .background(WIMica.horizontal(WIMica.workspaceBottom))
        .task(id: document.renderVersion) {
            // 防抖:画面停 300ms 才去算 PNG 体积
            try? await Task.sleep(nanoseconds: 300_000_000)
            encodedSize = document.encodedByteSize()
        }
    }

    // MARK: - 右侧缩放组(绝对坐标)

    /// 组内坐标 = 原版绝对坐标 - 1044(原版「适应」位图左缘在 1056,
    /// 组左缘对齐到窗口右边 440px 处)。
    private var zoomGroup: some View {
        ZStack(alignment: .topLeading) {
            // 适应窗口:墨迹 1061..1078 / 953..966
            WIBitmapIcon(name: "status_fit")
                .offset(x: 12, y: 11)

            // 100% 下拉框:原版 1100..1214 / 945..976
            zoomCombo
                .offset(x: 56, y: 7)

            // 缩小:墨迹 1236..1253 / 951..968
            WIBitmapIcon(name: "status_zoomout")
                .offset(x: 187, y: 8)

            // 滑轨:原版 1270..1432 / 959..963
            ZoomSlider(zoom: controller.zoom, onChange: onZoom)
                .frame(width: 163, height: Self.barHeight, alignment: .topLeading)
                .offset(x: 226, y: 0)

            // 放大:墨迹 1449..1466 / 951..968
            WIBitmapIcon(name: "status_zoomin")
                .offset(x: 400, y: 8)
        }
    }

    /// 组间竖线:原版在 x = 169 / 334 / 499,纵向 948..973(状态栏内的 26px)
    private var hairline: some View {
        Rectangle()
            .fill(WIPaint.separator)
            .frame(width: 1, height: 26)
    }

    /// 缩放百分比下拉框(原版是一个圆角矩形 + 右边一个 ▾)
    /// 注意:Menu 的 label 背景会被系统按钮吞掉,所以圆角框要画在 Menu 外面一层。
    ///
    /// 原版实测:框 1100..1214(宽 115)× 945..976(高 32),边框 (233,227,226),
    /// 框内 (253,251,251),「100%」墨迹 1117..1150 / 955..965,▾ 墨迹 1184..1193 / 958..963。
    private var zoomCombo: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 253.0 / 255.0, green: 251.0 / 255.0, blue: 251.0 / 255.0))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(red: 233.0 / 255.0, green: 227.0 / 255.0, blue: 226.0 / 255.0),
                              lineWidth: 1)

            Menu {
                ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { z in
                    Button("\(Int(z * 100))%") { onZoom(z) }
                }
                Divider()
                Button("适应窗口") { onFitToWindow() }
            } label: {
                Color.clear
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 115, height: 32)

            // 原版「100%」是 Segoe UI Semilight,笔画比 regular 细。
            // 扫描台实测:system 14.5 ultraLight 的 meanΔ 14.3,明显优于 regular。
            Text(controller.zoomText)
                .font(.system(size: 14.5, weight: .ultraLight))
                .monospacedDigit()
                .foregroundStyle(WIPaint.ink)
                .offset(x: 15, y: 4.5)

            // ▾ 在下拉框内侧(原版墨迹 1185..1193 / 958..963)。
            // 注意:offset 超出 ZStack 的 115pt 宽度也能画出来(SwiftUI 不裁),
            // 但一旦算错就会飘到外面的放大镜上 —— 曾经就飘过。
            WIBitmapIcon(name: "zoom_chev")
                .offset(x: 83, y: 10)
        }
        .frame(width: 115, height: 32)
    }
}

/// 缩放滑块:左段蓝、右段灰,把手是蓝色圆点外面套一圈白(原版样式)
///
/// 原版实测:滑轨 1270..1432(宽 163)、高 5px、纵向 959..963;
/// 蓝色段 1270..1293;把手中心 x = 1293(比轨道左端偏 23px);
/// 白盘直径 26 居中于 (1293, 961),内蓝点直径 12。
/// 所以 100% 不是轨道左端,而是偏左 14.1% 的位置。
struct ZoomSlider: View {
    let zoom: CGFloat
    var onChange: (CGFloat) -> Void

    /// 轨道宽度(原版实测 1270..1432)
    static let trackWidth: CGFloat = 163
    /// 轨道顶相对状态栏原点的 y(原版 959,状态栏顶 938)
    static let trackTop: CGFloat = 21
    /// 轨道高(原版 5px)
    static let trackHeight: CGFloat = 5
    /// 100% 时把手在轨道上的比例(原版:1293 - 1270 = 23)
    static let fitFraction: CGFloat = 23.0 / 163.0

    static func fraction(forZoom z: CGFloat) -> CGFloat {
        let zz = max(z, 0.05)
        if zz <= 1 {
            return fitFraction * (log(zz) - log(0.05)) / (log(1.0) - log(0.05))
        }
        return fitFraction + (1 - fitFraction) * (log(zz) - log(1.0)) / (log(8.0) - log(1.0))
    }

    static func zoom(forFraction f: CGFloat) -> CGFloat {
        let ff = min(max(f, 0), 1)
        if ff <= fitFraction {
            let t = ff / fitFraction
            return 0.05 * exp(log(1.0 / 0.05) * t)
        }
        let t = (ff - fitFraction) / (1 - fitFraction)
        return exp(log(8.0) * t)
    }

    var body: some View {
        GeometryReader { geo in
            let trackW = max(geo.size.width, 1)
            let fraction = Self.fraction(forZoom: zoom)
            let knobCenter = trackW * fraction

            ZStack(alignment: .topLeading) {
                // 灰色轨道
                RoundedRectangle(cornerRadius: Self.trackHeight / 2)
                    .fill(Color(red: 135.0 / 255.0, green: 134.0 / 255.0, blue: 135.0 / 255.0))
                    .frame(width: trackW, height: Self.trackHeight)
                    .offset(x: 0, y: Self.trackTop)

                // 蓝色段:从轨道左端到把手中心
                RoundedRectangle(cornerRadius: Self.trackHeight / 2)
                    .fill(WIPaint.accent)
                    .frame(width: max(knobCenter, 0), height: Self.trackHeight)
                    .offset(x: 0, y: Self.trackTop)

                // 白盘(原版直径 26,带 1px 浅灰描边)
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(red: 233.0 / 255.0, green: 227.0 / 255.0, blue: 226.0 / 255.0),
                                          lineWidth: 1)
                    )
                    .offset(x: knobCenter - 13, y: Self.trackTop - 11)

                // 内蓝点
                Circle()
                    .fill(WIPaint.accent)
                    .frame(width: 12, height: 12)
                    .offset(x: knobCenter - 6, y: Self.trackTop - 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = min(max(value.location.x / trackW, 0), 1)
                        onChange(Self.zoom(forFraction: f))
                    }
            )
        }
    }
}
