import CoreGraphics
import XCTest
@testable import WinPaint

/// 核心逻辑测试。
///
/// 这些用例盯的是"画出来的东西对不对"和"撤销能不能真的退回去",
/// 而不是"代码跑没跑崩"。像素级断言,防止画布坐标翻转之类的错误被放过。
///
/// ⚠️ 断言颜色必须**逐分量**比。踩过的坑:用单个通道区分颜色 ——
/// 红 (1,0,0) 和白 (1,1,1) 的红通道都是 1.0,蓝 (0,0,1) 和白 (1,1,1) 的蓝通道也都是 1.0,
/// 断言写得再"认真"也照样放行。所以统一走 `assertColor`。
@MainActor
final class PaintCoreTests: XCTestCase {

    // MARK: - 断言辅助

    private func assertColor(_ actual: RGBA?, _ expected: RGBA,
                             accuracy: Double = 0.12, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let a = actual else {
            XCTFail("取不到像素\(message.isEmpty ? "" : " — \(message)")", file: file, line: line)
            return
        }
        XCTAssertEqual(a.r, expected.r, accuracy: accuracy, "R 分量不符\(message.isEmpty ? "" : " — \(message)")", file: file, line: line)
        XCTAssertEqual(a.g, expected.g, accuracy: accuracy, "G 分量不符\(message.isEmpty ? "" : " — \(message)")", file: file, line: line)
        XCTAssertEqual(a.b, expected.b, accuracy: accuracy, "B 分量不符\(message.isEmpty ? "" : " — \(message)")", file: file, line: line)
    }

    private func assertTransparent(_ actual: RGBA?, _ message: String = "",
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let a = actual else {
            XCTFail("取不到像素", file: file, line: line)
            return
        }
        XCTAssertLessThan(a.a, 0.1, "应是透明的\(message.isEmpty ? "" : " — \(message)")", file: file, line: line)
    }

    /// 读合成图的像素
    private func compositePixel(_ doc: PaintDocument, x: Int, y: Int) -> RGBA? {
        guard let img = doc.composite() else { return nil }
        let w = img.width, h = img.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.setBlendMode(.copy)
        ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        let row = h - 1 - y
        let i = (row * w + x) * 4
        guard buffer.count >= i + 4 else { return nil }
        let a = Double(buffer[i + 3]) / 255
        guard a > 0 else { return RGBA(0, 0, 0, 0) }
        return RGBA(Double(buffer[i]) / 255 / a,
                    Double(buffer[i + 1]) / 255 / a,
                    Double(buffer[i + 2]) / 255 / a,
                    a)
    }

    // MARK: - 基础

    func testNewDocumentHasOneWhiteLayer() {
        let doc = PaintDocument(size: CGSize(width: 200, height: 100))
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.size, CGSize(width: 200, height: 100))
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 100, y: 50)), .white, "新文档应为白底")
    }

    func testCompositeMatchesLayer() {
        let doc = PaintDocument(size: CGSize(width: 50, height: 50))
        let comp = doc.composite()
        XCTAssertNotNil(comp)
        XCTAssertEqual(comp!.width, 50)
        XCTAssertEqual(comp!.height, 50)
    }

    // MARK: - 坐标约定

    /// 文档坐标 y 向上:画布底部和顶部必须区分得开。
    /// 这条挂了意味着整个应用的图形全是上下颠倒的。
    func testDocumentCoordinatesAreBottomUp() {
        let doc = PaintDocument(size: CGSize(width: 10, height: 10), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 10, height: 3))   // 底部红条

        assertColor(layer.canvas.pixel(at: CGPoint(x: 5, y: 1)), .red, "y=1 应落在底部红条")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 5, y: 9)), .white, "y=9 应是白色(y 向上)")
    }

    // MARK: - 形状

    func testRectangleShapeFillsInterior() {
        let doc = PaintDocument(size: CGSize(width: 100, height: 100), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        let rect = CGRect(x: 20, y: 20, width: 40, height: 30)
        ShapeRenderer.draw(kind: .rectangle, in: rect, context: layer.canvas.context,
                           fill: RGBA.red.cgColor, stroke: nil, lineWidth: 1)

        assertColor(layer.canvas.pixel(at: CGPoint(x: 40, y: 35)), .red, "矩形内部")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 80, y: 80)), .white, "矩形外部")
    }

    func testAllShapeKindsProduceNonEmptyGeometry() {
        for kind in ShapeKind.allCases {
            let path = ShapeRenderer.path(for: kind, in: CGRect(x: 0, y: 0, width: 50, height: 30))
            let box = path.boundingBox
            XCTAssertGreaterThan(box.width, 0, "\(kind.displayName) 宽度为 0")
            XCTAssertGreaterThan(box.height, 0, "\(kind.displayName) 高度为 0")
        }
    }

    func testArrowGeometryPointsShaftward() {
        let path = ShapeRenderer.path(for: .arrowRight, in: CGRect(x: 0, y: 0, width: 100, height: 40))
        let box = path.boundingBox
        XCTAssertEqual(box.minX, 0, accuracy: 0.5)
        XCTAssertEqual(box.maxX, 100, accuracy: 0.5)
        XCTAssertEqual(box.midY, 20, accuracy: 0.5)
    }

    func testNoFillLeavesInteriorUntouched() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        ShapeRenderer.draw(kind: .ellipse, in: CGRect(x: 10, y: 10, width: 40, height: 40),
                           context: layer.canvas.context, fill: nil, stroke: RGBA.red.cgColor, lineWidth: 3)
        assertColor(layer.canvas.pixel(at: CGPoint(x: 30, y: 30)), .white, "无填充时内部应保持原样")
    }

    // MARK: - 油漆桶

    func testFloodFillFillsContiguousRegion() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        let ok = FloodFill.fill(context: layer.canvas.context, seed: CGPoint(x: 20, y: 20),
                                color: RGBA.blue, pixelSize: doc.size)
        XCTAssertTrue(ok)

        assertColor(layer.canvas.pixel(at: CGPoint(x: 20, y: 20)), .blue, "种子点")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 1, y: 1)), .blue, "同色区域应一起被填")
    }

    func testFloodFillRespectsBoundary() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        // 中间画一道黑色竖墙,把画布分成两半
        layer.canvas.context.setFillColor(RGBA.black.cgColor)
        layer.canvas.context.fill(CGRect(x: 19, y: 0, width: 2, height: 40))

        _ = FloodFill.fill(context: layer.canvas.context, seed: CGPoint(x: 5, y: 20),
                           color: RGBA.blue, pixelSize: doc.size)

        assertColor(layer.canvas.pixel(at: CGPoint(x: 5, y: 20)), .blue, "墙左侧应被填")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 35, y: 20)), .white, "墙右侧不应被填")
    }

    // MARK: - 撤销 / 重做

    func testUndoRestoresPixels() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        let rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        let before = doc.capturePatch(layerID: layer.id, rect: rect)

        ShapeRenderer.draw(kind: .rectangle, in: rect, context: layer.canvas.context,
                           fill: RGBA.red.cgColor, stroke: nil, lineWidth: 1)
        doc.commitPatch(title: "形状", layerID: layer.id, rect: rect, before: before)

        assertColor(layer.canvas.pixel(at: CGPoint(x: 25, y: 25)), .red, "画完应是红色")

        doc.undo()
        assertColor(layer.canvas.pixel(at: CGPoint(x: 25, y: 25)), .white, "撤销后应恢复成白色")

        doc.redo()
        assertColor(layer.canvas.pixel(at: CGPoint(x: 25, y: 25)), .red, "重做后应再次变红")
    }

    func testUndoRedoStacksReportCorrectly() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        XCTAssertFalse(doc.history.canUndo)
        XCTAssertFalse(doc.history.canRedo)

        doc.addLayer()
        XCTAssertTrue(doc.history.canUndo)
        doc.undo()
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertTrue(doc.history.canRedo)
        doc.redo()
        XCTAssertEqual(doc.layers.count, 2)
    }

    func testStructuralUndoRestoresLayerStack() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        doc.addLayer()
        doc.addLayer()
        XCTAssertEqual(doc.layers.count, 3)

        doc.deleteLayer(at: 2)
        XCTAssertEqual(doc.layers.count, 2)

        doc.undo()
        XCTAssertEqual(doc.layers.count, 3, "撤销应把图层加回来")
        XCTAssertEqual(doc.layers.map(\.name), ["图层 1", "图层 2", "图层 3"])
    }

    func testMultipleUndoStepsUnwindInOrder() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        func drawRed(at x: Int) {
            let rect = CGRect(x: CGFloat(x), y: 0, width: 8, height: 8)
            let before = doc.capturePatch(layerID: layer.id, rect: rect)
            layer.canvas.context.setFillColor(RGBA.red.cgColor)
            layer.canvas.context.fill(rect)
            doc.commitPatch(title: "方块", layerID: layer.id, rect: rect, before: before)
        }

        drawRed(at: 2)
        drawRed(at: 14)
        drawRed(at: 26)

        doc.undo()
        assertColor(layer.canvas.pixel(at: CGPoint(x: 29, y: 3)), .white, "撤一步:第三个方块消失")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 17, y: 3)), .red, "撤一步:第二个方块还在")

        doc.undo()
        assertColor(layer.canvas.pixel(at: CGPoint(x: 17, y: 3)), .white, "撤两步:第二个方块也消失")

        doc.undo()
        assertColor(layer.canvas.pixel(at: CGPoint(x: 5, y: 3)), .white, "撤三步:全部回原样")
    }

    // MARK: - 图层

    func testAddAndDeleteLayer() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        doc.addLayer()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.selectedLayerIndex, 1, "新建图层后应选中它")

        doc.deleteLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 1)
    }

    func testCannotDeleteLastLayer() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        doc.deleteLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 1, "至少要留一层")
    }

    func testHiddenLayerDoesNotAppearInComposite() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        doc.markDirty()

        assertColor(compositePixel(doc, x: 10, y: 10), .red, "可见图层应出现在合成里")

        doc.setLayerVisible(0, false)
        assertTransparent(compositePixel(doc, x: 10, y: 10), "隐藏后合成里不应再有该层像素")
    }

    func testLayerOrderAffectsComposite() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20), background: .white)
        guard let bottom = doc.selectedLayer else { return XCTFail("缺图层") }
        bottom.canvas.context.setFillColor(RGBA.red.cgColor)
        bottom.canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))

        doc.addLayer()
        guard let top = doc.selectedLayer else { return XCTFail("缺图层") }
        top.canvas.context.setFillColor(RGBA.blue.cgColor)
        top.canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        doc.markDirty()

        assertColor(compositePixel(doc, x: 10, y: 10), .blue, "上层应盖住下层")
    }

    // MARK: - 变换

    func testRotateSwapsDimensions() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 20))
        doc.rotateDocument(clockwise: true)
        XCTAssertEqual(doc.size, CGSize(width: 20, height: 40))
        XCTAssertEqual(doc.layers[0].canvas.pixelSize, CGSize(width: 20, height: 40))
    }

    func testRotateMovesContent() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 20), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        doc.markDirty()

        doc.rotateDocument(clockwise: true)
        // 顺时针转 90°:左下角 → 左上角
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 2, y: 36)), .red, "顺时针旋转后红色应跑到左上")
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 2, y: 2)), .white, "原位置应变白")
    }

    func testRotateCounterClockwiseMovesContent() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 20), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        doc.markDirty()

        doc.rotateDocument(clockwise: false)
        // 逆时针转 90°:左下角 → 右下角
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 18, y: 3)), .red, "逆时针旋转后红色应跑到右下")
    }

    func testFlipHorizontalMirrorsContent() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 20), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 8, height: 20))   // 左侧竖条
        doc.markDirty()

        doc.flipDocument(horizontal: true)
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 36, y: 10)), .red, "水平翻转后红条应在右侧")
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 3, y: 10)), .white, "原位置应变白")
    }

    func testFlipVerticalMirrorsContent() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 40), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 8))   // 底部横条
        doc.markDirty()

        doc.flipDocument(horizontal: false)
        assertColor(doc.layers[0].canvas.pixel(at: CGPoint(x: 10, y: 36)), .red, "垂直翻转后红条应在顶部")
    }

    func testResizeDocumentScalesLayers() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 20))
        doc.resizeDocument(to: CGSize(width: 80, height: 40))
        XCTAssertEqual(doc.size, CGSize(width: 80, height: 40))
        XCTAssertEqual(doc.layers[0].canvas.pixelSize, CGSize(width: 80, height: 40))
    }

    // MARK: - 导入

    func testImportImageCreatesNewLayer() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40))
        let src = BitmapCanvas(pixelSize: CGSize(width: 10, height: 10))
        src.context.setFillColor(RGBA.green.cgColor)
        src.context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let image = src.image()!

        doc.importLayer(image: image, name: "导入")
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.layers.last?.name, "导入")
    }

    // MARK: - 笔刷 / 橡皮

    func testBrushStrokeMarksPixels() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        var settings = BrushSettings()
        settings.size = 6
        settings.color = .black

        BrushRenderer.stroke(context: layer.canvas.context,
                             points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
                             settings: settings)

        assertColor(layer.canvas.pixel(at: CGPoint(x: 25, y: 25)), .black, "笔迹中点")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 50, y: 50)), .white, "笔迹外")
    }

    func testEraserUsesMaskToClearPixels() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }

        // 先铺满黑,再用遮罩擦掉中间
        layer.canvas.context.setFillColor(RGBA.black.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))

        let mask = BitmapCanvas(pixelSize: doc.size)
        mask.context.setFillColor(RGBA.black.cgColor)
        mask.context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        layer.canvas.applyMask(mask.image()!)

        assertTransparent(layer.canvas.pixel(at: CGPoint(x: 20, y: 20)), "遮罩区域应被擦成透明")
        assertColor(layer.canvas.pixel(at: CGPoint(x: 2, y: 2)), .black, "遮罩外应保留黑色")
    }

    // MARK: - 项目文件往返

    func testProjectFileRoundTrip() throws {
        let doc = PaintDocument(size: CGSize(width: 30, height: 30), background: .white)
        guard let layer = doc.selectedLayer else { return XCTFail("缺图层") }
        layer.canvas.context.setFillColor(RGBA.red.cgColor)
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 15, height: 30))
        doc.addLayer()
        doc.layers[1].name = "第二层"

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("winpaint-test-\(UUID().uuidString).winpaint")
        defer { try? FileManager.default.removeItem(at: url) }

        try ProjectFile.write(document: doc, to: url)

        let restored = PaintDocument(size: CGSize(width: 10, height: 10))
        try ProjectFile.read(from: url, into: restored)

        XCTAssertEqual(restored.size, CGSize(width: 30, height: 30))
        XCTAssertEqual(restored.layers.count, 2)
        XCTAssertEqual(restored.layers[1].name, "第二层")
        assertColor(restored.layers[0].canvas.pixel(at: CGPoint(x: 5, y: 15)), .red, "红色区域应完整还原")
    }
}
