import SwiftUI

// MARK: - 界面配色
//
// 取值全部来自 Windows 11 画图原版截图的逐像素采样:
// 原图是 125% DPI 截图(1484×985 px),换算成 100% 之后色值不变。
// Mica 材质会跟着系统强调色染暖,这里照抄采样到的暖米色。

enum WIPaint {
    /// 标题栏 / 菜单行底色 #F9F2EA(平铺时的兜底色;实际用 WIMica.chrome 横向渐变)
    static let chrome = Color(red: 0.9765, green: 0.9490, blue: 0.9176)
    /// 功能区底色 #FCF9F4(平铺时的兜底色;实际用 WIMica.ribbon 横向渐变)
    static let ribbon = Color(red: 0.9882, green: 0.9765, blue: 0.9569)
    /// 画布外底色 #F4F4EB(兜底色;实际用 WIMica 的二维 Mica 场)
    static let canvasBG = Color(red: 0.9569, green: 0.9569, blue: 0.9216)
    /// 行界分隔线 #EBEBEB(原版三道行界横线都是这个色)
    static let divider = Color(red: 0.9216, green: 0.9216, blue: 0.9216)
    /// 组间竖分隔线:黑色 6% 透明(原版菜单行、功能区、状态栏的竖线都是这个配比)
    static let separator = Color.black.opacity(0.06)
    /// UI 强调蓝 #0067C0(缩放滑块把手、画笔选中框、图层选中态)
    static let accent = Color(red: 0.0, green: 0.4039, blue: 0.7529)
    /// 图标里的强蓝 #005FB7(旋转楔、吸管球头)
    static let accentInk = Color(red: 0.0, green: 0.3725, blue: 0.7176)
    /// 中蓝 #3F85C7(调整大小的图片框)
    static let accentMid = Color(red: 0.2471, green: 0.5216, blue: 0.7804)
    /// 浅蓝 #7DACD6
    static let accentSoft = Color(red: 0.4902, green: 0.6745, blue: 0.8392)
    /// 图标浅灰描边 #A09F9D(裁剪、样式按钮)
    static let iconGrey = Color(red: 0.6275, green: 0.6235, blue: 0.6157)
    /// 正文近黑
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
    /// 次级灰(分隔线、箭头)
    static let inkSoft = Color(red: 0.40, green: 0.40, blue: 0.40)
    /// 细分割线
    static let hairline = Color.black.opacity(0.09)
    /// 纸白
    static let paper = Color.white
}

// MARK: - 图标枚举

enum WIIcon {
    case palette
    case crop, rotate, flip, resize, removeBackground
    case pencil, fillCan, textA, eraser, eyedropper, magnifier, brush
    case save, share, undo, redo, megaphone, gear, layers, add
    case cursor, fit, zoomOut, zoomIn, chevronDown, dashedSelect, selectBracket
    case brushStroke, imageFrame, drop
}

/// 形状库里的小图标(顺序与 Windows 画图一致)
enum WIShapeIcon {
    case line, curve, oval, square, roundedSquare, polygon
    case triangle, rightTriangle, diamond, pentagon, hexagon
    case arrowRight, arrowLeft, arrowUp, arrowDown
    case fourStar, fiveStar, sixStar
    case calloutRect, calloutOval, cloudCallout
}

// MARK: - 绘制

/// 统一在 24×24 的设计网格里作画,再整体缩放到目标尺寸。
/// 少数图标(调整大小)比 24 大,自己指定 `grid`。
struct WIIconView: View {
    var icon: WIIcon
    var size: CGFloat = 20
    var grid: CGFloat = 24

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / grid
            ctx.scaleBy(x: s, y: s)
            WIIconRenderer.render(icon, ctx: &ctx)
        }
        .frame(width: size, height: size)
    }
}

/// 形状库图标
struct WIShapeIconView: View {
    var icon: WIShapeIcon
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 24.0
            ctx.scaleBy(x: s, y: s)
            WIIconRenderer.renderShape(icon, ctx: &ctx)
        }
        .frame(width: size, height: size)
    }
}

enum WIIconRenderer {

    enum ArrowDir { case left, right, up, down }

    // MARK: 通用工具

    private static func fill(_ ctx: inout GraphicsContext, _ p: Path, _ c: Color) {
        ctx.fill(p, with: .color(c))
    }

    private static func stroke(_ ctx: inout GraphicsContext, _ p: Path, _ c: Color, _ w: CGFloat = 1.5) {
        ctx.stroke(p, with: .color(c),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    private static func dashed(_ ctx: inout GraphicsContext, _ p: Path, _ c: Color, _ w: CGFloat, _ pattern: [CGFloat]) {
        ctx.stroke(p, with: .color(c),
                   style: StrokeStyle(lineWidth: w, lineCap: .butt, dash: pattern))
    }

    private static func dot(_ ctx: inout GraphicsContext, _ center: CGPoint, _ r: CGFloat, _ c: Color) {
        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        fill(&ctx, p, c)
    }

    private static func poly(_ ctx: inout GraphicsContext, _ points: [CGPoint], _ c: Color) {
        var p = Path()
        guard let first = points.first else { return }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        fill(&ctx, p, c)
    }

    // MARK: 入口

    static func render(_ icon: WIIcon, ctx: inout GraphicsContext) {
        switch icon {
        case .palette: palette(&ctx)
        case .crop: crop(&ctx)
        case .rotate: rotate(&ctx)
        case .flip: flip(&ctx)
        case .resize: resize(&ctx)
        case .removeBackground: removeBackground(&ctx)
        case .pencil: pencil(&ctx)
        case .fillCan: fillCan(&ctx)
        case .textA: textA(&ctx)
        case .eraser: eraser(&ctx)
        case .eyedropper: eyedropper(&ctx)
        case .magnifier: magnifier(&ctx)
        case .brush: brush(&ctx)
        case .save: save(&ctx)
        case .share: share(&ctx)
        case .undo: undo(&ctx)
        case .redo: redo(&ctx)
        case .megaphone: megaphone(&ctx)
        case .gear: gear(&ctx)
        case .layers: layers(&ctx)
        case .add: add(&ctx)
        case .cursor: cursor(&ctx)
        case .fit: fit(&ctx)
        case .zoomOut: magnifierSign(&ctx, minus: true)
        case .zoomIn: magnifierSign(&ctx, minus: false)
        case .chevronDown: chevronDown(&ctx)
        case .dashedSelect: dashedSelect(&ctx)
        case .selectBracket: selectBracket(&ctx)
        case .brushStroke: brushStroke(&ctx)
        case .imageFrame: imageFrame(&ctx)
        case .drop: drop(&ctx)
        }
    }

    // MARK: 标题栏 / 菜单行

    /// 调色板(应用图标)
    ///
    /// 原版实测:墨迹 x 10..29 / y 9..28(标题栏左上角 20×20)。
    /// 构成:蓝色渐变调色板 + 黄/绿/红三块十字颜料 + 右侧竖画笔(米色笔毛 + 棕色笔杆)。
    static func palette(_ ctx: inout GraphicsContext) {
        // 蓝调色板本体:顶窄、左宽、底收成一条尾
        var back = Path()
        back.move(to: CGPoint(x: 13, y: 0.6))
        back.addCurve(to: CGPoint(x: 22, y: 9),
                      control1: CGPoint(x: 19, y: 0.6), control2: CGPoint(x: 22, y: 4))
        back.addCurve(to: CGPoint(x: 15, y: 14),
                      control1: CGPoint(x: 22, y: 12), control2: CGPoint(x: 18, y: 13))
        back.addLine(to: CGPoint(x: 15.6, y: 20.4))
        back.addCurve(to: CGPoint(x: 11, y: 21.6),
                      control1: CGPoint(x: 16.4, y: 22.2), control2: CGPoint(x: 13.4, y: 22.6))
        back.addCurve(to: CGPoint(x: 8.6, y: 17),
                      control1: CGPoint(x: 9, y: 21.2), control2: CGPoint(x: 8.6, y: 19))
        back.addCurve(to: CGPoint(x: 0.6, y: 12),
                      control1: CGPoint(x: 4.6, y: 16), control2: CGPoint(x: 1.6, y: 14.6))
        back.addCurve(to: CGPoint(x: 6, y: 3),
                      control1: CGPoint(x: 0.6, y: 8), control2: CGPoint(x: 2, y: 4.6))
        back.addCurve(to: CGPoint(x: 13, y: 0.6),
                      control1: CGPoint(x: 8, y: 1), control2: CGPoint(x: 10.6, y: 0.6))
        back.closeSubpath()
        ctx.fill(back, with: .linearGradient(
            Gradient(colors: [Color(red: 0.36, green: 0.80, blue: 0.96),
                              Color(red: 0.05, green: 0.55, blue: 0.84)]),
            startPoint: CGPoint(x: 4, y: 0),
            endPoint: CGPoint(x: 16, y: 22)))

        // 笔毛(米色,原版是一块明显的梯形笔毛)
        var bristle = Path()
        bristle.move(to: CGPoint(x: 18.8, y: 5.8))
        bristle.addLine(to: CGPoint(x: 22.6, y: 7.2))
        bristle.addCurve(to: CGPoint(x: 20.4, y: 12.4),
                         control1: CGPoint(x: 22.2, y: 9.4), control2: CGPoint(x: 21.4, y: 11))
        bristle.addLine(to: CGPoint(x: 16.8, y: 11.0))
        bristle.closeSubpath()
        fill(&ctx, bristle, Color(red: 0.855, green: 0.702, blue: 0.498))

        // 笔杆(棕)
        var handle = Path()
        handle.move(to: CGPoint(x: 16.8, y: 10.6))
        handle.addLine(to: CGPoint(x: 20.0, y: 11.9))
        handle.addLine(to: CGPoint(x: 17.6, y: 22.8))
        handle.addLine(to: CGPoint(x: 15.2, y: 22.0))
        handle.closeSubpath()
        fill(&ctx, handle, Color(red: 0.62, green: 0.365, blue: 0.012))

        // 拇指孔(原版调色板中间有个浅色小方孔)
        var hole = Path()
        hole.addRoundedRect(in: CGRect(x: 13.0, y: 12.6, width: 3.2, height: 3.2),
                            cornerSize: CGSize(width: 0.8, height: 0.8))
        fill(&ctx, hole, Color(white: 0.86))

        // 三块十字颜料
        plus(&ctx, CGPoint(x: 15, y: 4.6), 1.9, 1.6, Color(red: 0.96, green: 0.77, blue: 0.0))
        plus(&ctx, CGPoint(x: 6, y: 7.2), 1.9, 1.6, Color(red: 0.27, green: 0.66, blue: 0.055))
        plus(&ctx, CGPoint(x: 3.6, y: 11.6), 1.9, 1.6, Color(red: 0.85, green: 0.29, blue: 0.06))
    }

    /// 十字颜料点(原版就是三个小十字)
    private static func plus(_ ctx: inout GraphicsContext, _ c: CGPoint, _ arm: CGFloat,
                             _ w: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: c.x - arm, y: c.y))
        p.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - arm))
        p.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        // 平头:十字的两端是方的,不是圆头(圆头会变成四角星)
        ctx.stroke(p, with: .color(color),
                   style: StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter))
    }

    /// 撤销:左上箭头 + 向右下坠的曲线
    static func undo(_ ctx: inout GraphicsContext) {
        var curve = Path()
        curve.move(to: CGPoint(x: 20.5, y: 21.5))
        curve.addCurve(to: CGPoint(x: 4.6, y: 10),
                       control1: CGPoint(x: 15, y: 13.5), control2: CGPoint(x: 8.5, y: 10))
        stroke(&ctx, curve, WIPaint.inkSoft, 1.6)
        var head = Path()
        head.move(to: CGPoint(x: 1, y: 9.8))
        head.addLine(to: CGPoint(x: 6.8, y: 5.6))
        head.addLine(to: CGPoint(x: 6.4, y: 12.6))
        head.closeSubpath()
        fill(&ctx, head, WIPaint.inkSoft)
    }

    /// 重做:撤销的镜像
    static func redo(_ ctx: inout GraphicsContext) {
        var curve = Path()
        curve.move(to: CGPoint(x: 3.5, y: 21.5))
        curve.addCurve(to: CGPoint(x: 19.4, y: 10),
                       control1: CGPoint(x: 9, y: 13.5), control2: CGPoint(x: 15.5, y: 10))
        stroke(&ctx, curve, WIPaint.inkSoft, 1.6)
        var head = Path()
        head.move(to: CGPoint(x: 23, y: 9.8))
        head.addLine(to: CGPoint(x: 17.2, y: 5.6))
        head.addLine(to: CGPoint(x: 17.6, y: 12.6))
        head.closeSubpath()
        fill(&ctx, head, WIPaint.inkSoft)
    }

    /// 保存:软盘
    static func save(_ ctx: inout GraphicsContext) {
        var outline = Path()
        outline.move(to: CGPoint(x: 5.5, y: 2.5))
        outline.addLine(to: CGPoint(x: 15.5, y: 2.5))
        outline.addLine(to: CGPoint(x: 21.5, y: 8.5))
        outline.addLine(to: CGPoint(x: 21.5, y: 21.5))
        outline.addLine(to: CGPoint(x: 2.5, y: 21.5))
        outline.addLine(to: CGPoint(x: 2.5, y: 2.5))
        outline.closeSubpath()
        fill(&ctx, outline, WIPaint.paper)
        stroke(&ctx, outline, WIPaint.ink, 1.4)
        var shutter = Path()
        shutter.addRect(CGRect(x: 6.4, y: 4.6, width: 8.2, height: 5.6))
        stroke(&ctx, shutter, WIPaint.ink, 1.2)
        var label = Path()
        label.addRect(CGRect(x: 5.6, y: 13, width: 12.8, height: 6.6))
        stroke(&ctx, label, WIPaint.ink, 1.3)
    }

    /// 分享:开口方框 + 右上箭头
    static func share(_ ctx: inout GraphicsContext) {
        var box = Path()
        box.move(to: CGPoint(x: 11, y: 3.5))
        box.addLine(to: CGPoint(x: 5.4, y: 3.5))
        box.addQuadCurve(to: CGPoint(x: 2.6, y: 6.3), control: CGPoint(x: 2.6, y: 3.5))
        box.addLine(to: CGPoint(x: 2.6, y: 18.8))
        box.addQuadCurve(to: CGPoint(x: 5.4, y: 21.6), control: CGPoint(x: 2.6, y: 21.6))
        box.addLine(to: CGPoint(x: 16.8, y: 21.6))
        box.addQuadCurve(to: CGPoint(x: 19.6, y: 18.8), control: CGPoint(x: 19.6, y: 21.6))
        box.addLine(to: CGPoint(x: 19.6, y: 12.6))
        stroke(&ctx, box, WIPaint.ink, 1.5)
        var shaft = Path()
        shaft.move(to: CGPoint(x: 11, y: 15.6))
        shaft.addLine(to: CGPoint(x: 20, y: 6.6))
        stroke(&ctx, shaft, WIPaint.ink, 1.7)
        var head = Path()
        head.move(to: CGPoint(x: 13.2, y: 6))
        head.addLine(to: CGPoint(x: 20.6, y: 6))
        head.addLine(to: CGPoint(x: 20.6, y: 13.4))
        head.closeSubpath()
        fill(&ctx, head, WIPaint.ink)
    }

    /// 反馈:喇叭
    static func megaphone(_ ctx: inout GraphicsContext) {
        var horn = Path()
        horn.move(to: CGPoint(x: 2.6, y: 9.2))
        horn.addLine(to: CGPoint(x: 20.2, y: 3.4))
        horn.addLine(to: CGPoint(x: 20.2, y: 17.6))
        horn.addLine(to: CGPoint(x: 2.6, y: 14.2))
        horn.closeSubpath()
        fill(&ctx, horn, WIPaint.paper)
        stroke(&ctx, horn, WIPaint.ink, 1.5)
        var bump = Path()
        bump.move(to: CGPoint(x: 4.9, y: 14.6))
        bump.addCurve(to: CGPoint(x: 11.4, y: 14.6),
                      control1: CGPoint(x: 4.9, y: 19.8), control2: CGPoint(x: 11.4, y: 19.8))
        stroke(&ctx, bump, WIPaint.ink, 1.4)
    }

    /// 设置:齿轮
    static func gear(_ ctx: inout GraphicsContext) {
        var contour = Path()
        let teeth = 6
        let rootR: CGFloat = 6.6
        let tipR: CGFloat = 9.9
        for i in 0..<teeth {
            let base = Double(i) * 60.0 - 90.0
            let corners: [(CGFloat, Double)] = [
                (rootR, base - 21), (tipR, base - 10), (tipR, base + 10), (rootR, base + 21)
            ]
            for (j, corner) in corners.enumerated() {
                let ang = corner.1 * .pi / 180
                let x = 12 + corner.0 * CGFloat(cos(ang))
                let y = 12 + corner.0 * CGFloat(sin(ang))
                if i == 0 && j == 0 {
                    contour.move(to: CGPoint(x: x, y: y))
                } else {
                    contour.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        contour.closeSubpath()
        fill(&ctx, contour, WIPaint.paper)
        stroke(&ctx, contour, WIPaint.ink, 1.4)
        var hole = Path()
        hole.addEllipse(in: CGRect(x: 8.8, y: 8.8, width: 6.4, height: 6.4))
        stroke(&ctx, hole, WIPaint.ink, 1.4)
    }

    /// 层:三片叠起来的菱形
    /// 图层:上下两枚叠在一起的菱形(原版实测 26×26,x 1365..1390 / y 132..157)
    static func layers(_ ctx: inout GraphicsContext) {
        // 上菱形:顶点 (12,0.4) / 左 (0.6,6.9) / 右 (23.4,6.9) / 下 (12,13.4)
        var top = Path()
        top.move(to: CGPoint(x: 12, y: 0.4))
        top.addLine(to: CGPoint(x: 23.4, y: 6.9))
        top.addLine(to: CGPoint(x: 12, y: 13.4))
        top.addLine(to: CGPoint(x: 0.6, y: 6.9))
        top.closeSubpath()
        stroke(&ctx, top, WIPaint.ink, 1.8)

        // 下菱形:与上菱形重叠 2px,原版就是这个样子
        var bottom = Path()
        bottom.move(to: CGPoint(x: 12, y: 11.6))
        bottom.addLine(to: CGPoint(x: 23.4, y: 17.4))
        bottom.addLine(to: CGPoint(x: 12, y: 23.2))
        bottom.addLine(to: CGPoint(x: 0.6, y: 17.4))
        bottom.closeSubpath()
        stroke(&ctx, bottom, WIPaint.ink, 1.8)
    }

    /// 新建图层:圈中加号
    static func add(_ ctx: inout GraphicsContext) {
        var ring = Path()
        ring.addEllipse(in: CGRect(x: 3.6, y: 3.6, width: 16.8, height: 16.8))
        stroke(&ctx, ring, WIPaint.ink, 1.4)
        var plus = Path()
        plus.move(to: CGPoint(x: 8, y: 12))
        plus.addLine(to: CGPoint(x: 16, y: 12))
        plus.move(to: CGPoint(x: 12, y: 8))
        plus.addLine(to: CGPoint(x: 12, y: 16))
        stroke(&ctx, plus, WIPaint.ink, 1.4)
    }

    // MARK: 功能区 · 图像组

    /// 裁剪:原版的裁剪标记(左边竖线带短横档 + 圆角裁剪框 + 底部长横带短竖档)
    /// 原版实测:x 97..116 / y 110..129
    static func crop(_ ctx: inout GraphicsContext) {
        // 原版图标是 19×19,比 24 网格画出来的略大,这里整体放大并对齐
        ctx.translateBy(x: -1.3, y: 2.4)
        ctx.scaleBy(x: 1.06, y: 1.10)
        let g = WIPaint.iconGrey

        // 左边竖线 + 向左伸出的短横档
        var left = Path()
        left.move(to: CGPoint(x: 7.4, y: 2.0))
        left.addLine(to: CGPoint(x: 7.4, y: 17.6))
        left.move(to: CGPoint(x: 3.3, y: 13.4))
        left.addLine(to: CGPoint(x: 8.3, y: 13.4))
        stroke(&ctx, left, g, 1.6)

        // 裁剪框:上边 + 圆角 + 右边
        var frame = Path()
        frame.move(to: CGPoint(x: 9.6, y: 13.9))
        frame.addLine(to: CGPoint(x: 14.4, y: 13.9))
        frame.addQuadCurve(to: CGPoint(x: 16.6, y: 11.7), control: CGPoint(x: 16.0, y: 13.9))
        frame.addLine(to: CGPoint(x: 16.6, y: 5.1))
        stroke(&ctx, frame, g, 1.6)

        // 底部长横 + 向下伸出的短竖档
        var bottom = Path()
        bottom.move(to: CGPoint(x: 7.4, y: 2.3))
        bottom.addLine(to: CGPoint(x: 21.1, y: 2.3))
        bottom.move(to: CGPoint(x: 18.6, y: 0.4))
        bottom.addLine(to: CGPoint(x: 18.6, y: 4.2))
        stroke(&ctx, bottom, g, 1.6)
    }

    /// 旋转:黑色 C 形弧箭头(上)+ 右下角蓝色直角楔(下)
    /// 原版实测:弧 149..166 / 109..121,蓝楔 149..167 / 119..129
    static func rotate(_ ctx: inout GraphicsContext) {
        // 蓝色直角楔:直角在右下,斜边从左下到右上
        var tri = Path()
        tri.move(to: CGPoint(x: 21, y: 13))
        tri.addLine(to: CGPoint(x: 20, y: 22.4))
        tri.addLine(to: CGPoint(x: 3, y: 22.4))
        tri.closeSubpath()
        fill(&ctx, tri, WIPaint.accentInk)

        // 黑色 C 形弧:左端在下,绕过顶部往右上扬
        var arc = Path()
        arc.move(to: CGPoint(x: 5.6, y: 12.4))
        arc.addCurve(to: CGPoint(x: 12.6, y: 7.4),
                     control1: CGPoint(x: 2.4, y: 12.8), control2: CGPoint(x: 4.2, y: 8.6))
        arc.addCurve(to: CGPoint(x: 15.4, y: 4.4),
                     control1: CGPoint(x: 16.6, y: 6.9), control2: CGPoint(x: 16.6, y: 5.2))
        stroke(&ctx, arc, WIPaint.ink, 1.5)

        // 箭头:指向右上
        var head = Path()
        head.move(to: CGPoint(x: 17, y: 3.2))
        head.addLine(to: CGPoint(x: 11.8, y: 4.6))
        head.addLine(to: CGPoint(x: 15.4, y: 8.6))
        head.closeSubpath()
        fill(&ctx, head, WIPaint.ink)
    }

    /// 翻转:上白下蓝的楔形
    static func flip(_ ctx: inout GraphicsContext) {
        // 上半:黑色描边三角(顶点在左)
        var top = Path()
        top.move(to: CGPoint(x: 21.7, y: 3.3))
        top.addLine(to: CGPoint(x: 21.7, y: 13.3))
        top.addLine(to: CGPoint(x: 4.9, y: 11.9))
        top.closeSubpath()
        fill(&ctx, top, WIPaint.ribbon)
        stroke(&ctx, top, WIPaint.ink, 1.4)

        // 下半:蓝色实心三角(上下镜像)
        var bottom = Path()
        bottom.move(to: CGPoint(x: 5, y: 14))
        bottom.addLine(to: CGPoint(x: 22, y: 14))
        bottom.addLine(to: CGPoint(x: 22, y: 23.3))
        bottom.closeSubpath()
        fill(&ctx, bottom, WIPaint.accent)
    }


    /// 移除背景:45° 斜纹背景 + 蓝色人像(原版斜纹是 "/" 向,人像带留白挖空)
    /// 原版实测:墨迹 x 95..118 / y 161..178(图形只占 24 网格的中下部)
    static func removeBackground(_ ctx: inout GraphicsContext) {
        // 斜纹:原版被裁在 y 3..20 这条带子里,这里直接按带子画线段
        for k in 1..<7 {
            let gx = 2.7 + CGFloat(k) * 4.3
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 3))
            line.addLine(to: CGPoint(x: gx - 17, y: 20))
            stroke(&ctx, line, WIPaint.ink, 1.6)
        }

        // 人像:头(圆环)+ 肩(平顶拱形),先描一圈底色把斜纹挡在外面
        var head = Path()
        head.addEllipse(in: CGRect(x: 8, y: 6, width: 6, height: 6))

        var body = Path()
        body.move(to: CGPoint(x: 7, y: 20))
        body.addLine(to: CGPoint(x: 7, y: 14.6))
        body.addQuadCurve(to: CGPoint(x: 10, y: 13.8), control: CGPoint(x: 7, y: 13.8))
        body.addLine(to: CGPoint(x: 16, y: 13.8))
        body.addQuadCurve(to: CGPoint(x: 19, y: 14.6), control: CGPoint(x: 19, y: 13.8))
        body.addLine(to: CGPoint(x: 19, y: 20))

        stroke(&ctx, head, WIPaint.ribbon, 4.4)
        stroke(&ctx, body, WIPaint.ribbon, 4.4)
        stroke(&ctx, head, WIPaint.accentMid, 1.9)
        stroke(&ctx, body, WIPaint.accentMid, 1.9)
    }

    /// 调整大小:灰色虚线方框(四角实心)+ 左下蓝色图片框 + 右上蓝色箭头
    /// 原版实测:整体 220..252 / 131..158(比别的图标大,网格用 32)
    static func resize(_ ctx: inout GraphicsContext) {
        let grey = Color(white: 0.54)

        // 深灰虚线方框:四角实心圆角,四边虚线
        let lo: CGFloat = 0.6, hi: CGFloat = 31.4, arm: CGFloat = 7
        var edges = Path()
        edges.move(to: CGPoint(x: lo + arm, y: lo)); edges.addLine(to: CGPoint(x: hi - arm, y: lo))
        edges.move(to: CGPoint(x: hi, y: lo + arm)); edges.addLine(to: CGPoint(x: hi, y: hi - arm))
        edges.move(to: CGPoint(x: hi - arm, y: hi)); edges.addLine(to: CGPoint(x: lo + arm, y: hi))
        edges.move(to: CGPoint(x: lo, y: hi - arm)); edges.addLine(to: CGPoint(x: lo, y: lo + arm))
        dashed(&ctx, edges, grey, 1.7, [4.4, 3.2])

        var corners = Path()
        corners.move(to: CGPoint(x: lo + arm, y: lo))
        corners.addCurve(to: CGPoint(x: lo, y: lo + arm),
                         control1: CGPoint(x: lo + arm - 3, y: lo), control2: CGPoint(x: lo, y: lo + arm - 3))
        corners.move(to: CGPoint(x: hi - arm, y: lo))
        corners.addCurve(to: CGPoint(x: hi, y: lo + arm),
                         control1: CGPoint(x: hi - arm + 3, y: lo), control2: CGPoint(x: hi, y: lo + arm - 3))
        corners.move(to: CGPoint(x: hi, y: hi - arm))
        corners.addCurve(to: CGPoint(x: hi - arm, y: hi),
                         control1: CGPoint(x: hi, y: hi - arm + 3), control2: CGPoint(x: hi - arm + 3, y: hi))
        corners.move(to: CGPoint(x: lo + arm, y: hi))
        corners.addCurve(to: CGPoint(x: lo, y: hi - arm),
                         control1: CGPoint(x: lo + arm - 3, y: hi), control2: CGPoint(x: lo, y: hi - arm + 3))
        stroke(&ctx, corners, grey, 1.7)

        // 左下蓝色图片框
        var frame = Path()
        frame.addRoundedRect(in: CGRect(x: 0.6, y: 10, width: 17, height: 17),
                             cornerSize: CGSize(width: 3, height: 3))
        stroke(&ctx, frame, WIPaint.accentMid, 2.0)

        // 框里的太阳
        dot(&ctx, CGPoint(x: 12, y: 15), 1.6, WIPaint.accentMid)

        // 框里的山形
        var hill = Path()
        hill.move(to: CGPoint(x: 1.2, y: 26.6))
        hill.addCurve(to: CGPoint(x: 9.6, y: 19.4),
                      control1: CGPoint(x: 4.2, y: 22.4), control2: CGPoint(x: 6.6, y: 19.4))
        hill.addCurve(to: CGPoint(x: 14.4, y: 26.6),
                      control1: CGPoint(x: 11.6, y: 22.4), control2: CGPoint(x: 12.8, y: 24.8))
        stroke(&ctx, hill, WIPaint.accentMid, 1.8)

        // 右上蓝色箭头
        var shaft = Path()
        shaft.move(to: CGPoint(x: 19.4, y: 7.6))
        shaft.addLine(to: CGPoint(x: 28.2, y: 0.8))
        stroke(&ctx, shaft, WIPaint.accentMid, 2.3)

        var head = Path()
        head.move(to: CGPoint(x: 32.2, y: 0.2))
        head.addLine(to: CGPoint(x: 26.4, y: 0.9))
        head.addLine(to: CGPoint(x: 27.4, y: 5.6))
        head.closeSubpath()
        fill(&ctx, head, WIPaint.accentMid)
    }

    // MARK: 功能区 · 工具组

    /// 铅笔:黄杆 + 黑描边 + 黑笔尖(原版顶端是圆头,没有白色橡皮帽)
    /// 原版实测:x 295..314 / y 110..129
    static func pencil(_ ctx: inout GraphicsContext) {
        let yellow = Color(red: 0.933, green: 0.808, blue: 0.502)

        // 笔身:沿 45° 的一支圆头铅笔
        var body = Path()
        body.move(to: CGPoint(x: 3.2, y: 21.8))          // 笔尖
        body.addLine(to: CGPoint(x: 4.05, y: 18.13))     // 上棱起点
        body.addLine(to: CGPoint(x: 15.93, y: 6.25))     // 上棱到尾部
        body.addQuadCurve(to: CGPoint(x: 18.75, y: 9.07), // 圆头
                          control: CGPoint(x: 20.6, y: 4.4))
        body.addLine(to: CGPoint(x: 6.87, y: 20.95))     // 下棱回到笔尖
        body.closeSubpath()
        fill(&ctx, body, yellow)
        stroke(&ctx, body, WIPaint.ink, 1.25)

        // 石墨芯
        var lead = Path()
        lead.move(to: CGPoint(x: 3.2, y: 21.8))
        lead.addLine(to: CGPoint(x: 4.05, y: 18.13))
        lead.addLine(to: CGPoint(x: 6.87, y: 20.95))
        lead.closeSubpath()
        fill(&ctx, lead, WIPaint.ink)
    }

    /// 用颜色填充:斜置油漆桶(蓝口沿)+ 右侧提手 + 橙色颜料滴
    /// 原版实测:桶 345..360 / 110..126,滴 359..361 / 124..129
    static func fillCan(_ ctx: inout GraphicsContext) {
        // 桶身(白)
        var body = Path()
        body.move(to: CGPoint(x: 6.8, y: 2.6))
        body.addLine(to: CGPoint(x: 17.0, y: 6.6))
        body.addLine(to: CGPoint(x: 9.6, y: 19.6))
        body.addLine(to: CGPoint(x: 3.2, y: 13.2))
        body.closeSubpath()
        fill(&ctx, body, WIPaint.paper)
        stroke(&ctx, body, WIPaint.ink, 1.3)

        // 桶口的两道蓝边(沿左上棱)
        var rim = Path()
        rim.move(to: CGPoint(x: 6.8, y: 2.6))
        rim.addLine(to: CGPoint(x: 10.0, y: 4.0))
        rim.addLine(to: CGPoint(x: 5.2, y: 13.0))
        rim.addLine(to: CGPoint(x: 3.2, y: 13.2))
        rim.closeSubpath()
        fill(&ctx, rim, WIPaint.accentInk)

        var rim2 = Path()
        rim2.move(to: CGPoint(x: 12.0, y: 4.4))
        rim2.addLine(to: CGPoint(x: 14.4, y: 5.6))
        rim2.addLine(to: CGPoint(x: 9.4, y: 14.6))
        rim2.addLine(to: CGPoint(x: 7.4, y: 13.4))
        rim2.closeSubpath()
        fill(&ctx, rim2, WIPaint.accentInk)

        // 提手(右侧细弧)
        var handle = Path()
        handle.move(to: CGPoint(x: 17.4, y: 6.2))
        handle.addCurve(to: CGPoint(x: 15.6, y: 18.6),
                        control1: CGPoint(x: 21.6, y: 9.4), control2: CGPoint(x: 21.2, y: 15.2))
        stroke(&ctx, handle, Color(white: 0.45), 1.2)

        // 颜料滴
        var drop = Path()
        drop.move(to: CGPoint(x: 18.4, y: 14.4))
        drop.addCurve(to: CGPoint(x: 21.4, y: 20.6),
                      control1: CGPoint(x: 20.0, y: 17.0), control2: CGPoint(x: 21.4, y: 18.6))
        drop.addCurve(to: CGPoint(x: 15.4, y: 20.6),
                      control1: CGPoint(x: 21.4, y: 22.6), control2: CGPoint(x: 15.4, y: 22.6))
        drop.addCurve(to: CGPoint(x: 18.4, y: 14.4),
                      control1: CGPoint(x: 14.8, y: 18.8), control2: CGPoint(x: 17.0, y: 16.8))
        drop.closeSubpath()
        fill(&ctx, drop, Color(red: 0.93, green: 0.36, blue: 0.09))
        stroke(&ctx, drop, WIPaint.ink, 1.1)
    }

    /// 文本:细衬线 A(原版是发丝笔画,系统衬线体太粗,直接用矢量画)
    static func textA(_ ctx: inout GraphicsContext) {
        var a = Path()
        a.move(to: CGPoint(x: 9.8, y: 2.6))
        a.addLine(to: CGPoint(x: 2.6, y: 19.2))
        a.move(to: CGPoint(x: 9.8, y: 2.6))
        a.addLine(to: CGPoint(x: 17.0, y: 19.2))
        a.move(to: CGPoint(x: 5.4, y: 13.4))
        a.addLine(to: CGPoint(x: 14.2, y: 13.4))
        // 脚上的小衬线
        a.move(to: CGPoint(x: 1.0, y: 19.4)); a.addLine(to: CGPoint(x: 4.8, y: 19.4))
        a.move(to: CGPoint(x: 14.8, y: 19.4)); a.addLine(to: CGPoint(x: 18.6, y: 19.4))
        stroke(&ctx, a, WIPaint.ink, 1.25)
    }

    /// 橡皮擦:45° 粉红菱块 + 左下白色擦面 + 底部黑线
    /// 原版实测:粉块 298..315 / 160..176,底线 300..311 / 179
    static func eraser(_ ctx: inout GraphicsContext) {
        // 左下那条白色擦面(先画,压在粉块下面)
        var edge = Path()
        edge.move(to: CGPoint(x: 1.0, y: 13.8))
        edge.addLine(to: CGPoint(x: 8.8, y: 19.4))
        edge.addLine(to: CGPoint(x: 11.4, y: 16.4))
        edge.addLine(to: CGPoint(x: 3.6, y: 10.8))
        edge.closeSubpath()
        fill(&ctx, edge, Color(white: 0.94))
        stroke(&ctx, edge, WIPaint.ink, 1.2)

        // 粉红菱块
        var base = Path()
        base.move(to: CGPoint(x: 12.0, y: 3.6))
        base.addLine(to: CGPoint(x: 20.4, y: 10.6))
        base.addLine(to: CGPoint(x: 11.0, y: 19.2))
        base.addLine(to: CGPoint(x: 3.2, y: 12.8))
        base.closeSubpath()
        fill(&ctx, base, Color(red: 0.965, green: 0.682, blue: 0.675))
        stroke(&ctx, base, WIPaint.ink, 1.3)

        // 底部那条"擦拭面"横线
        var ground = Path()
        ground.move(to: CGPoint(x: 6, y: 23.2))
        ground.addLine(to: CGPoint(x: 15.4, y: 23.2))
        stroke(&ctx, ground, WIPaint.ink, 1.4)
    }

    /// 取色器:蓝色胶头 + 细玻璃管(黑描边)
    /// 原版实测:胶头 357..366 / 159..168,管尖 346 / 179
    static func eyedropper(_ ctx: inout GraphicsContext) {
        // 玻璃管(白,黑描边)
        var tube = Path()
        tube.move(to: CGPoint(x: 14.4, y: 10.8))
        tube.addLine(to: CGPoint(x: 17.6, y: 13.4))
        tube.addLine(to: CGPoint(x: 6.0, y: 23.4))
        tube.addLine(to: CGPoint(x: 3.8, y: 21.0))
        tube.closeSubpath()
        fill(&ctx, tube, WIPaint.paper)
        stroke(&ctx, tube, WIPaint.ink, 1.2)

        // 管里的蓝液(靠胶头那一段)
        var liquid = Path()
        liquid.move(to: CGPoint(x: 15.2, y: 9.6))
        liquid.addLine(to: CGPoint(x: 17.8, y: 11.8))
        liquid.addLine(to: CGPoint(x: 13.0, y: 14.4))
        liquid.addLine(to: CGPoint(x: 10.8, y: 12.2))
        liquid.closeSubpath()
        fill(&ctx, liquid, WIPaint.accentInk)

        // 胶头
        dot(&ctx, CGPoint(x: 19.2, y: 6.6), 4.6, WIPaint.accentInk)
    }

    /// 放大镜:黑圈 + 蓝加号 + 右下把手
    static func magnifier(_ ctx: inout GraphicsContext) {
        var ring = Path()
        ring.addEllipse(in: CGRect(x: 4, y: 3.5, width: 12, height: 12))
        stroke(&ctx, ring, WIPaint.ink, 1.4)

        var handle = Path()
        handle.move(to: CGPoint(x: 14.4, y: 15.4))
        handle.addLine(to: CGPoint(x: 20.8, y: 20.6))
        stroke(&ctx, handle, WIPaint.ink, 1.7)

        var plus = Path()
        plus.move(to: CGPoint(x: 6.8, y: 9.5))
        plus.addLine(to: CGPoint(x: 13.4, y: 9.5))
        plus.move(to: CGPoint(x: 10.1, y: 6.4))
        plus.addLine(to: CGPoint(x: 10.1, y: 12.6))
        stroke(&ctx, plus, WIPaint.accentMid, 1.7)
    }

    /// 画笔:上方扁金属箍 + 下方尖笔毛(笔毛下半截蘸墨)
    /// 坐标全部按 Canvas 的 y 向下。原版实测:箍 467..482 / 121.8..125.7,笔尖 474.6 / 146.1
    static func brush(_ ctx: inout GraphicsContext) {
        let ink = WIPaint.ink
        let grey = Color(red: 0.50, green: 0.50, blue: 0.51)

        // 笔毛轮廓:上宽下尖
        var bristles = Path()
        bristles.move(to: CGPoint(x: 6.4, y: 5.3))
        bristles.addLine(to: CGPoint(x: 18.9, y: 5.3))
        bristles.addCurve(to: CGPoint(x: 18.7, y: 15.5),
                         control1: CGPoint(x: 19.0, y: 9.4), control2: CGPoint(x: 18.9, y: 13.4))
        bristles.addCurve(to: CGPoint(x: 12.6, y: 24.1),
                         control1: CGPoint(x: 18.5, y: 19.4), control2: CGPoint(x: 14.8, y: 22.6))
        bristles.addCurve(to: CGPoint(x: 6.4, y: 15.5),
                         control1: CGPoint(x: 10.4, y: 22.6), control2: CGPoint(x: 6.6, y: 19.4))
        bristles.addCurve(to: CGPoint(x: 6.4, y: 5.3),
                         control1: CGPoint(x: 6.0, y: 13.4), control2: CGPoint(x: 6.0, y: 9.4))
        bristles.closeSubpath()
        fill(&ctx, bristles, WIPaint.paper)

        // 蘸墨:笔毛下半截
        var paint = Path()
        paint.move(to: CGPoint(x: 6.9, y: 15.5))
        paint.addLine(to: CGPoint(x: 18.1, y: 15.5))
        paint.addCurve(to: CGPoint(x: 12.6, y: 23.3),
                       control1: CGPoint(x: 17.8, y: 19.6), control2: CGPoint(x: 14.5, y: 22.2))
        paint.addCurve(to: CGPoint(x: 6.9, y: 15.5),
                       control1: CGPoint(x: 10.7, y: 22.2), control2: CGPoint(x: 7.4, y: 19.6))
        paint.closeSubpath()
        fill(&ctx, paint, grey)

        stroke(&ctx, bristles, ink, 1.4)

        // 笔毛缝隙(两滴短竖线)
        var drips = Path()
        drips.move(to: CGPoint(x: 9.6, y: 6.3))
        drips.addLine(to: CGPoint(x: 9.6, y: 11.2))
        drips.move(to: CGPoint(x: 13.3, y: 6.3))
        drips.addLine(to: CGPoint(x: 13.3, y: 9.9))
        stroke(&ctx, drips, ink, 1.4)

        // 金属箍:倒 U 形(原版是"⊓",不是闭合矩形)
        var ferrule = Path()
        ferrule.move(to: CGPoint(x: 5.5, y: 4.8))
        ferrule.addLine(to: CGPoint(x: 5.5, y: 1.7))
        ferrule.addLine(to: CGPoint(x: 19.4, y: 1.7))
        ferrule.addLine(to: CGPoint(x: 19.4, y: 4.8))
        stroke(&ctx, ferrule, ink, 1.4)
    }

    // MARK: 状态栏

    /// 光标:空心箭头
    static func cursor(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 2))
        p.addLine(to: CGPoint(x: 4, y: 19.4))
        p.addLine(to: CGPoint(x: 8.4, y: 15.1))
        p.addLine(to: CGPoint(x: 11.3, y: 21.8))
        p.addLine(to: CGPoint(x: 14, y: 20.7))
        p.addLine(to: CGPoint(x: 11.1, y: 14.3))
        p.addLine(to: CGPoint(x: 16.9, y: 13.9))
        p.closeSubpath()
        fill(&ctx, p, WIPaint.paper)
        stroke(&ctx, p, WIPaint.ink, 1.3)
    }

    /// 适应窗口:四角括号套圆
    static func fit(_ ctx: inout GraphicsContext) {
        var brackets = Path()
        brackets.move(to: CGPoint(x: 2.6, y: 8.4))
        brackets.addLine(to: CGPoint(x: 2.6, y: 2.6))
        brackets.addLine(to: CGPoint(x: 8.4, y: 2.6))
        brackets.move(to: CGPoint(x: 15.6, y: 2.6))
        brackets.addLine(to: CGPoint(x: 21.4, y: 2.6))
        brackets.addLine(to: CGPoint(x: 21.4, y: 8.4))
        brackets.move(to: CGPoint(x: 21.4, y: 15.6))
        brackets.addLine(to: CGPoint(x: 21.4, y: 21.4))
        brackets.addLine(to: CGPoint(x: 15.6, y: 21.4))
        brackets.move(to: CGPoint(x: 8.4, y: 21.4))
        brackets.addLine(to: CGPoint(x: 2.6, y: 21.4))
        brackets.addLine(to: CGPoint(x: 2.6, y: 15.6))
        stroke(&ctx, brackets, WIPaint.inkSoft, 1.4)

        var circle = Path()
        circle.addEllipse(in: CGRect(x: 8.2, y: 8.2, width: 7.6, height: 7.6))
        stroke(&ctx, circle, WIPaint.inkSoft, 1.4)
    }

    /// 缩放放大镜(带 + / −)
    static func magnifierSign(_ ctx: inout GraphicsContext, minus: Bool) {
        var ring = Path()
        ring.addEllipse(in: CGRect(x: 2.4, y: 2.4, width: 13, height: 13))
        stroke(&ctx, ring, WIPaint.ink, 1.4)
        var handle = Path()
        handle.move(to: CGPoint(x: 14.2, y: 14.2))
        handle.addLine(to: CGPoint(x: 21, y: 21))
        stroke(&ctx, handle, WIPaint.ink, 1.6)
        var sign = Path()
        sign.move(to: CGPoint(x: 6.2, y: 8.9))
        sign.addLine(to: CGPoint(x: 11.6, y: 8.9))
        if !minus {
            sign.move(to: CGPoint(x: 8.9, y: 6.2))
            sign.addLine(to: CGPoint(x: 8.9, y: 11.6))
        }
        stroke(&ctx, sign, WIPaint.ink, 1.5)
    }

    /// 下拉箭头
    static func chevronDown(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 4.4, y: 9.2))
        p.addLine(to: CGPoint(x: 12, y: 16.4))
        p.addLine(to: CGPoint(x: 19.6, y: 9.2))
        stroke(&ctx, p, WIPaint.inkSoft, 1.6)
    }

    /// 选择:虚线方框(状态栏用的小号)
    static func dashedSelect(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.addRect(CGRect(x: 3, y: 3, width: 18, height: 18))
        dashed(&ctx, p, WIPaint.ink, 1.5, [3.4, 2.6])
    }

    /// 选择(功能区):四角实心角标 + 四边虚线
    /// 原版实测:方框 22..51 / 120..149,四角是实心 L 形角标
    static func selectBracket(_ ctx: inout GraphicsContext) {
        let lo: CGFloat = 1.0, hi: CGFloat = 23.0, arm: CGFloat = 5.5

        var corners = Path()
        corners.move(to: CGPoint(x: lo, y: lo + arm))
        corners.addLine(to: CGPoint(x: lo, y: lo))
        corners.addLine(to: CGPoint(x: lo + arm, y: lo))

        corners.move(to: CGPoint(x: hi - arm, y: lo))
        corners.addLine(to: CGPoint(x: hi, y: lo))
        corners.addLine(to: CGPoint(x: hi, y: lo + arm))

        corners.move(to: CGPoint(x: hi, y: hi - arm))
        corners.addLine(to: CGPoint(x: hi, y: hi))
        corners.addLine(to: CGPoint(x: hi - arm, y: hi))

        corners.move(to: CGPoint(x: lo + arm, y: hi))
        corners.addLine(to: CGPoint(x: lo, y: hi))
        corners.addLine(to: CGPoint(x: lo, y: hi - arm))
        stroke(&ctx, corners, WIPaint.ink, 1.5)

        var edges = Path()
        edges.move(to: CGPoint(x: lo + arm, y: lo)); edges.addLine(to: CGPoint(x: hi - arm, y: lo))
        edges.move(to: CGPoint(x: hi, y: lo + arm)); edges.addLine(to: CGPoint(x: hi, y: hi - arm))
        edges.move(to: CGPoint(x: hi - arm, y: hi)); edges.addLine(to: CGPoint(x: lo + arm, y: hi))
        edges.move(to: CGPoint(x: lo, y: hi - arm)); edges.addLine(to: CGPoint(x: lo, y: lo + arm))
        dashed(&ctx, edges, WIPaint.ink, 1.5, [2.8, 2.4])
    }

    /// 笔迹:三道手写波浪(左侧浮动滑块顶部那个图标)
    /// 原版的「笔刷纹理」图标是 **4 条平行的斜线**(Windows 的笔刷预览),
    /// 不是波浪线。深灰,画在 24 网格里约占 x 3..21 / y 3..19。
    static func brushStroke(_ ctx: inout GraphicsContext) {
        for i in 0..<4 {
            let y = 5.4 + CGFloat(i) * 3.4
            var p = Path()
            p.move(to: CGPoint(x: 7.0, y: y + 1.5))
            p.addLine(to: CGPoint(x: 15.0, y: y - 1.5))
            stroke(&ctx, p, WIPaint.inkSoft, 1.6)
        }
    }

    /// 图像尺寸:四边矩形 + 四角抓手(原版是带角手柄的变换框)
    /// 原版实测:矩形 348..368 / 954..967,四角各有小抓手
    static func imageFrame(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.addRect(CGRect(x: 1.5, y: 2.5, width: 21, height: 13))
        stroke(&ctx, p, WIPaint.inkSoft, 1.3)

        // 四角抓手
        let handles: [CGPoint] = [
            CGPoint(x: 1.5, y: 2.5), CGPoint(x: 22.5, y: 2.5),
            CGPoint(x: 1.5, y: 15.5), CGPoint(x: 22.5, y: 15.5)
        ]
        for h in handles {
            var s = Path()
            s.addRect(CGRect(x: h.x - 2.2, y: h.y - 2.2, width: 4.4, height: 4.4))
            fill(&ctx, s, WIPaint.inkSoft)
        }
    }

    /// 不透明度图标:半满的颜料滴(原版左侧浮动滑块右上那个)
    static func drop(_ ctx: inout GraphicsContext) {
        // 下半截(实心深灰)
        var lower = Path()
        lower.move(to: CGPoint(x: 3.4, y: 14.6))
        lower.addCurve(to: CGPoint(x: 12, y: 23.2),
                       control1: CGPoint(x: 3.4, y: 19.8), control2: CGPoint(x: 7.2, y: 23.2))
        lower.addCurve(to: CGPoint(x: 20.6, y: 14.6),
                       control1: CGPoint(x: 16.8, y: 23.2), control2: CGPoint(x: 20.6, y: 19.8))
        lower.closeSubpath()
        let grey = Color(red: 0.36, green: 0.36, blue: 0.37)
        fill(&ctx, lower, grey)

        // 整滴轮廓:先铺纸白,再描边
        var full = Path()
        full.move(to: CGPoint(x: 12, y: 1.2))
        full.addCurve(to: CGPoint(x: 20.6, y: 14.6),
                      control1: CGPoint(x: 15.5, y: 6.0), control2: CGPoint(x: 20.6, y: 9.6))
        full.addCurve(to: CGPoint(x: 12, y: 23.2),
                      control1: CGPoint(x: 20.6, y: 19.8), control2: CGPoint(x: 16.8, y: 23.2))
        full.addCurve(to: CGPoint(x: 3.4, y: 14.6),
                      control1: CGPoint(x: 7.2, y: 23.2), control2: CGPoint(x: 3.4, y: 19.8))
        full.addCurve(to: CGPoint(x: 12, y: 1.2),
                      control1: CGPoint(x: 3.4, y: 9.6), control2: CGPoint(x: 8.5, y: 6.0))
        full.closeSubpath()
        fill(&ctx, full, WIPaint.paper)
        stroke(&ctx, full, WIPaint.ink, 1.4)

        // 再把下半截盖回去
        fill(&ctx, lower, grey)
    }

    // MARK: 形状库

    static func renderShape(_ icon: WIShapeIcon, ctx: inout GraphicsContext) {
        let c = WIPaint.ink
        switch icon {
        case .line:
            var p = Path()
            p.move(to: CGPoint(x: 4, y: 4))
            p.addLine(to: CGPoint(x: 20, y: 20))
            stroke(&ctx, p, c, 1.7)

        case .curve:
            var p = Path()
            p.move(to: CGPoint(x: 3.4, y: 18))
            p.addCurve(to: CGPoint(x: 11, y: 13),
                       control1: CGPoint(x: 6, y: 5), control2: CGPoint(x: 8.6, y: 6))
            p.addCurve(to: CGPoint(x: 20.6, y: 6),
                       control1: CGPoint(x: 13.6, y: 20), control2: CGPoint(x: 17.4, y: 19))
            stroke(&ctx, p, c, 1.7)

        case .oval:
            var p = Path()
            p.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 15, height: 15))
            stroke(&ctx, p, c, 1.7)

        case .square:
            var p = Path()
            p.addRect(CGRect(x: 4.8, y: 4.8, width: 14.4, height: 14.4))
            stroke(&ctx, p, c, 1.7)

        case .roundedSquare:
            var p = Path()
            p.addRoundedRect(in: CGRect(x: 4.8, y: 4.8, width: 14.4, height: 14.4), cornerSize: CGSize(width: 4.5, height: 4.5))
            stroke(&ctx, p, c, 1.7)

        case .polygon:
            // 原版是一个带凹口的六边形(闪电状),顶点按截图量取
            var p = Path()
            p.move(to: CGPoint(x: 9.5, y: 22.6))
            p.addLine(to: CGPoint(x: 21.0, y: 22.6))
            p.addLine(to: CGPoint(x: 14.3, y: 12.4))
            p.addLine(to: CGPoint(x: 23.2, y: 12.4))
            p.addLine(to: CGPoint(x: 23.2, y: 3.4))
            p.addLine(to: CGPoint(x: 0.6, y: 3.4))
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .triangle:
            poly(&ctx, [CGPoint(x: 12, y: 4), CGPoint(x: 20.4, y: 19.6), CGPoint(x: 3.6, y: 19.6)], WIPaint.paper)
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 20.4, y: 19.6))
            p.addLine(to: CGPoint(x: 3.6, y: 19.6))
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .rightTriangle:
            poly(&ctx, [CGPoint(x: 4.4, y: 4.4), CGPoint(x: 4.4, y: 19.6), CGPoint(x: 19.6, y: 19.6)], WIPaint.paper)
            var p = Path()
            p.move(to: CGPoint(x: 4.4, y: 4.4))
            p.addLine(to: CGPoint(x: 4.4, y: 19.6))
            p.addLine(to: CGPoint(x: 19.6, y: 19.6))
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .diamond:
            poly(&ctx, [CGPoint(x: 12, y: 3.4), CGPoint(x: 20.6, y: 12), CGPoint(x: 12, y: 20.6), CGPoint(x: 3.4, y: 12)], WIPaint.paper)
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 3.4))
            p.addLine(to: CGPoint(x: 20.6, y: 12))
            p.addLine(to: CGPoint(x: 12, y: 20.6))
            p.addLine(to: CGPoint(x: 3.4, y: 12))
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .pentagon:
            let pts = regularPolygon(sides: 5, rotation: -90)
            poly(&ctx, pts, WIPaint.paper)
            var p = Path()
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .hexagon:
            let pts = regularPolygon(sides: 6, rotation: 0)
            poly(&ctx, pts, WIPaint.paper)
            var p = Path()
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            stroke(&ctx, p, c, 1.7)

        case .arrowRight:
            arrow(&ctx, .right)
        case .arrowLeft:
            arrow(&ctx, .left)
        case .arrowUp:
            arrow(&ctx, .up)
        case .arrowDown:
            arrow(&ctx, .down)

        case .fourStar:
            star(&ctx, points: 4, inner: 0.32)
        case .fiveStar:
            star(&ctx, points: 5, inner: 0.45)
        case .sixStar:
            star(&ctx, points: 6, inner: 0.58)

        case .calloutRect:
            var p = Path()
            p.addRoundedRect(in: CGRect(x: 3.6, y: 4.2, width: 16.8, height: 12.4), cornerSize: CGSize(width: 2.4, height: 2.4))
            stroke(&ctx, p, c, 1.6)
            var tail = Path()
            tail.move(to: CGPoint(x: 8.4, y: 16.4))
            tail.addLine(to: CGPoint(x: 7.4, y: 20.4))
            tail.addLine(to: CGPoint(x: 12, y: 16.4))
            stroke(&ctx, tail, c, 1.6)

        case .calloutOval:
            var p = Path()
            p.addEllipse(in: CGRect(x: 3.2, y: 4.2, width: 17.6, height: 12.4))
            stroke(&ctx, p, c, 1.6)
            var tail = Path()
            tail.move(to: CGPoint(x: 8.4, y: 16.2))
            tail.addLine(to: CGPoint(x: 7.4, y: 20.4))
            tail.addLine(to: CGPoint(x: 12, y: 16.2))
            stroke(&ctx, tail, c, 1.6)

        case .cloudCallout:
            var p = Path()
            p.addEllipse(in: CGRect(x: 3.2, y: 4.2, width: 17.6, height: 12.4))
            stroke(&ctx, p, c, 1.6)
            var tail = Path()
            tail.move(to: CGPoint(x: 8.4, y: 16.2))
            tail.addLine(to: CGPoint(x: 7.4, y: 20.4))
            tail.addLine(to: CGPoint(x: 12, y: 16.2))
            stroke(&ctx, tail, c, 1.6)
        }
    }

    private static func regularPolygon(sides: Int, rotation: Double) -> [CGPoint] {
        let radius: CGFloat = 8.6
        return (0..<sides).map { i in
            let a = (rotation + Double(i) * 360.0 / Double(sides)) * .pi / 180
            return CGPoint(x: 12 + radius * CGFloat(cos(a)), y: 12 + radius * CGFloat(sin(a)))
        }
    }

    private static func arrow(_ ctx: inout GraphicsContext, _ dir: ArrowDir) {
        var p = Path()
        switch dir {
        case .up:
            p.move(to: CGPoint(x: 8.4, y: 20.4))
            p.addLine(to: CGPoint(x: 8.4, y: 10.4))
            p.addLine(to: CGPoint(x: 4.4, y: 10.4))
            p.addLine(to: CGPoint(x: 12, y: 3.4))
            p.addLine(to: CGPoint(x: 19.6, y: 10.4))
            p.addLine(to: CGPoint(x: 15.6, y: 10.4))
            p.addLine(to: CGPoint(x: 15.6, y: 20.4))
        case .down:
            p.move(to: CGPoint(x: 8.4, y: 3.6))
            p.addLine(to: CGPoint(x: 8.4, y: 13.6))
            p.addLine(to: CGPoint(x: 4.4, y: 13.6))
            p.addLine(to: CGPoint(x: 12, y: 20.6))
            p.addLine(to: CGPoint(x: 19.6, y: 13.6))
            p.addLine(to: CGPoint(x: 15.6, y: 13.6))
            p.addLine(to: CGPoint(x: 15.6, y: 3.6))
        case .right:
            p.move(to: CGPoint(x: 3.6, y: 8.4))
            p.addLine(to: CGPoint(x: 13.6, y: 8.4))
            p.addLine(to: CGPoint(x: 13.6, y: 4.4))
            p.addLine(to: CGPoint(x: 20.6, y: 12))
            p.addLine(to: CGPoint(x: 13.6, y: 19.6))
            p.addLine(to: CGPoint(x: 13.6, y: 15.6))
            p.addLine(to: CGPoint(x: 3.6, y: 15.6))
        case .left:
            p.move(to: CGPoint(x: 20.4, y: 8.4))
            p.addLine(to: CGPoint(x: 10.4, y: 8.4))
            p.addLine(to: CGPoint(x: 10.4, y: 4.4))
            p.addLine(to: CGPoint(x: 3.4, y: 12))
            p.addLine(to: CGPoint(x: 10.4, y: 19.6))
            p.addLine(to: CGPoint(x: 10.4, y: 15.6))
            p.addLine(to: CGPoint(x: 20.4, y: 15.6))
        }
        p.closeSubpath()
        fill(&ctx, p, WIPaint.paper)
        stroke(&ctx, p, WIPaint.ink, 1.7)
    }

    private static func star(_ ctx: inout GraphicsContext, points: Int, inner: CGFloat) {
        let outer: CGFloat = 9.2
        let innerR = outer * inner
        var pts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let a = (Double(i) * 180.0 / Double(points) - 90) * .pi / 180
            let r = i % 2 == 0 ? outer : innerR
            pts.append(CGPoint(x: 12 + r * CGFloat(cos(a)), y: 12 + r * CGFloat(sin(a))))
        }
        poly(&ctx, pts, WIPaint.paper)
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        stroke(&ctx, p, WIPaint.ink, 1.7)
    }
}
