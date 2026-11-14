import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// 与平台无关的 RGBA 颜色。模型层只认它,不让 NSColor / SwiftUI Color 渗进渲染代码。
struct RGBA: Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// 拾色器用:把不透明色拆成 hsv,方便用 SwiftUI 的 ColorPicker 双向绑定
    var hue: Double { ColorConverter.rgbToHue(r, g, b) }
    var saturation: Double { ColorConverter.rgbToSaturation(r, g, b) }
    var brightness: Double { max(r, max(g, b)) }

    var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    static let black = RGBA(0, 0, 0)
    static let white = RGBA(1, 1, 1)
    static let red = RGBA(1, 0, 0)
    static let green = RGBA(0, 1, 0)
    static let blue = RGBA(0, 0, 1)

    /// Windows 画图标准色板 2×10(从原版截图逐格采样得到)
    static let standardPalette: [RGBA] = [
        // 第 1 行
        RGBA(0, 0, 0), RGBA(0.498, 0.498, 0.498), RGBA(0.455, 0, 0.071), RGBA(0.929, 0.110, 0.141),
        RGBA(1, 0.498, 0.153), RGBA(1, 0.949, 0), RGBA(0.133, 0.694, 0.298), RGBA(0, 0.635, 0.910),
        RGBA(0.247, 0.282, 0.800), RGBA(0.639, 0.286, 0.643),
        // 第 2 行
        RGBA(1, 1, 1), RGBA(0.737, 0.737, 0.737), RGBA(0.698, 0.463, 0.329), RGBA(0.965, 0.659, 0.761),
        RGBA(0.965, 0.761, 0.055), RGBA(0.906, 0.863, 0.667), RGBA(0.686, 0.871, 0.110), RGBA(0.580, 0.820, 0.886),
        RGBA(0.424, 0.553, 0.718), RGBA(0.757, 0.722, 0.875),
    ]
}

/// RGB ↔ HSV 互转,供 SwiftUI ColorPicker 与模型层对接
enum ColorConverter {
    static func rgbToHue(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let delta = maxV - minV
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxV == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxV == g {
            hue = ((b - r) / delta) + 2
        } else {
            hue = ((r - g) / delta) + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return hue / 360
    }

    static func rgbToSaturation(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        guard maxV > 0 else { return 0 }
        return (maxV - minV) / maxV
    }

    static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
        guard s > 0 else { return RGBA(v, v, v) }
        let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let i = Int(hh.rounded(.down))
        let f = hh - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return RGBA(v, t, p)
        case 1: return RGBA(q, v, p)
        case 2: return RGBA(p, v, t)
        case 3: return RGBA(p, q, v)
        case 4: return RGBA(t, p, v)
        default: return RGBA(v, p, q)
        }
    }
}

/// 画笔参数
struct BrushSettings: Equatable {
    /// 直径(像素)
    var size: CGFloat = 1
    var color: RGBA = .black
    /// 不透明度(对应左侧浮动条的第二根滑块)
    var opacity: Double = 1.0
    /// 橡皮擦:true 时用 destinationOut 擦除而不是涂色
    var isEraser: Bool = false

    static let sizePresets: [CGFloat] = [1, 2, 3, 5, 8, 12, 18, 25]
}

/// 形状类型。顺序与 Windows 11 画图形状库完全一致(从左上角开始,5 列一行)。
enum ShapeKind: String, CaseIterable, Identifiable {
    case line
    case curve
    case ellipse
    case rectangle
    case roundedRectangle
    case polygon
    case triangle
    case rightTriangle
    case diamond
    case pentagon
    case hexagon
    case arrowRight
    case arrowLeft
    case arrowUp
    case arrowDown
    case fourPointStar
    case fivePointStar
    case sixPointStar
    case calloutRectangle
    case calloutOval
    case cloudCallout
    case heart
    case lightning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .line: return "直线"
        case .curve: return "曲线"
        case .ellipse: return "椭圆"
        case .rectangle: return "矩形"
        case .roundedRectangle: return "圆角矩形"
        case .polygon: return "多边形"
        case .triangle: return "三角形"
        case .rightTriangle: return "直角三角形"
        case .diamond: return "菱形"
        case .pentagon: return "五边形"
        case .hexagon: return "六边形"
        case .arrowRight: return "右箭头"
        case .arrowLeft: return "左箭头"
        case .arrowUp: return "上箭头"
        case .arrowDown: return "下箭头"
        case .fourPointStar: return "四角星"
        case .fivePointStar: return "五角星"
        case .sixPointStar: return "六角星"
        case .calloutRectangle: return "矩形标注"
        case .calloutOval: return "椭圆标注"
        case .cloudCallout: return "云形标注"
        case .heart: return "心形"
        case .lightning: return "闪电"
        }
    }

    /// 形状库里显示的小图标
    var galleryIcon: WIShapeIcon {
        switch self {
        case .line: return .line
        case .curve: return .curve
        case .ellipse: return .oval
        case .rectangle: return .square
        case .roundedRectangle: return .roundedSquare
        case .polygon: return .polygon
        case .triangle: return .triangle
        case .rightTriangle: return .rightTriangle
        case .diamond: return .diamond
        case .pentagon: return .pentagon
        case .hexagon: return .hexagon
        case .arrowRight: return .arrowRight
        case .arrowLeft: return .arrowLeft
        case .arrowUp: return .arrowUp
        case .arrowDown: return .arrowDown
        case .fourPointStar: return .fourStar
        case .fivePointStar: return .fiveStar
        case .sixPointStar: return .sixStar
        case .calloutRectangle: return .calloutRect
        case .calloutOval: return .calloutOval
        case .cloudCallout: return .cloudCallout
        case .heart: return .calloutOval
        case .lightning: return .line
        }
    }
}

/// 形状的填充样式
enum FillStyle: String, CaseIterable, Identifiable {
    case solid
    case none

    var id: String { rawValue }
    var displayName: String { self == .solid ? "实心" : "无填充" }
}

/// 形状轮廓开关。
/// 注意命名:不能叫 `StrokeStyle`,那会顶掉 SwiftUI / GraphicsContext 的同名类型。
enum OutlineStyle: String, CaseIterable, Identifiable {
    case stroked
    case none

    var id: String { rawValue }
    var displayName: String { self == .stroked ? "有轮廓" : "无轮廓" }
}

/// 当前工具
enum PaintTool: String, CaseIterable, Identifiable {
    case select
    case freehandSelect
    case crop
    case pencil
    case brush
    case fill
    case text
    case eraser
    case eyedropper
    case magnifier
    case shape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "选择"
        case .freehandSelect: return "手绘选择"
        case .crop: return "裁剪"
        case .pencil: return "铅笔"
        case .brush: return "画笔"
        case .fill: return "填充"
        case .text: return "文本"
        case .eraser: return "橡皮擦"
        case .eyedropper: return "取色器"
        case .magnifier: return "放大镜"
        case .shape: return "形状"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "rectangle.dashed"
        case .freehandSelect: return "lasso"
        case .crop: return "crop"
        case .pencil: return "pencil.tip"
        case .brush: return "paintbrush"
        case .fill: return "paintbucket"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .eyedropper: return "eyedropper"
        case .magnifier: return "magnifyingglass"
        case .shape: return "square.on.circle"
        }
    }
}
