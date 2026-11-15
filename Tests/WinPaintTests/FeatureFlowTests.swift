import AppKit
import CoreGraphics
import XCTest
@testable import WinPaint

/// 第二批功能测试:工具库、工具条开关、AppModel 动作链路。
///
/// 第一批(FunctionalTests)管「文档和文件」;这一批管「用户按工具条按钮」。
@MainActor
final class FeatureFlowTests: XCTestCase {

    // MARK: - 形状库:24 种形状都得画得出东西

    /// 形状库里每一个图标都得真的画得出像素。
    ///
    /// 抠位图只覆盖了前 4 行,第五行以后是矢量画的 —— 矢量路径写错一个参数,
    /// 那个格子就会是空白,用户在形状库里一点选不上。这里把 24 种全过一遍。
    func testEveryShapeKindRendersVisiblePixels() {
        for kind in ShapeKind.allCases {
            let canvas = BitmapCanvas(pixelSize: CGSize(width: 60, height: 60))
            ShapeRenderer.draw(kind: kind,
                               in: CGRect(x: 8, y: 8, width: 44, height: 44),
                               context: canvas.context,
                               fill: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),
                               stroke: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),
                               lineWidth: 1.5)
            let painted = countOpaque(canvas)
            XCTAssertGreaterThan(painted, 8, "形状「\(kind.displayName)」画出来是空的")
        }
    }

    /// 形状画出来不能压到隔壁格子(量真实墨迹,不能用 path.boundingBox ——
    /// 贝塞尔曲线那个给的是控制点包围盒,比真实曲线大一圈)
    func testShapeInkStaysInsideItsCell() {
        for kind in ShapeKind.allCases {
            let canvas = BitmapCanvas(pixelSize: CGSize(width: 40, height: 40))
            ShapeRenderer.draw(kind: kind,
                               in: CGRect(x: 10, y: 10, width: 20, height: 20),
                               context: canvas.context,
                               fill: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),
                               stroke: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),
                               lineWidth: 1.5)
            guard let img = canvas.image() else { return XCTFail("取不到图像") }
            let w = img.width, h = img.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return }
            ctx.setBlendMode(.copy)
            ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
            var minX = w, maxX = -1, minY = h, maxY = -1
            for y in 0..<h {
                for x in 0..<w where buffer[(y * w + x) * 4 + 3] > 20 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return XCTFail("「\(kind.displayName)」什么都没画出来") }
            // cell 在 10..30,允许 1px 的线宽溢出
            XCTAssertGreaterThanOrEqual(minX, 8, "「\(kind.displayName)」左边压出格子了")
            XCTAssertLessThanOrEqual(maxX, 31, "「\(kind.displayName)」右边压出格子了")
            XCTAssertGreaterThanOrEqual(minY, 8, "「\(kind.displayName)」上边压出格子了")
            XCTAssertLessThanOrEqual(maxY, 31, "「\(kind.displayName)」下边压出格子了")
        }
    }

    // MARK: - 橡皮擦 / 取色器

    /// 橡皮擦:用 destinationOut 把像素擦掉,而不是涂黑
    func testEraserClearsInsteadOfPainting() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 40, height: 40))
        canvas.context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        canvas.context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertGreaterThan(canvas.pixel(at: CGPoint(x: 20, y: 20))?.a ?? 0, 0.9)

        var settings = BrushSettings(size: 12)
        settings.isEraser = true
        BrushRenderer.stroke(context: canvas.context,
                             points: [CGPoint(x: 20, y: 20)],
                             settings: settings)
        XCTAssertLessThan(canvas.pixel(at: CGPoint(x: 20, y: 20))?.a ?? 1, 0.2, "橡皮没擦掉")
    }

    /// 取色器:读回来的颜色要跟画上去的一致
    func testPickColorReadsBackWhatWasPainted() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 20, height: 20))
        canvas.context.setFillColor(CGColor(srgbRed: 0, green: 0.6, blue: 0.2, alpha: 1))
        canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let p = canvas.pixel(at: CGPoint(x: 10, y: 10))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertEqual(p.r, 0, accuracy: 0.05)
            XCTAssertEqual(p.g, 0.6, accuracy: 0.05)
            XCTAssertEqual(p.b, 0.2, accuracy: 0.05)
        }
    }

    // MARK: - 缩放滑块

    /// 滑块的「位置 ↔ 倍率」必须能来回换算,不然拖一下会跳
    func testZoomSliderPositionAndScaleRoundTrip() {
        for z in [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0] {
            let f = ZoomSlider.fraction(forZoom: CGFloat(z))
            XCTAssertGreaterThanOrEqual(f, 0, "位置不能小于 0")
            XCTAssertLessThanOrEqual(f, 1, "位置不能大于 1")
            let back = ZoomSlider.zoom(forFraction: f)
            XCTAssertEqual(Double(back), Double(z), accuracy: 0.01, "倍率 \(z) 往返对不上")
        }
    }

    /// 100% 必须落在滑块偏左的位置(原版实测把手中心在 23/163)
    func testZoomSliderHundredPercentSitsNearLeft() {
        let f = ZoomSlider.fraction(forZoom: 1.0)
        XCTAssertEqual(Double(f), Double(ZoomSlider.fitFraction), accuracy: 0.001)
        XCTAssertEqual(Double(ZoomSlider.fitFraction), 23.0 / 163.0, accuracy: 0.0001)
    }

    /// 「适应窗口」不能超过 100%
    func testFitToWindowNeverExceedsHundredPercent() {
        let c = CanvasController()
        let doc = PaintDocument(size: CGSize(width: 1200, height: 630))
        c.document = doc
        c.viewportSize = CGSize(width: 600, height: 400)
        c.fitToWindow()
        XCTAssertLessThanOrEqual(c.zoom, 1.0, "适应窗口超过了 100%")
        XCTAssertGreaterThan(c.zoom, 0.1)
    }

    // MARK: - 工具条开关

    /// 网格线 / 标尺 / 状态栏 / 图层面板四个开关要互不干扰
    func testToolbarTogglesAreIndependent() {
        let c = CanvasController()
        XCTAssertFalse(c.showsGrid)
        XCTAssertFalse(c.showsRulers)
        XCTAssertTrue(c.showsStatusBar)
        XCTAssertFalse(c.showsLayerPanel)

        c.showsGrid = true
        XCTAssertTrue(c.showsGrid)
        XCTAssertFalse(c.showsRulers, "开网格线把标尺也开了")
        XCTAssertTrue(c.showsStatusBar, "开网格线把状态栏关了")

        c.showsRulers = true
        XCTAssertTrue(c.showsGrid, "开标尺把网格线关了")
        XCTAssertTrue(c.showsRulers)

        c.showsLayerPanel = true
        XCTAssertTrue(c.showsStatusBar, "开图层面板把状态栏关了")
    }

    // MARK: - AppModel 动作

    /// 全选 / 取消选择
    func testSelectAllAndClearSelection() {
        let m = AppModel()
        XCTAssertNil(m.controller.selectionRect)

        m.selectAll()
        XCTAssertEqual(m.controller.selectionRect,
                       CGRect(origin: .zero, size: m.document.size),
                       "全选没框住整张画布")

        m.clearSelection()
        XCTAssertNil(m.controller.selectionRect, "取消选择没清掉选区")
    }

    /// 「向右旋转 / 水平翻转」这些工具条动作要真的作用到文档上
    func testToolbarImageActionsAffectDocument() {
        let m = AppModel()
        let w = m.document.size.width, h = m.document.size.height

        m.handle(.rotateRight)
        XCTAssertEqual(m.document.size, CGSize(width: h, height: w), "向右旋转没换尺寸")

        m.handle(.rotateLeft)
        XCTAssertEqual(m.document.size, CGSize(width: w, height: h), "向左旋转没转回来")

        m.handle(.flipHorizontal)
        m.handle(.flipVertical)
        XCTAssertEqual(m.document.size, CGSize(width: w, height: h), "翻转把尺寸改了")
        XCTAssertTrue(m.document.history.canUndo, "翻转没进历史")
    }

    /// 「新建」要清空文档、标题和选区
    func testNewDocumentClearsEverything() {
        let m = AppModel()
        m.document.documentTitle = "旧名字"
        m.document.fileURL = URL(fileURLWithPath: "/tmp/old.png")
        m.selectAll()
        m.handle(.flipHorizontal)

        m.newDocument()
        XCTAssertEqual(m.document.documentTitle, "无标题")
        XCTAssertNil(m.document.fileURL)
        XCTAssertNil(m.controller.selectionRect)
        XCTAssertEqual(m.document.size, CGSize(width: 1200, height: 630))
    }

    /// 窗口标题要带「- 画图」
    func testWindowTitleIncludesPaintSuffix() {
        let m = AppModel()
        m.document.documentTitle = "测试图"
        XCTAssertTrue(m.windowTitle.hasSuffix(" - 画图"), "窗口标题不对:\(m.windowTitle)")
        XCTAssertTrue(m.windowTitle.contains("测试图"))
    }

    // MARK: - 历史

    /// 图层增删移这些结构操作也要能撤销回去
    func testLayerStructureUndoRedo() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40))
        doc.reset(to: CGSize(width: 40, height: 40))
        XCTAssertEqual(doc.layers.count, 1)

        doc.addLayer()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertTrue(doc.history.canUndo)

        doc.undo()
        XCTAssertEqual(doc.layers.count, 1, "撤销加层没退回去")

        doc.redo()
        XCTAssertEqual(doc.layers.count, 2, "重做加层没回来")
    }

    /// 读回来的项目文件应该是「干净」的(没有未保存改动)
    func testProjectReadProducesCleanDocument() throws {
        let doc = PaintDocument(size: CGSize(width: 30, height: 30))
        doc.reset(to: CGSize(width: 30, height: 30))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("winpaint-clean-\(UUID().uuidString).json")
        try ProjectFile.write(document: doc, to: url)

        let doc2 = PaintDocument(size: CGSize(width: 10, height: 10))
        try ProjectFile.read(from: url, into: doc2)
        XCTAssertFalse(doc2.isDirty, "刚读进来的项目不该是脏的")
        XCTAssertEqual(doc2.size, CGSize(width: 30, height: 30))

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 辅助

    /// 数一数画布里不透明的像素
    private func countOpaque(_ canvas: BitmapCanvas) -> Int {
        guard let img = canvas.image() else { return 0 }
        let w = img.width, h = img.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return 0 }
        ctx.setBlendMode(.copy)
        ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        return buffer.enumerated().filter { $0.offset % 4 == 3 }.filter { $0.element > 20 }.count
    }
}
