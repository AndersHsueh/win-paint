import SwiftUI

// MARK: - Mica 背景场
//
// Windows 11 画图的窗口不是纯色铺底,而是 Mica 材质跟着系统壁纸染出来的渐变。
// 原版截图(1484×985)里量到的实际取值:
//
//   标题栏 / 菜单行   左上 (244,243,237) 暖奶油 → 右上 (244,243,241) 偏冷
//   功能区           Mica 之上再蒙一层半透明白,整体更亮 (250,250,245)…(249,249,247)
//   画布区 / 状态栏   顶部 (244,244,235) 暖奶油 → 底部 (245,241,246) 粉白,
//                     中段 x≈250 偏蓝 (242,242,249)
//
// 下面每一条色板都是从原版截图逐像素采出来的,照抄即可,不要凭感觉调。
// 横向变化用多段 LinearGradient stop 还原;
// 竖向变化用「上沿色板打底 + 下沿色板叠竖向 alpha 遮罩」,等价于 lerp(上沿色, 下沿色, t)。

enum WIMica {
    /// (窗口横坐标, r, g, b)
    typealias Stop = (x: CGFloat, rgb: (Double, Double, Double))

    /// 色板是按这个宽度采样的;窗口更宽时最后一个 stop 一直延伸出去
    static let referenceWidth: CGFloat = 1484

    // MARK: 色板

    /// 标题栏 + 菜单行。采样自原版 y=76..86(菜单文字下缘之下,无内容)
    static let chrome: [Stop] = [
        (0,    (244, 243, 237)),
        (120,  (245, 243, 236)),
        (240,  (246, 243, 235)),
        (360,  (247, 243, 233)),
        (480,  (249, 242, 231)),
        (596,  (249, 242, 232)),
        (670,  (249, 242, 233)),
        (744,  (249, 242, 234)),
        (818,  (249, 242, 234)),
        (892,  (249, 241, 235)),
        (966,  (248, 241, 236)),
        (1040, (247, 242, 238)),
        (1114, (247, 242, 239)),
        (1188, (246, 242, 240)),
        (1262, (245, 242, 241)),
        (1336, (245, 242, 241)),
        (1410, (244, 243, 241)),
        (1483, (244, 243, 241))
    ]

    /// 功能区。采样自原版 y=188..216
    static let ribbon: [Stop] = [
        (0,    (250, 250, 245)),
        (340,  (250, 250, 245)),
        (480,  (251, 249, 245)),
        (620,  (251, 249, 244)),
        (760,  (251, 249, 245)),
        (900,  (251, 249, 246)),
        (1040, (251, 249, 247)),
        (1180, (250, 249, 247)),
        (1320, (250, 249, 248)),
        (1460, (249, 249, 247)),
        (1483, (249, 249, 247))
    ]

    /// 画布区上沿。采样自原版 y=228..262(文档之上)
    static let workspaceTop: [Stop] = [
        (0,    (244, 244, 235)),
        (300,  (244, 244, 235)),
        (448,  (245, 244, 235)),
        (522,  (245, 243, 235)),
        (596,  (245, 243, 235)),
        (670,  (246, 243, 235)),
        (744,  (246, 243, 235)),
        (818,  (246, 243, 236)),
        (892,  (246, 243, 237)),
        (966,  (246, 243, 238)),
        (1040, (246, 243, 238)),
        (1114, (245, 242, 239)),
        (1188, (245, 243, 239)),
        (1262, (245, 243, 239)),
        (1336, (244, 243, 239)),
        (1410, (244, 243, 239)),
        (1483, (243, 243, 239))
    ]

    /// 画布区下沿 / 状态栏。采样自原版 y=900..936 与 y=942..982,两者实测一致
    static let workspaceBottom: [Stop] = [
        (0,    (245, 241, 246)),
        (78,   (244, 242, 247)),
        (152,  (243, 242, 248)),
        (226,  (243, 242, 249)),
        (300,  (242, 242, 249)),
        (374,  (243, 242, 249)),
        (448,  (244, 242, 248)),
        (522,  (245, 242, 245)),
        (596,  (246, 241, 244)),
        (670,  (247, 241, 243)),
        (744,  (247, 241, 242)),
        (818,  (248, 241, 241)),
        (892,  (248, 241, 240)),
        (966,  (248, 241, 240)),
        (1040, (249, 241, 240)),
        (1114, (249, 241, 240)),
        (1188, (248, 241, 240)),
        (1262, (247, 241, 241)),
        (1336, (246, 242, 242)),
        (1410, (245, 242, 244)),
        (1483, (244, 242, 244))
    ]

    // MARK: 取色

    static func color(_ rgb: (Double, Double, Double)) -> Color {
        Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }

    /// 在一行采样点里按 x 线性插值
    static func sample(_ row: [Stop], _ x: CGFloat) -> (Double, Double, Double) {
        guard let first = row.first, let last = row.last else { return (255, 255, 255) }
        if x <= first.x { return first.rgb }
        if x >= last.x { return last.rgb }
        for i in 1..<row.count {
            let a = row[i - 1]
            let b = row[i]
            if x <= b.x {
                let t = (x - a.x) / (b.x - a.x)
                return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t,
                        a.rgb.1 + (b.rgb.1 - a.rgb.1) * t,
                        a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
            }
        }
        return last.rgb
    }

    /// 一行采样点 → 横向渐变 stop
    static func stops(_ row: [Stop]) -> [Gradient.Stop] {
        row.map { Gradient.Stop(color: color($0.rgb), location: $0.x / referenceWidth) }
    }

    static func horizontal(_ row: [Stop]) -> LinearGradient {
        LinearGradient(stops: stops(row), startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - 画布区背景

/// 画布区的 Mica 背景。
///
/// 上沿色板打底,下沿色板用一条竖向 alpha 遮罩叠上去 —— 等价于
/// `lerp(上沿色, 下沿色, t)`,t 从顶到底线性增长。
/// 状态栏直接用下沿色板(实测两者色值一致),整条 Mica 场就接上了。
struct MicaWorkspaceBackground: View {
    var body: some View {
        ZStack {
            WIMica.horizontal(WIMica.workspaceTop)
            WIMica.horizontal(WIMica.workspaceBottom)
                .mask(LinearGradient(colors: [.clear, .white],
                                     startPoint: .top, endPoint: .bottom))
        }
    }
}

// MARK: - 行界分隔线

/// 原版三道行界横线(菜单行/功能区、功能区/画布区、画布区/状态栏)都是 1px #EBEBEB
struct WIDividerLine: View {
    var body: some View {
        Rectangle()
            .fill(WIPaint.divider)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
