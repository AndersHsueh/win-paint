import AppKit
import Foundation

/// 核心画布视图。
///
/// 用 AppKit NSView 而不是 SwiftUI `Canvas` 的原因很实际:
/// NSView 原生坐标系就是 **原点左下、y 向上**,与本项目的文档坐标系完全一致,
/// 于是整条链路(鼠标 → 文档坐标 → 位图 → 屏幕)一次翻转都不需要,文字也不会上下颠倒。
///
/// 绘制策略:
/// - 文档内容来自 `PaintDocument.composite()`(有缓存)
/// - 拖拽中的笔迹/形状画进一块**预览缓冲区**,提交时才落到图层上
/// - 预览与最终结果用同一套绘制代码,所见即所得
final class PaintCanvasView: NSView {

    // MARK: 依赖

    var controller: CanvasController?
    var document: PaintDocument?

    /// 外部(菜单)触发的操作回调
    var onCommit: ((String) -> Void)?
    var onChange: (() -> Void)?

    // MARK: 交互状态

    private var previewContext: CGContext?
    private var previewDirty: CGRect = .zero
    private var previewIsMask = false

    private var strokePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero
    private var dragCurrent: CGPoint = .zero
    private var isDragging = false
    private var isPanning = false
    private var panStartOffset: CGPoint = .zero
    /// 上次居中时的视口尺寸,用来判断是否需要重新居中
    private var lastFitSize: NSSize = .zero

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textLayerID: UUID?

    // MARK: 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        focusRingType = .none
    }

    /// 画布区底色交给 SwiftUI 层的 Mica 背景,这个视图自己保持透明
    override var isOpaque: Bool { false }

    // MARK: 坐标换算

    /// 视图坐标 → 文档坐标
    func toDoc(_ viewPoint: CGPoint) -> CGPoint {
        let zoom = controller?.zoom ?? 1
        let pan = controller?.pan ?? .zero
        guard zoom > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - pan.x) / zoom, y: (viewPoint.y - pan.y) / zoom)
    }

    /// 文档坐标 → 视图坐标
    func toView(_ docPoint: CGPoint) -> CGPoint {
        let zoom = controller?.zoom ?? 1
        let pan = controller?.pan ?? .zero
        return CGPoint(x: docPoint.x * zoom + pan.x, y: docPoint.y * zoom + pan.y)
    }

    /// 让文档完整落在视图内
    func fitToWindow() {
        guard let doc = document, bounds.width > 1, bounds.height > 1 else { return }
        let scale = min(bounds.width / doc.size.width, bounds.height / doc.size.height)
        controller?.zoom = max(min(scale, 1.0), 0.02)
        centerCanvas()
        needsDisplay = true
        onChange?()
    }

    /// 按当前缩放把文档重新摆到视口正中(不改缩放倍率)。
    ///
    /// 原版 Windows 画图打开时画布是 100% 且在画布区里居中的,而窗口尺寸会在
    /// 布局确定前先变一次 —— 早期版本在错误的 bounds(1440×648)上算了一次居中就
    /// 再也不重算,结果画布整体偏移了 22px/36px。所以这里必须能在 bounds 变化后
    /// 重新居中,只要用户还没手动平移过。
    func centerCanvas() {
        guard let doc = document, let ctrl = controller,
              bounds.width > 1, bounds.height > 1 else { return }
        ctrl.pan = CGPoint(
            x: (bounds.width - doc.size.width * ctrl.zoom) / 2,
            // 原版画布内容比精确居中高 2px(照片 265..894 而不是 267..896),
            // 这里照抄原版的偏移量,保证 1:1 像素对齐。
            // 实测最优是 +1.4:offset 每 +1 画布往**上**移 1px(AppKit 坐标 y 向上),
            // +2 时画布顶边落在 264.55、比原版的 265 高了半像素。
            y: (bounds.height - doc.size.height * ctrl.zoom) / 2 + 1.4
        )
        needsDisplay = true
    }

    /// 以某点为锚缩放
    func zoom(to newZoom: CGFloat, anchor: CGPoint) {
        guard let ctrl = controller else { return }
        let clamped = min(max(newZoom, 0.02), 32)
        let docPoint = toDoc(anchor)
        ctrl.zoom = clamped
        ctrl.pan = CGPoint(x: anchor.x - docPoint.x * clamped, y: anchor.y - docPoint.y * clamped)
        ctrl.didUserPan = true
        needsDisplay = true
        onChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        controller?.viewportSize = newSize
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        controller?.viewportSize = bounds.size
        guard let ctrl = controller, bounds.width > 1, bounds.height > 1 else { return }
        if !ctrl.didInitialFit {
            // 原版打开时就是 100% 缩放 + 在画布区居中,不做「适应窗口」缩放
            ctrl.didInitialFit = true
            ctrl.zoom = 1.0
            centerCanvas()
            lastFitSize = bounds.size
        } else if !ctrl.didUserPan, bounds.size != lastFitSize {
            // bounds 又变了(窗口尺寸变化 / 工具选项栏出现)→ 重新居中,保持 1:1 像素对齐。
            // 只在尺寸真的变了时才写 pan,避免在 layout 里反复改 @Observable 触发循环。
            lastFitSize = bounds.size
            centerCanvas()
        }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ctrl = controller
        let doc = document

        // 画布区底色由 SwiftUI 层的 Mica 渐变负责,这里不再铺底色

        guard let ctrl, let doc else { return }

        let zoom = ctrl.zoom
        let pan = ctrl.pan

        ctx.saveGState()
        ctx.translateBy(x: pan.x, y: pan.y)
        ctx.scaleBy(x: zoom, y: zoom)

        let docRect = CGRect(origin: .zero, size: doc.size)

        // 画布白底(原版的画布边缘只有外面一圈投影暗线,见下)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(docRect)

        // 画布四周的投影暗线。
        //
        // 原版实测(逐像素):画布内容占 x 142..1341 / y 265..894,外面还套着
        //   上 1px (y=264) / 左 2px (x=140,141) / 右 1px (x=1342) / 下 2px (y=895,896)
        // 亮度是底色的 95%~97%,也就是盖了一层 3%~5% 的黑。
        // 之前只在 docRect 上描了一条 1px 8% 的边,结果只有半条、还偏亮。
        drawCanvasShadow(in: ctx, docRect: docRect, zoom: zoom, pan: pan)

        // 文档内容
        if let image = doc.composite() {
            ctx.draw(image, in: docRect)
        }

        // 网格
        if ctrl.showsGrid {
            drawGrid(in: ctx, docRect: docRect, spacing: ctrl.gridSpacing, zoom: zoom)
        }

        // 实时预览
        drawPreview(in: ctx)

        ctx.restoreGState()

        // 画布四周的八个选框手柄(原版是画在画布外侧的 7×7 空心小方块)
        drawFrameHandles(in: ctx, docRect: docRect, zoom: zoom, pan: pan)

        // 选区(视图空间画,便于画虚线框)
        if let selection = ctrl.selectionRect {
            drawSelection(in: ctx, docRect: selection)
        }
    }

    /// 画布四周的投影暗线(原版实测:上 1px / 左 2px / 右 1px / 下 2px)
    ///
    /// 颜色是盖在 Mica 底色上的一层薄黑(3%~5%),所以直接用带 alpha 的黑填充,
    /// 让 AppKit 跟底下的 Mica 做合成 —— 底色有渐变,这样才不会画成一条死色。
    ///
    /// ⚠️ 调用时 ctx 已经做过 `translate(pan)` + `scale(zoom)`,
    /// 所以这里用的是**文档坐标系**:画布下边在 y=0、上边在 y=height*zoom。
    /// 再叠一次 pan 会把暗线推到画布外面去(之前就踩过)。
    private func drawCanvasShadow(in ctx: CGContext, docRect: CGRect, zoom: CGFloat, pan: CGPoint) {
        let left = docRect.minX
        let bottom = docRect.minY
        let right = docRect.maxX * zoom
        let top = docRect.maxY * zoom
        let w = right - left
        let h = top - bottom

        // 每边的厚度和浓度都按原版逐像素取值
        let edge = 1.0 / max(zoom, 0.01)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.045).cgColor)
        // 上 1px
        ctx.fill(CGRect(x: left, y: top, width: w, height: edge))
        // 右 1px
        ctx.fill(CGRect(x: right, y: bottom - 2 * edge, width: edge, height: h + 3 * edge))
        // 左 2px
        ctx.fill(CGRect(x: left - 2 * edge, y: bottom - 2 * edge, width: 2 * edge, height: h + 4 * edge))
        // 下 2px(离画布越远越淡)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.030).cgColor)
        ctx.fill(CGRect(x: left - 2 * edge, y: bottom - edge, width: w + 3 * edge, height: edge))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.045).cgColor)
        ctx.fill(CGRect(x: left - 2 * edge, y: bottom - 2 * edge, width: w + 3 * edge, height: edge))
    }

    /// 画布边框手柄:四角 + 四边中点,共 8 个 7×7 的空心方块
    private func drawFrameHandles(in ctx: CGContext, docRect: CGRect, zoom: CGFloat, pan: CGPoint) {
        let s: CGFloat = 7
        let left = pan.x
        let bottom = pan.y
        let right = pan.x + docRect.width * zoom
        let top = pan.y + docRect.height * zoom
        let midX = left + docRect.width * zoom / 2
        let midY = bottom + docRect.height * zoom / 2

        // (起点 x, 起点 y)——都落在画布外侧,紧贴边
        let spots: [(CGFloat, CGFloat)] = [
            (left - 8, top),          // 左上
            (midX - s / 2, top),      // 上中
            (right, top),             // 右上
            (left - 8, midY - s / 2), // 左中
            (right, midY - s / 2),    // 右中
            (left - 8, bottom - s),   // 左下
            (midX - s / 2, bottom - s), // 下中
            (right, bottom - s)       // 右下
        ]

        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.2)
        for (x, y) in spots {
            ctx.fill(CGRect(x: x, y: y, width: s, height: s))
            ctx.stroke(CGRect(x: x, y: y, width: s, height: s))
        }
        ctx.restoreGState()
    }

    private func drawGrid(in ctx: CGContext, docRect: CGRect, spacing: CGFloat, zoom: CGFloat) {
        guard spacing > 0, zoom * spacing >= 5 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(1 / zoom)
        var x = spacing
        while x < docRect.width {
            ctx.move(to: CGPoint(x: x, y: docRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: docRect.maxY))
            x += spacing
        }
        var y = spacing
        while y < docRect.height {
            ctx.move(to: CGPoint(x: docRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: docRect.maxX, y: y))
            y += spacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawPreview(in ctx: CGContext) {
        guard let ctrl = controller, let doc = document else { return }

        // 形状预览
        if isDragging, ctrl.tool == .shape, let rect = normalizedDragRect() {
            let fillColor: CGColor? = ctrl.fillStyle == .solid ? ctrl.primaryColor.cgColor : nil
            let strokeColor: CGColor? = ctrl.strokeStyle == .stroked ? ctrl.primaryColor.cgColor : nil
            ShapeRenderer.draw(kind: ctrl.shapeKind, in: rect, context: ctx,
                               fill: fillColor, stroke: strokeColor, lineWidth: ctrl.lineWidth)
            return
        }

        // 笔迹预览
        if let preview = previewContext, let image = preview.makeImage(), !previewDirty.isEmpty {
            ctx.saveGState()
            if previewIsMask {
                // 橡皮擦:用半透明遮罩表示"将被擦除的区域"
                ctx.setBlendMode(.normal)
                ctx.setAlpha(0.45)
                ctx.draw(image, in: CGRect(origin: .zero, size: doc.size))
            } else {
                ctx.draw(image, in: CGRect(origin: .zero, size: doc.size))
            }
            ctx.restoreGState()
        }
    }

    private func drawSelection(in ctx: CGContext, docRect: CGRect) {
        let zoom = controller?.zoom ?? 1
        let pan = controller?.pan ?? .zero
        let viewRect = CGRect(
            x: docRect.minX * zoom + pan.x,
            y: docRect.minY * zoom + pan.y,
            width: docRect.width * zoom,
            height: docRect.height * zoom
        )
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(viewRect)
        ctx.restoreGState()
    }

    // MARK: 预览缓冲区

    private func ensurePreviewBuffer() -> CGContext? {
        guard let doc = document else { return nil }
        if previewContext == nil {
            let w = max(1, Int(doc.size.width.rounded()))
            let h = max(1, Int(doc.size.height.rounded()))
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            previewContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            previewContext?.setAllowsAntialiasing(true)
        }
        return previewContext
    }

    private func resetPreview(mask: Bool) {
        guard let ctx = previewContext, let doc = document else { return }
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.clear(CGRect(origin: .zero, size: doc.size))
        ctx.restoreGState()
        previewDirty = .zero
        previewIsMask = mask
    }

    // MARK: 鼠标

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let docPoint = toDoc(viewPoint)
        guard let ctrl = controller else { return }

        dragStart = docPoint
        dragCurrent = docPoint

        // 空格 / 中键 → 平移
        if event.charactersIgnoringModifiers == " " || event.buttonNumber == 1 {
            isPanning = true
            panStartOffset = ctrl.pan
            dragOriginView = viewPoint
            return
        }

        switch ctrl.tool {
        case .pencil, .brush, .eraser:
            beginStroke(at: docPoint)
        case .fill:
            applyFloodFill(at: docPoint)
        case .eyedropper:
            pickColor(at: docPoint)
        case .magnifier:
            zoom(to: ctrl.zoom * 2, anchor: viewPoint)
        case .select, .freehandSelect, .crop:
            isDragging = true
            ctrl.selectionRect = CGRect(origin: docPoint, size: .zero)
            needsDisplay = true
        case .text:
            beginText(at: docPoint)
        case .shape:
            isDragging = true
            resetPreview(mask: false)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let docPoint = toDoc(viewPoint)
        dragCurrent = docPoint

        if isPanning, let ctrl = controller {
            ctrl.pan = CGPoint(x: panStartOffset.x + (viewPoint.x - dragOriginView.x),
                               y: panStartOffset.y + (viewPoint.y - dragOriginView.y))
            ctrl.didUserPan = true
            needsDisplay = true
            onChange?()
            return
        }

        guard let ctrl = controller else { return }

        switch ctrl.tool {
        case .pencil, .brush, .eraser:
            appendStroke(at: docPoint)
        case .select, .freehandSelect, .crop:
            ctrl.selectionRect = normalizedDragRect()
            needsDisplay = true
        case .shape:
            needsDisplay = true
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            return
        }
        guard let ctrl = controller else { return }

        switch ctrl.tool {
        case .pencil, .brush, .eraser:
            endStroke()
        case .shape:
            commitShape()
        case .select, .freehandSelect, .crop:
            isDragging = false
            if let sel = ctrl.selectionRect, sel.width < 2 || sel.height < 2 {
                ctrl.selectionRect = nil
            }
            needsDisplay = true
            onChange?()
        default:
            break
        }
    }

    /// 平移用的起始视图坐标
    private var dragOriginView: CGPoint = .zero

    override func scrollWheel(with event: NSEvent) {
        guard let ctrl = controller else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) {
            // ⌘ + 滚轮 = 缩放
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 + event.scrollingDeltaY * 0.01 : 1.1
            zoom(to: ctrl.zoom * factor, anchor: viewPoint)
        } else {
            // 普通滚动 = 平移
            ctrl.pan = CGPoint(x: ctrl.pan.x + event.scrollingDeltaX,
                               y: ctrl.pan.y + event.scrollingDeltaY)
            ctrl.didUserPan = true
            needsDisplay = true
            onChange?()
        }
    }

    // MARK: 各工具实现

    private func beginStroke(at point: CGPoint) {
        guard let ctrl = controller else { return }
        let isEraser = ctrl.tool == .eraser
        resetPreview(mask: isEraser)
        strokePoints = [point]
        isDragging = true

        // 橡皮擦用「遮罩」模式:遮罩画成不透明黑,提交时用 destinationOut 扣掉图层像素
        var settings = ctrl.brush
        settings.isEraser = false
        if isEraser {
            settings.color = RGBA(0, 0, 0)
        }
        if let ctx = previewContext {
            BrushRenderer.stroke(context: ctx, points: [point], settings: settings)
            previewDirty = strokeBounds(points: [point], size: settings.size)
        }
        needsDisplay = true
    }

    private func appendStroke(at point: CGPoint) {
        guard let ctrl = controller, let ctx = previewContext else { return }
        var settings = ctrl.brush
        settings.isEraser = false
        if ctrl.tool == .eraser { settings.color = RGBA(0, 0, 0) }

        strokePoints.append(point)
        let last = strokePoints.count >= 2 ? strokePoints[strokePoints.count - 2] : point
        BrushRenderer.stroke(context: ctx, points: [last, point], settings: settings)
        previewDirty = previewDirty.union(strokeBounds(points: [last, point], size: settings.size))
        needsDisplay = true
    }

    private func endStroke() {
        guard let ctrl = controller, let doc = document,
              let targetLayer = doc.selectedLayer, let ctx = previewContext else { return }
        isDragging = false

        guard let previewImage = ctx.makeImage(), !previewDirty.isEmpty else {
            strokePoints = []
            needsDisplay = true
            return
        }

        let rect = previewDirty
        let before = doc.capturePatch(layerID: targetLayer.id, rect: rect)

        if previewIsMask {
            targetLayer.canvas.applyMask(previewImage)
            doc.markDirty()
        } else {
            targetLayer.canvas.draw(image: previewImage, in: CGRect(origin: .zero, size: doc.size))
            doc.markDirty()
        }

        let title = ctrl.tool == .eraser ? "橡皮擦" : (ctrl.tool == .brush ? "画笔" : "铅笔")
        doc.commitPatch(title: title, layerID: targetLayer.id, rect: rect, before: before)

        resetPreview(mask: false)
        strokePoints = []
        needsDisplay = true
        onChange?()
        onCommit?(title)
    }

    private func strokeBounds(points: [CGPoint], size: CGFloat) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let r = size / 2 + 1
        return CGRect(x: minX - r, y: minY - r, width: maxX - minX + r * 2, height: maxY - minY + r * 2)
    }

    private func commitShape() {
        guard let ctrl = controller, let doc = document, let layer = doc.selectedLayer else { return }
        isDragging = false
        guard let rect = normalizedDragRect(), rect.width >= 1, rect.height >= 1 else {
            needsDisplay = true
            return
        }
        let before = doc.capturePatch(layerID: layer.id, rect: rect.insetBy(dx: -2, dy: -2))
        let fillColor: CGColor? = ctrl.fillStyle == .solid ? ctrl.primaryColor.cgColor : nil
        let strokeColor: CGColor? = ctrl.strokeStyle == .stroked ? ctrl.primaryColor.cgColor : nil
        ShapeRenderer.draw(kind: ctrl.shapeKind, in: rect, context: layer.canvas.context,
                           fill: fillColor, stroke: strokeColor, lineWidth: ctrl.lineWidth)
        doc.markDirty()
        doc.commitPatch(title: "形状", layerID: layer.id, rect: rect.insetBy(dx: -2, dy: -2), before: before)
        needsDisplay = true
        onChange?()
        onCommit?("形状")
    }

    private func applyFloodFill(at point: CGPoint) {
        guard let ctrl = controller, let doc = document, let layer = doc.selectedLayer else { return }
        let rect = CGRect(origin: .zero, size: doc.size)
        let before = doc.capturePatch(layerID: layer.id, rect: rect)
        let ok = FloodFill.fill(context: layer.canvas.context, seed: point,
                                color: ctrl.primaryColor, pixelSize: doc.size)
        guard ok else { return }
        doc.markDirty()
        doc.commitPatch(title: "填充", layerID: layer.id, rect: rect, before: before)
        needsDisplay = true
        onChange?()
        onCommit?("填充")
    }

    private func pickColor(at point: CGPoint) {
        guard let ctrl = controller, let doc = document, let composite = doc.composite() else { return }
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < composite.width, y < composite.height else { return }
        guard let provider = composite.dataProvider, let data = provider.data else { return }
        let bytes = data as Data
        let bytesPerRow = composite.bytesPerRow
        // CGImage 行 0 在顶部,文档 y 向上 → 内存行 = height - 1 - y
        let row = composite.height - 1 - y
        let offset = row * bytesPerRow + x * 4
        guard bytes.count >= offset + 4 else { return }
        let b = bytes[offset], g = bytes[offset + 1], r = bytes[offset + 2], a = bytes[offset + 3]
        guard a > 0 else { return }
        ctrl.primaryColor = RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        onChange?()
    }

    private func normalizedDragRect() -> CGRect? {
        let dx = dragCurrent.x - dragStart.x
        let dy = dragCurrent.y - dragStart.y
        guard dx != 0 || dy != 0 else { return nil }
        return CGRect(x: min(dragStart.x, dragCurrent.x),
                      y: min(dragStart.y, dragCurrent.y),
                      width: abs(dx),
                      height: abs(dy))
    }

    // MARK: 文本

    private func beginText(at point: CGPoint) {
        guard let ctrl = controller, let doc = document, let layer = doc.selectedLayer else { return }
        textLayerID = layer.id
        textOrigin = point

        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.font = NSFont.systemFont(ofSize: ctrl.textSize)
        field.textColor = ctrl.primaryColor.nsColor
        field.stringValue = ""

        let origin = toView(point)
        let size = NSSize(width: 400, height: ctrl.textSize * 1.6)
        field.frame = NSRect(x: origin.x, y: origin.y - 4, width: size.width, height: size.height)

        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)

        field.delegate = self
    }

    /// 外部(菜单)调用:提交当前正在编辑的文字
    func commitActiveText() {
        guard let field = textField, let layerID = textLayerID else { return }
        let text = field.stringValue
        let size = field.font?.pointSize ?? 24
        let color = field.textColor ?? NSColor.black
        field.removeFromSuperview()
        textField = nil
        textLayerID = nil

        guard !text.isEmpty, let doc = document, let layer = doc.layer(with: layerID) else {
            needsDisplay = true
            return
        }

        let rgba = RGBA(Double(color.redComponent), Double(color.greenComponent),
                        Double(color.blueComponent), Double(color.alphaComponent))
        let attributed = TextRenderer.makeAttributed(text, size: size, color: rgba)
        let textSize = TextRenderer.size(of: attributed)
        let ascent = TextRenderer.ascent(of: attributed)
        let origin = CGPoint(x: textOrigin.x, y: textOrigin.y + ascent)

        let rect = CGRect(x: textOrigin.x - 2, y: textOrigin.y - 2,
                          width: textSize.width + 4, height: textSize.height + 4)
        let before = doc.capturePatch(layerID: layerID, rect: rect)
        TextRenderer.draw(attributed, at: origin, in: layer.canvas.context)
        doc.markDirty()
        doc.commitPatch(title: "文本", layerID: layerID, rect: rect, before: before)
        needsDisplay = true
        onChange?()
        onCommit?("文本")
    }

    /// 把画布内容裁剪到当前选区
    func cropToSelection() {
        guard let ctrl = controller, let doc = document,
              let layer = doc.selectedLayer, let sel = ctrl.selectionRect else { return }
        let rect = sel.intersection(CGRect(origin: .zero, size: doc.size)).integral
        guard rect.width >= 1, rect.height >= 1 else { return }
        guard let cropped = layer.canvas.snapshot(in: rect) else { return }
        let fresh = BitmapCanvas(pixelSize: rect.size)
        fresh.draw(image: cropped, in: CGRect(origin: .zero, size: rect.size))
        layer.canvas = fresh
        doc.markDirty()
        ctrl.selectionRect = nil
        needsDisplay = true
        onChange?()
    }
}

// MARK: - 文本框代理

extension PaintCanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        // Enter 或失焦都提交
        commitActiveText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitActiveText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitActiveText()
            return true
        }
        return false
    }
}
