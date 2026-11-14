import AppKit
import SwiftUI

/// 画布左缘浮着的两枚竖向滑块卡片(Windows 画图原版就是浮在画布上的,不是旁边一列)。
///
/// 左卡 = 笔刷粗细(顶部是笔刷纹理),右卡 = 不透明度(顶部是油漆桶)。
///
/// **几何全部按原版截图逐像素量出来**(不是估的):
///   卡片外框 50×450 —— 卡片 1 占 x 16..65,卡片 2 占 x 76..125,顶边 y=356
///   卡片是 1px 边线(235,235,235)+ 48px 白底(248~250),**原版没有投影**
///   竖轨 x 39..43 / 99..103(5px 宽),纵向 407..789
///   把手:白盘 ⌀25 + 蓝芯 ⌀13,圆心行程 y 418..770
///   灰槽 = 竖轨的上段(把手顶边以上),蓝填充 = 下段(把手底边以下)
///
/// 「笔刷最细」时把手落到 770,灰槽占满 407..757,只剩轨道最底下 6px 是蓝的;
/// 「不透明度 100%」时把手升到 418,灰槽为空,整条轨道都是蓝的 —— 两个状态都和原版对得上。
struct ToolOptionsFloat: View {
    @Bindable var controller: CanvasController

    // MARK: 卡片内几何(相对卡片外框左上角,单位 pt)

    /// 卡片外框尺寸(原版:50×450,含 1px 边线)
    private let cardW: CGFloat = 50
    private let cardH: CGFloat = 450
    /// 竖轨左边(相对卡片外框左边):绝对 39 / 99,外框左边 16 / 76 → 23
    private let trackX: CGFloat = 23
    private let trackW: CGFloat = 5
    /// 竖轨顶 / 底(相对外框顶 356):绝对 407 / 789
    private let trackTop: CGFloat = 51
    private let trackBottom: CGFloat = 433
    /// 把手圆心行程(相对外框顶):最低 414(绝对 770)、最高 62(绝对 418)
    private let knobLow: CGFloat = 414
    private let knobHigh: CGFloat = 62
    /// 把手:白盘半径 / 蓝芯半径
    private let thumbR: CGFloat = 12.5
    private let dotR: CGFloat = 6.5
    /// 竖轨颜色:原版灰槽 (137,137,137)
    private let grooveGray = Color(white: 0.537)

    var body: some View {
        // 容器原点在画布区 (16, 356);卡片 1 就在原点,卡片 2 右移 60px
        ZStack(alignment: .topLeading) {
            card(icon: "brush_texture", iconOffset: CGSize(width: 12, height: 16),
                 value: sizeFraction) { newValue in
                controller.brush.size = 1 + CGFloat(newValue) * 24
            }

            card(icon: "brush_drop", iconOffset: CGSize(width: 13, height: 13),
                 value: opacityFraction) { newValue in
                controller.brush.opacity = newValue
            }
            .offset(x: 60, y: 0)
        }
        .frame(width: 110, height: 450, alignment: .topLeading)
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

    private func card(icon: String, iconOffset: CGSize, value: Double,
                      onChange: @escaping (Double) -> Void) -> some View {
        // 把手圆心 y(相对外框顶)
        let knobY = knobLow - value * (knobLow - knobHigh)
        // 灰槽:轨道上段,到把手顶边为止
        let grayH = max(knobY - thumbR - trackTop, 0)
        // 蓝填充:从把手底边到轨道底
        let blueH = max(trackBottom - (knobY + thumbR), 0)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(grooveGray)
                .frame(width: trackW, height: grayH)
                .offset(x: trackX, y: trackTop)

            Rectangle()
                .fill(WIPaint.accent)
                .frame(width: trackW, height: blueH)
                .offset(x: trackX, y: knobY + thumbR)

            // 把手:白盘(带一圈浅灰描边)+ 蓝芯
            Circle()
                .fill(Color.white)
                .frame(width: thumbR * 2, height: thumbR * 2)
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(WIPaint.accent)
                        .frame(width: dotR * 2, height: dotR * 2)
                )
                .offset(x: trackX + trackW / 2 - thumbR, y: knobY - thumbR)

            WIBitmapIcon(name: icon)
                .offset(x: iconOffset.width, y: iconOffset.height)
        }
        .frame(width: cardW, height: cardH, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.9725))
        )
        .overlay(
            // 原版卡片只有一圈 1px 边线(235,235,235),没有投影
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(white: 0.9216), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let v = min(max((knobLow - g.location.y) / (knobLow - knobHigh), 0), 1)
                    onChange(v)
                }
        )
    }
}
