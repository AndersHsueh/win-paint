import AppKit
import SwiftUI

/// 底部状态栏。字段顺序、图标与间距对齐 Windows 画图:
/// 光标 → 选区 → 画布尺寸 → 文件大小 …… 适应窗口 → 100% 下拉框 → 缩放滑块。
///
/// 全部按原版截图逐像素量的坐标排版(窗口宽 1484 时):
///   光标 19 | 分隔 155 | 选区 180 | 分隔 340 | 尺寸图标 350 | 文本 372
///   分隔 492 | 软盘 524 | 文本 550
///   适应 1061 | 100%框 1100..1215 | 缩小 1235 | 滑轨 1270..1431 | 放大 1449
struct StatusBarView: View {
    @Bindable var controller: CanvasController
    let document: PaintDocument
    var onFitToWindow: () -> Void
    var onZoom: (CGFloat) -> Void

    /// 原版状态栏实际高度:938..983,共 46pt(不是 28)
    private static let barHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            // 左侧读数:绝对坐标排版,和原版逐像素对齐
            ZStack(alignment: .topLeading) {
                WIIconView(icon: .cursor, size: 13)
                    .offset(x: 18, y: 15)
                    .help("光标模式")

                hairline.offset(x: 169, y: 10)

                WIIconView(icon: .dashedSelect, size: 15)
                    .offset(x: 181, y: 15)
                    .help("选区")

                hairline.offset(x: 334, y: 10)

                WIIconView(icon: .imageFrame, size: 20)
                    .offset(x: 347, y: 15)

                Text(verbatim: "\(Int(document.size.width)) × \(Int(document.size.height))像素")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WIPaint.ink)
                    .offset(x: 375, y: 16)

                hairline.offset(x: 499, y: 10)

                WIIconView(icon: .save, size: 15)
                    .offset(x: 517, y: 15)

                Text(verbatim: "大小: \(ByteFormat.string(Int(document.size.width * document.size.height * 4)))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WIPaint.ink)
                    .offset(x: 553, y: 16)
            }
            .frame(width: 700, height: Self.barHeight, alignment: .topLeading)

            Spacer(minLength: 0)

            // 右侧缩放组:右端锚定,各段宽度按原版量取
            HStack(spacing: 0) {
                Button {
                    onFitToWindow()
                } label: {
                    WIIconView(icon: .fit, size: 18)
                        .frame(width: 18, height: Self.barHeight)
                }
                .buttonStyle(.plain)
                .help("适应窗口")

                gap(21)

                zoomCombo

                gap(20)

                WIIconView(icon: .zoomOut, size: 20)
                    .frame(width: 18, height: Self.barHeight)
                    .help("缩小")

                gap(17)

                ZoomSlider(zoom: controller.zoom, onChange: onZoom)
                    .frame(width: 161, height: Self.barHeight)

                gap(18)

                WIIconView(icon: .zoomIn, size: 20)
                    .frame(width: 18, height: Self.barHeight)
                    .help("放大")
            }
            .padding(.trailing, 17)
        }
        .font(.system(size: 13, weight: .medium))
        .frame(height: Self.barHeight)
        .background(WIMica.horizontal(WIMica.workspaceBottom))
    }

    private func gap(_ w: CGFloat) -> some View {
        Color.clear.frame(width: w, height: 1)
    }

    /// 组间竖线:原版在 x = 169 / 334 / 499,纵向 948..973(状态栏内的 26px)
    private var hairline: some View {
        Rectangle()
            .fill(WIPaint.separator)
            .frame(width: 1, height: 26)
    }

    /// 缩放百分比下拉框(原版是一个圆角矩形 + 右边一个 ▾)
    /// 注意:Menu 的 label 背景会被系统按钮吞掉,所以圆角框要画在 Menu 外面一层。
    private var zoomCombo: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.992, green: 0.984, blue: 0.984))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)

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
            .frame(width: 115, height: 35)

            Text(controller.zoomText)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WIPaint.ink)
                .offset(x: 15, y: 13)

            WIIconView(icon: .chevronDown, size: 12)
                .offset(x: 92, y: 15)
        }
        .frame(width: 115, height: 35)
    }
}

/// 缩放滑块:左段蓝、右段灰,把手是蓝色圆点外面套一圈白(原版样式)
///
/// 原版实测:滑轨 1270..1431(宽 161),把手中心在 1293 处对应 100%。
/// 所以 100% 不是轨道左端,而是偏左 14.3% 的位置。
struct ZoomSlider: View {
    let zoom: CGFloat
    var onChange: (CGFloat) -> Void

    private let minZoom: CGFloat = 0.05
    private let maxZoom: CGFloat = 8

    /// 100% 时把手在轨道上的比例(按原版截图量取)
    static let fitFraction: CGFloat = 0.1429

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
            let knobSize: CGFloat = 26

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.66))
                    .frame(width: trackW, height: 4)
                    .offset(x: 0, y: 21)

                RoundedRectangle(cornerRadius: 2)
                    .fill(WIPaint.accent)
                    .frame(width: max(knobCenter, 0), height: 4)
                    .offset(x: 0, y: 21)

                Circle()
                    .fill(WIPaint.paper)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Circle()
                            .fill(WIPaint.accent)
                            .frame(width: 16, height: 16)
                    )
                    .offset(x: knobCenter - knobSize / 2, y: 10)
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
