import CoreGraphics
import CoreText
import Foundation

// MARK: - 笔刷

enum BrushRenderer {
    /// 画一条折线笔迹。使用中点二次贝塞尔平滑,避免硬折角。
    static func stroke(context: CGContext, points: [CGPoint], settings: BrushSettings) {
        guard !points.isEmpty else { return }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(settings.size, 0.5))

        if settings.isEraser {
            context.setBlendMode(.destinationOut)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        } else {
            context.setBlendMode(.normal)
            context.setStrokeColor(settings.color.cgColor)
            context.setAlpha(settings.opacity)
        }

        if points.count == 1 {
            let r = settings.size / 2
            context.fillEllipse(in: CGRect(x: points[0].x - r, y: points[0].y - r, width: settings.size, height: settings.size))
        } else {
            context.beginPath()
            context.move(to: points[0])
            if points.count == 2 {
                context.addLine(to: points[1])
            } else {
                for i in 1..<(points.count - 1) {
                    let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                                      y: (points[i].y + points[i + 1].y) / 2)
                    context.addQuadCurve(to: mid, control: points[i])
                }
                context.addLine(to: points[points.count - 1])
            }
            context.strokePath()
        }
        context.restoreGState()
    }
}

// MARK: - 形状

enum ShapeRenderer {
    /// 形状几何路径。`rect` 为文档坐标(y 向上)。
    static func path(for kind: ShapeKind, in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY
        let midX = rect.midX, midY = rect.midY
        let w = rect.width, h = rect.height

        switch kind {
        case .line:
            p.move(to: CGPoint(x: minX, y: maxY))
            p.addLine(to: CGPoint(x: maxX, y: minY))

        case .curve:
            p.move(to: CGPoint(x: minX, y: minY))
            p.addCurve(to: CGPoint(x: maxX, y: maxY),
                       control1: CGPoint(x: minX + w * 0.42, y: maxY + h * 0.25),
                       control2: CGPoint(x: maxX - w * 0.42, y: minY - h * 0.25))

        case .ellipse:
            p.addEllipse(in: rect)

        case .rectangle:
            p.addRect(rect)

        case .roundedRectangle:
            let r = min(w, h) * 0.15
            p.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)

        case .polygon:
            addPolygon([
                CGPoint(x: minX, y: minY),
                CGPoint(x: minX + w * 0.30, y: maxY),
                CGPoint(x: maxX, y: maxY - h * 0.22),
                CGPoint(x: maxX - w * 0.18, y: minY),
            ], to: p)

        case .triangle:
            p.move(to: CGPoint(x: midX, y: maxY))
            p.addLine(to: CGPoint(x: maxX, y: minY))
            p.addLine(to: CGPoint(x: minX, y: minY))
            p.closeSubpath()

        case .rightTriangle:
            p.move(to: CGPoint(x: minX, y: minY))
            p.addLine(to: CGPoint(x: maxX, y: minY))
            p.addLine(to: CGPoint(x: minX, y: maxY))
            p.closeSubpath()

        case .diamond:
            p.move(to: CGPoint(x: midX, y: maxY))
            p.addLine(to: CGPoint(x: maxX, y: midY))
            p.addLine(to: CGPoint(x: midX, y: minY))
            p.addLine(to: CGPoint(x: minX, y: midY))
            p.closeSubpath()

        case .pentagon:
            let pts = regularPolygonPoints(in: rect, sides: 5, rotation: .pi / 2)
            addPolygon(pts, to: p)

        case .hexagon:
            let pts = regularPolygonPoints(in: rect, sides: 6, rotation: 0)
            addPolygon(pts, to: p)

        case .arrowRight, .arrowLeft, .arrowUp, .arrowDown:
            let pts = arrowPoints(for: kind, in: rect)
            addPolygon(pts, to: p)

        case .fourPointStar:
            addPolygon(starPoints(in: rect, tips: 4, inner: 0.30), to: p)

        case .fivePointStar:
            addPolygon(starPoints(in: rect, tips: 5, inner: 0.382), to: p)

        case .sixPointStar:
            addPolygon(starPoints(in: rect, tips: 6, inner: 0.58), to: p)

        case .calloutRectangle:
            addCallout(in: rect, to: p, rounded: true)

        case .calloutOval:
            addCallout(in: rect, to: p, rounded: false)

        case .cloudCallout:
            addCloudCallout(in: rect, to: p)

        case .heart:
            addHeart(in: rect, to: p)

        case .lightning:
            addPolygon(lightningPoints(in: rect), to: p)
        }
        return p
    }

    /// 按填充/轮廓样式绘制形状
    static func draw(kind: ShapeKind, in rect: CGRect, context: CGContext,
                      fill: CGColor?, stroke: CGColor?, lineWidth: CGFloat) {
        let p = path(for: kind, in: rect)
        context.saveGState()
        context.setLineJoin(.round)
        context.setLineCap(.round)
        if let fill {
            context.setFillColor(fill)
            context.addPath(p)
            context.fillPath()
        }
        if let stroke {
            context.setStrokeColor(stroke)
            context.setLineWidth(max(lineWidth, 0.5))
            context.addPath(p)
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: 私有

    private static func addPolygon(_ pts: [CGPoint], to path: CGMutablePath) {
        guard let first = pts.first else { return }
        path.move(to: first)
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
    }

    /// 正多边形顶点。rotation 为首顶点相对 x 轴的角度。
    private static func regularPolygonPoints(in rect: CGRect, sides: Int, rotation: Double) -> [CGPoint] {
        let rx = rect.width / 2
        let ry = rect.height / 2
        return (0..<sides).map { i in
            let a = rotation + Double(i) * (2 * Double.pi / Double(sides))
            return CGPoint(x: rect.midX + rx * CGFloat(cos(a)),
                           y: rect.midY + ry * CGFloat(sin(a)))
        }
    }

    /// 箭头多边形。用"方向向量 + 垂直向量"统一表达各种朝向。
    private static func arrowPoints(for kind: ShapeKind, in rect: CGRect) -> [CGPoint] {
        let dir: CGPoint
        let tail: CGPoint
        let length: CGFloat
        let headLength: CGFloat
        let headSpan: CGFloat
        let shaft: CGFloat

        switch kind {
        case .arrowRight:
            dir = CGPoint(x: 1, y: 0); tail = CGPoint(x: rect.minX, y: rect.midY)
            length = rect.width; headLength = rect.width * 0.42; headSpan = rect.height; shaft = rect.height * 0.32
        case .arrowLeft:
            dir = CGPoint(x: -1, y: 0); tail = CGPoint(x: rect.maxX, y: rect.midY)
            length = rect.width; headLength = rect.width * 0.42; headSpan = rect.height; shaft = rect.height * 0.32
        case .arrowUp:
            dir = CGPoint(x: 0, y: 1); tail = CGPoint(x: rect.midX, y: rect.minY)
            length = rect.height; headLength = rect.height * 0.42; headSpan = rect.width; shaft = rect.width * 0.32
        case .arrowDown:
            dir = CGPoint(x: 0, y: -1); tail = CGPoint(x: rect.midX, y: rect.maxY)
            length = rect.height; headLength = rect.height * 0.42; headSpan = rect.width; shaft = rect.width * 0.32
        default:
            return []
        }

        let perp = CGPoint(x: -dir.y, y: dir.x)
        let base = CGPoint(x: tail.x + dir.x * (length - headLength), y: tail.y + dir.y * (length - headLength))
        let tip = CGPoint(x: tail.x + dir.x * length, y: tail.y + dir.y * length)

        func pt(_ origin: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + dir.x * along + perp.x * across,
                    y: origin.y + dir.y * along + perp.y * across)
        }

        return [
            pt(tail, 0, -shaft / 2),
            pt(base, 0, -shaft / 2),
            pt(base, 0, -headSpan / 2),
            tip,
            pt(base, 0, headSpan / 2),
            pt(base, 0, shaft / 2),
            pt(tail, 0, shaft / 2),
        ]
    }

    /// N 角星。inner 为内/外半径比。
    private static func starPoints(in rect: CGRect, tips: Int, inner: CGFloat) -> [CGPoint] {
        let rx = rect.width / 2
        let ry = rect.height / 2
        return (0..<(tips * 2)).map { i in
            let a = .pi / 2 + Double(i) * .pi / Double(tips)
            let scale = i % 2 == 0 ? 1.0 : inner
            return CGPoint(x: rect.midX + rx * CGFloat(cos(a)) * CGFloat(scale),
                           y: rect.midY + ry * CGFloat(sin(a)) * CGFloat(scale))
        }
    }

    /// 标注框(圆角矩形或椭圆)+ 左下角一个小尾巴
    private static func addCallout(in rect: CGRect, to path: CGMutablePath, rounded: Bool) {
        let body = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.22,
                          width: rect.width, height: rect.height * 0.78)
        if rounded {
            let r = min(body.width, body.height) * 0.14
            path.addRoundedRect(in: body, cornerWidth: r, cornerHeight: r)
        } else {
            path.addEllipse(in: body)
        }
        // 尾巴
        let tailRoot = CGPoint(x: rect.minX + rect.width * 0.28, y: body.minY)
        let tailTip = CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY)
        path.move(to: tailRoot)
        path.addLine(to: tailTip)
        path.addLine(to: CGPoint(x: tailRoot.x + rect.width * 0.14, y: body.minY))
        path.closeSubpath()
    }

    /// 云形标注:椭圆身体 + 底部一串圆弧
    private static func addCloudCallout(in rect: CGRect, to path: CGMutablePath) {
        let body = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.28,
                          width: rect.width, height: rect.height * 0.72)
        path.addEllipse(in: body)
        // 底部三个凸起
        let bumps: [CGFloat] = [0.22, 0.5, 0.78]
        for t in bumps {
            let cx = rect.minX + rect.width * t
            let r = rect.width * 0.13
            path.addArc(center: CGPoint(x: cx, y: body.minY + r * 0.4),
                        radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        }
    }

    /// 心形(两段三次贝塞尔)
    private static func addHeart(in rect: CGRect, to path: CGMutablePath) {
        let w = rect.width, h = rect.height
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: midX + w * 0.34, y: rect.minY + h * 0.30),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.36))
        path.addCurve(to: CGPoint(x: midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.midY + h * 0.26),
                      control2: CGPoint(x: midX + w * 0.30, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: midX - w * 0.30, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.midY + h * 0.26))
        path.addCurve(to: CGPoint(x: midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.36),
                      control2: CGPoint(x: midX - w * 0.34, y: rect.minY + h * 0.30))
        path.closeSubpath()
    }

    /// 闪电
    private static func lightningPoints(in rect: CGRect) -> [CGPoint] {
        let f: [(CGFloat, CGFloat)] = [
            (0.60, 0.00), (0.26, 0.54), (0.47, 0.54),
            (0.36, 1.00), (0.74, 0.44), (0.51, 0.44),
        ]
        return f.map { (fx, fy) in
            CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
        }
    }

    /// 十字
    private static func plusPoints(in rect: CGRect) -> [CGPoint] {
        let f: [(CGFloat, CGFloat)] = [
            (0.34, 0.00), (0.66, 0.00), (0.66, 0.34), (1.00, 0.34),
            (1.00, 0.66), (0.66, 0.66), (0.66, 1.00), (0.34, 1.00),
            (0.34, 0.66), (0.00, 0.66), (0.00, 0.34), (0.34, 0.34),
        ]
        return f.map { (fx, fy) in
            CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
        }
    }
}

extension CGPoint {
    var normalized: CGPoint {
        let len = (x * x + y * y).squareRoot()
        guard len > 0 else { return .zero }
        return CGPoint(x: x / len, y: y / len)
    }
}

// MARK: - 油漆桶

enum FloodFill {
    /// 扫描线洪水填充。
    ///
    /// 实现要点:
    /// 1. 把目标图层画进一块**自己拥有**的像素缓冲区,用 `premultipliedLast | byteOrder32Big`
    ///    创建,内存字节序确定为 R,G,B,A,读像素不会猜错布局
    /// 2. 扫描线算法产出横向 span 列表
    /// 3. 用 span 拼成路径 → 裁剪 → 填色。这样只改填充区域,
    ///    不会把整层的透明区域也涂成不透明
    static func fill(context: CGContext, seed: CGPoint, color: RGBA,
                     pixelSize: CGSize, tolerance: Int = 12) -> Bool {
        let w = Int(pixelSize.width.rounded())
        let h = Int(pixelSize.height.rounded())
        guard w > 0, h > 0 else { return false }

        let sx = Int(seed.x.rounded(.down))
        let sy = Int(seed.y.rounded(.down))
        guard sx >= 0, sx < w, sy >= 0, sy < h else { return false }

        guard let source = context.makeImage() else { return false }

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let bufCtx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return false }
        bufCtx.setBlendMode(.copy)
        bufCtx.draw(source, in: CGRect(origin: .zero, size: pixelSize))

        // 文档 y 向上,内存行 0 在顶部 → 内存行 = h - 1 - docY
        func idx(_ x: Int, _ y: Int) -> Int {
            let row = h - 1 - y
            return (row * w + x) * 4
        }
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = idx(x, y)
            return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]), Int(buffer[i + 3]))
        }
        func matches(_ x: Int, _ y: Int, _ target: (Int, Int, Int, Int)) -> Bool {
            let p = pixel(x, y)
            return abs(p.0 - target.0) <= tolerance
                && abs(p.1 - target.1) <= tolerance
                && abs(p.2 - target.2) <= tolerance
                && abs(p.3 - target.3) <= tolerance
        }

        let target = pixel(sx, sy)
        var visited = [Bool](repeating: false, count: w * h)
        var spans: [(Int, Int, Int)] = []   // (x0, x1, docY)
        var stack: [(Int, Int)] = [(sx, sy)]

        while let (px, py) = stack.popLast() {
            guard px >= 0, px < w, py >= 0, py < h else { continue }
            let flat = (h - 1 - py) * w + px
            if visited[flat] { continue }
            if !matches(px, py, target) { continue }

            // 向左扩展到 span 起点
            var x0 = px
            while x0 - 1 >= 0 {
                let nx = x0 - 1
                let f = (h - 1 - py) * w + nx
                if visited[f] || !matches(nx, py, target) { break }
                x0 = nx
            }

            var spanAbove = false
            var spanBelow = false
            var x = x0
            while x < w {
                let f = (h - 1 - py) * w + x
                if visited[f] || !matches(x, py, target) { break }
                visited[f] = true
                spans.append((x0, x, py))

                if py + 1 < h {
                    if matches(x, py + 1, target) {
                        if !spanBelow {
                            stack.append((x, py + 1))
                            spanBelow = true
                        }
                    } else {
                        spanBelow = false
                    }
                }
                if py - 1 >= 0 {
                    if matches(x, py - 1, target) {
                        if !spanAbove {
                            stack.append((x, py - 1))
                            spanAbove = true
                        }
                    } else {
                        spanAbove = false
                    }
                }
                x += 1
            }
        }

        guard !spans.isEmpty else { return false }

        let path = CGMutablePath()
        for (a, b, y) in spans {
            path.addRect(CGRect(x: CGFloat(a), y: CGFloat(y), width: CGFloat(b - a + 1), height: 1))
        }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.restoreGState()
        return true
    }
}

// MARK: - 文本

enum TextRenderer {
    static func makeAttributed(_ text: String, size: CGFloat, color: RGBA) -> NSAttributedString {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.cgColor,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    /// 在 `origin` 处绘制文字,origin 为基线起点(文档坐标,y 向上)
    static func draw(_ attributed: NSAttributedString, at origin: CGPoint, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 文字尺寸
    static func size(of attributed: NSAttributedString) -> CGSize {
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// 文字总高度(用于点击落点定位基线)
    static func ascent(of attributed: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}
