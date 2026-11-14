import AppKit
import SwiftUI

/// 画布左缘浮着的两枚竖向滑块卡片(Windows 画图原版就是浮在画布上的,不是旁边一列)。
///
/// 左卡 = 笔迹(笔刷粗细),顶部是四道笔刷纹理斜线,滑块默认落在底部(笔刷最细)。
/// 右卡 = 油漆桶(不透明度),顶部是桶图标,滑块拉满,轨道整条是蓝的。
///
/// **几何全部按原版截图的绝对像素写死**(原版卡片 48×442,白底 #F8F8F8,
/// 轨道相对卡片左边偏 10px,滑块中心行程比可见轨道短)。
struct ToolOptionsFloat: View {
    @Bindable var controller: CanvasController

    // MARK: 卡片内几何(全部相对卡片左上角,单位 pt)

    private let cardWidth: CGFloat = 48
    private let cardHeight: CGFloat = 444
    /// 图标区高度(图标框 + 上边距)
    private let iconBlockH: CGFloat = 33
    /// 可见轨道:顶 / 底(相对卡片顶)
    private let trackTopRel: CGFloat = 26
    private let trackBottomRel: CGFloat = 403
    /// 滑块圆心:最高 / 最低(相对卡片顶)。两端都比轨道内缩 —— 原版把手的行程比
    /// 轨道短,滑块拉满/拉到底时轨道两头各露出一小截。
    private let knobTopRel: CGFloat = 65
    private let knobBottomRel: CGFloat = 408
    private let knobSize: CGFloat = 22
    /// 轨道 / 图标相对卡片中心的左偏量(原版轨道不在正中)
    private let trackShiftX: CGFloat = 0
    private let iconShiftX: CGFloat = -6.5

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            card(icon: .brushStroke, fraction: sizeFraction) { newValue in
                controller.brush.size = 1 + CGFloat(newValue) * 24
            }
            card(icon: .drop, fraction: opacityFraction) { newValue in
                controller.brush.opacity = newValue
            }
        }
        .frame(width: cardWidth * 2 + 12, height: cardHeight)
    }

    // MARK: 派生值

    /// 笔刷粗细 → 滑块位置(0 = 最细,在底部)
    private var sizeFraction: Double {
        let s = Double(controller.brush.size)
        return min(max((s - 1) / 24, 0), 1)
    }

    /// 不透明度 → 滑块位置(1 = 满,在顶部)
    private var opacityFraction: Double {
        min(max(controller.brush.opacity, 0), 1)
    }

    // MARK: 卡片

    private func card(icon: WIIcon, fraction: Double,
                      onChange: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 0) {
            WIIconView(icon: icon, size: 25)
                .frame(width: iconSizeBox, height: 25)
                .offset(x: iconShiftX, y: 10)
                .frame(width: cardWidth)
                .frame(height: iconBlockH, alignment: .top)

            GeometryReader { geo in
                // 换算到 GeometryReader 内部坐标
                let trackTop = trackTopRel - iconBlockH
                let trackBottom = trackBottomRel - iconBlockH
                let usable = max(trackBottom - trackTop, 1)
                let knobTop = knobTopRel - iconBlockH
                let knobBottom = knobBottomRel - iconBlockH
                let knobY = knobTop + (1 - fraction) * (knobBottom - knobTop)
                let trackX = (geo.size.width - 5) / 2 + trackShiftX
                // 蓝色已填充段:从滑块圆心一直到轨道底(略多出把手半径)
                // 蓝色是「已填充比例」:从轨道底往上长,和滑块位置解耦。
                // 原版左卡(笔刷最小)整条是灰的,右卡(不透明度 100%)整条是蓝的。
                let blueHeight = max(usable * fraction, 0)
                let blueTop = trackBottom - blueHeight

                ZStack(alignment: .topLeading) {
                    // 灰轨
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.541))
                        .frame(width: 5, height: usable)
                        .offset(x: trackX, y: trackTop)

                    // 蓝色已填充段
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WIPaint.accent)
                        .frame(width: 5, height: blueHeight)
                        .offset(x: trackX, y: blueTop)

                    // 滑块把手:白底圆 + 蓝芯
                    Circle()
                        .fill(Color(white: 0.97))
                        .frame(width: knobSize, height: knobSize)
                        .overlay(
                            Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .fill(fraction > 0.02 ? WIPaint.accent : Color(white: 0.72))
                                .frame(width: knobSize * 0.52, height: knobSize * 0.52)
                        )
                        .offset(x: (geo.size.width - knobSize) / 2 + trackShiftX,
                                y: knobY - knobSize / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let local = value.location.y - knobTop
                            let f = min(max(1 - local / max(knobBottom - knobTop, 1), 0), 1)
                            onChange(f)
                        }
                )
            }
            .frame(width: cardWidth, height: cardHeight - iconBlockH)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.9725))
                .shadow(color: .black.opacity(0.22), radius: 6, x: 1, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    /// 图标框宽度(比卡片窄一点,再靠左偏)
    private var iconSizeBox: CGFloat { cardWidth }
}
