import AppKit
import CoreGraphics
import XCTest
@testable import WinPaint

/// 功能层测试:从「用户做了什么」到「文件里落了什么」。
///
/// 核心逻辑测试(PaintCoreTests)盯的是模型内部;这一套盯的是**功能链路**——
/// 画一笔 → 合成 → 导出 PNG → 读回来对不对;建图层 → 存项目 → 重新打开 →
/// 图层栈和像素对不对;旋转/翻转 → 撤销 → 回不回得去。
///
/// 这些是用户真按按钮时走的路径,以前没有自动化覆盖。
@MainActor
final class FunctionalTests: XCTestCase {

    // MARK: - 辅助

    /// 建一张指定尺寸的白底文档
    private func makeDoc(_ w: Int = 120, _ h: Int = 80) -> PaintDocument {
        let doc = PaintDocument(size: CGSize(width: w, height: h))
        doc.reset(to: CGSize(width: w, height: h))
        return doc
    }

    /// 在文档当前图层上画一笔实心黑线
    private func strokeBlackLine(_ doc: PaintDocument,
                                 from: CGPoint, to: CGPoint, width: CGFloat = 4) {
        guard let layer = doc.selectedLayer else { return }
        let ctx = layer.canvas.context
        BrushRenderer.stroke(context: ctx, points: [from, to], settings: BrushSettings(size: width))
    }

    /// 读合成图某点的颜色(坐标是文档坐标系,y 向上)
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

    /// 临时目录(用例结束自动清)
    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("winpaint-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    // MARK: - 文件往返

    /// 画一笔 → 导出 PNG → 读回来,尺寸和像素都要一致
    func testPNGExportRoundTripPreservesPixels() throws {
        let doc = makeDoc(100, 60)
        strokeBlackLine(doc, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 40), width: 6)
        let composite = try XCTUnwrap(doc.composite())

        let url = tempURL("out.png")
        try FileService.savePNG(composite, to: url)

        let reread = try XCTUnwrap(PaintDocument.loadImage(at: url))
        XCTAssertEqual(reread.width, composite.width, "导出后宽度变了")
        XCTAssertEqual(reread.height, composite.height, "导出后高度变了")

        // 把读回来的图再送进文档,逐点比对
        let doc2 = makeDoc(100, 60)
        doc2.load(image: reread, title: "t")
        let a = compositePixel(doc, x: 40, y: 25)
        let b = compositePixel(doc2, x: 40, y: 25)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        if let a, let b {
            XCTAssertEqual(a.r, b.r, accuracy: 0.03, "导出往返后 R 变了")
            XCTAssertEqual(a.g, b.g, accuracy: 0.03, "导出往返后 G 变了")
            XCTAssertEqual(a.b, b.b, accuracy: 0.03, "导出往返后 B 变了")
        }

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 多图层 → 存项目文件 → 重新打开,图层栈(名字/显隐/不透明度)和像素都要回来
    func testProjectFileRoundTripRestoresLayerStack() throws {
        let doc = makeDoc(80, 50)
        doc.addLayer()
        doc.addLayer()
        XCTAssertEqual(doc.layers.count, 3)

        doc.layers[0].name = "底图"
        doc.layers[1].name = "线稿"
        doc.layers[2].name = "标注"
        doc.setLayerVisible(2, false)
        doc.setLayerOpacity(1, 0.5)

        // 在第 2 层画一笔红,这样能验像素也回来了
        let layer = doc.layers[1]
        layer.canvas.context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 5, y: 5, width: 30, height: 20))

        let url = tempURL("p.json")
        try ProjectFile.write(document: doc, to: url)

        let doc2 = makeDoc(80, 50)
        try ProjectFile.read(from: url, into: doc2)

        XCTAssertEqual(doc2.layers.count, 3, "图层数没回来")
        XCTAssertEqual(doc2.layers.map(\.name), ["底图", "线稿", "标注"], "图层名没回来")
        XCTAssertFalse(doc2.layers[2].isVisible, "显隐状态没回来")
        XCTAssertEqual(doc2.layers[1].opacity, 0.5, accuracy: 0.001, "不透明度没回来")
        XCTAssertEqual(doc2.size, CGSize(width: 80, height: 50), "文档尺寸没回来")

        let px = compositePixel(doc2, x: 20, y: 15)
        XCTAssertNotNil(px)
        if let px {
            // 这一层不透明度被设成 0.5,红压白底 → 粉红,G 落在 0.5 附近
            XCTAssertGreaterThan(px.r, 0.7, "红色像素没回来")
            XCTAssertLessThan(px.g, 0.7, "绿色分量不对")
            XCTAssertGreaterThan(px.g, 0.3, "绿色分量不对")
        }

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 坏文件要报错,不能悄悄吞掉
    func testProjectFileReadRejectsGarbage() throws {
        let url = tempURL("bad.json")
        try Data("这不是项目文件".utf8).write(to: url)
        let doc = makeDoc(10, 10)
        XCTAssertThrowsError(try ProjectFile.read(from: url, into: doc))
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 打印合成图里红像素的列范围(诊断用)
    private func dumpProfile(_ doc: PaintDocument, tag: String) {
        guard let img = doc.composite() else { return }
        let w = img.width, h = img.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return }
        ctx.setBlendMode(.copy)
        ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        var cols: [Int] = []
        var rows: Set<Int> = []
        for y in 0..<h {
            for x in 0..<w where buffer[(y * w + x) * 4] > 180 && buffer[(y * w + x) * 4 + 1] < 130 {
                cols.append(x); rows.insert(y)
            }
        }
        print("[诊断]\(tag): 红像素 x[\(cols.min() ?? -1),\(cols.max() ?? -1)] "
              + "y[\(rows.min() ?? -1),\(rows.max() ?? -1)] 共\(cols.count)px")
    }

    // MARK: - 图像操作

    /// 整档旋转:尺寸要交换,而且能撤销回去
    func testRotateDocumentSwapsSizeAndUndoRestoresIt() {
        let doc = makeDoc(120, 80)
        strokeBlackLine(doc, from: CGPoint(x: 100, y: 10), to: CGPoint(x: 100, y: 70), width: 6)

        doc.rotateDocument(clockwise: true)
        XCTAssertEqual(doc.size, CGSize(width: 80, height: 120), "旋转后尺寸没交换")

        doc.undo()
        XCTAssertEqual(doc.size, CGSize(width: 120, height: 80), "撤销后尺寸没回来")
    }

    /// 整档翻转:像素要真的镜像过去
    func testFlipDocumentMirrorsPixels() {
        let doc = makeDoc(100, 60)
        guard let layer = doc.selectedLayer else { return XCTFail("没有图层") }
        // 左上角画一个红块(文档坐标 x=5..15, y=45..55)
        layer.canvas.context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 5, y: 45, width: 10, height: 10))

        dumpProfile(doc, tag: "翻转前")
        doc.flipDocument(horizontal: true)
        dumpProfile(doc, tag: "翻转后")
        // 水平翻转后,红块应该跑到右边
        let right = compositePixel(doc, x: 88, y: 50)
        XCTAssertNotNil(right)
        if let right {
            XCTAssertGreaterThan(right.r, 0.7, "水平翻转后红块没到右边")
        }
        let left = compositePixel(doc, x: 8, y: 50)
        XCTAssertNotNil(left)
        if let left {
            // 白底的 R 通道也是 1.0,判「白」只能看 G/B
            XCTAssertGreaterThan(left.g, 0.9, "水平翻转后左边应该变白")
            XCTAssertGreaterThan(left.b, 0.9, "水平翻转后左边应该变白")
        }

        doc.undo()
        let back = compositePixel(doc, x: 8, y: 50)
        if let back {
            XCTAssertGreaterThan(back.r, 0.7, "撤销后红块没回原位")
            XCTAssertLessThan(back.g, 0.4, "撤销后不该是白底")
        }
    }

    /// 「导入到画布」:外部图片要变成一个新图层
    func testImportImageAddsNamedLayer() throws {
        let src = tempURL("src.png")
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 20, height: 20))
        canvas.context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        canvas.context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        try FileService.savePNG(try XCTUnwrap(canvas.image()), to: src)

        let doc = makeDoc(60, 60)
        let before = doc.layers.count
        doc.importImage(from: src)
        XCTAssertEqual(doc.layers.count, before + 1, "导入后没多出图层")
        XCTAssertEqual(doc.layers.last?.name, "src.png", "导入图层名不对")

        try? FileManager.default.removeItem(at: src.deletingLastPathComponent())
    }

    /// 调整大小:缩放开关要真的生效
    func testResizeDocumentScalesPixelContent() {
        let doc = makeDoc(100, 100)
        guard let layer = doc.selectedLayer else { return XCTFail("没有图层") }
        layer.canvas.context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // 左上角 10×10 红块(文档坐标)
        layer.canvas.context.fill(CGRect(x: 0, y: 90, width: 10, height: 10))

        doc.resizeDocument(to: CGSize(width: 200, height: 200), scaleLayers: true)
        XCTAssertEqual(doc.size, CGSize(width: 200, height: 200), "尺寸没变")

        // 放大两倍后,红块应该占 20×20
        let px = compositePixel(doc, x: 5, y: 195)
        XCTAssertNotNil(px)
        if let px {
            XCTAssertGreaterThan(px.r, 0.7, "放大后红块没跟着放大")
        }
    }

    // MARK: - 图层

    /// 图层的增删改移全套
    func testLayerStackOperations() {
        let doc = makeDoc(40, 40)
        XCTAssertEqual(doc.layers.count, 1)

        doc.addLayer()
        doc.addLayer()
        XCTAssertEqual(doc.layers.count, 3)

        doc.renameLayer(2, to: "第三层")
        XCTAssertEqual(doc.layers[2].name, "第三层")

        doc.setLayerVisible(1, false)
        XCTAssertFalse(doc.layers[1].isVisible)

        doc.setLayerOpacity(1, 0.25)
        XCTAssertEqual(doc.layers[1].opacity, 0.25, accuracy: 0.001)

        doc.moveLayer(from: 0, to: 2)
        XCTAssertEqual(doc.layers.count, 3, "移动后图层数变了")
        XCTAssertEqual(doc.layers[1].name, "第三层", "移动后位置不对")

        doc.deleteLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 2, "删除后图层数不对")
    }

    /// 隐藏图层不参与合成
    func testHiddenLayerDoesNotAffectComposite() {
        let doc = makeDoc(50, 50)
        guard let layer = doc.selectedLayer else { return XCTFail("没有图层") }
        layer.canvas.context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertGreaterThan(compositePixel(doc, x: 25, y: 25)?.r ?? 0, 0.7)

        doc.setLayerVisible(0, false)
        let after = compositePixel(doc, x: 25, y: 25)
        XCTAssertNotNil(after)
        if let after {
            // 唯一一层被隐藏后合成结果是透明的,不是白底
            XCTAssertLessThan(after.a, 0.1, "隐藏图层后应该透明")
        }
    }

    // MARK: - 渲染器(用户真正画出来的东西)

    /// 形状:实心填充要真的填满内部
    func testShapeRendererFillsInterior() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 60, height: 60))
        ShapeRenderer.draw(kind: .rectangle,
                       in: CGRect(x: 10, y: 10, width: 40, height: 40),
                       context: canvas.context,
                       fill: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                       stroke: nil,
                       lineWidth: 1)
        let p = canvas.pixel(at: CGPoint(x: 30, y: 30))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertGreaterThan(p.b, 0.7, "矩形内部没填上")
        }
    }

    /// 形状:无填充时内部不能被染色
    func testShapeRendererWithoutFillLeavesInteriorClear() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 60, height: 60))
        ShapeRenderer.draw(kind: .ellipse,
                       in: CGRect(x: 10, y: 10, width: 40, height: 40),
                       context: canvas.context,
                       fill: nil,
                       stroke: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                       lineWidth: 2)
        let p = canvas.pixel(at: CGPoint(x: 30, y: 30))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertLessThan(p.a, 0.1, "椭圆内部不该有像素")
        }
    }

    /// 文字:要真的画得出可见字形
    func testTextRendererDrawsVisibleGlyphs() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 120, height: 40))
        let attr = TextRenderer.makeAttributed("画", size: 24, color: RGBA(0, 0, 0, 1))
        TextRenderer.draw(attr, at: CGPoint(x: 10, y: 10), in: canvas.context)

        // 整块区域里得有多少非透明像素
        let img = try? XCTUnwrap(canvas.image())
        XCTAssertNotNil(img)
        guard let img else { return }
        var buffer = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &buffer, width: img.width, height: img.height,
                            bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: space, bitmapInfo: info)
        ctx?.draw(img, in: CGRect(origin: .zero, size: CGSize(width: img.width, height: img.height)))
        let painted = buffer.enumerated().filter { $0.offset % 4 == 3 }.filter { $0.element > 20 }.count
        XCTAssertGreaterThan(painted, 30, "文字没画出可见字形(只有 \(painted) 个不透明像素)")
    }

    /// 油漆桶:点一下要真的填出一片
    func testFloodFillPaintsRegion() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 40, height: 40))
        FloodFill.fill(context: canvas.context, seed: CGPoint(x: 20, y: 20),
                       color: RGBA(1, 0, 0, 1), pixelSize: CGSize(width: 40, height: 40))
        let p = canvas.pixel(at: CGPoint(x: 20, y: 20))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertGreaterThan(p.r, 0.7, "填充没生效")
        }
    }

    /// 画笔:走渲染器画一笔,像素要真的黑
    func testBrushStrokeThroughRendererMarksPixels() {
        let canvas = BitmapCanvas(pixelSize: CGSize(width: 60, height: 40))
        BrushRenderer.stroke(context: canvas.context,
                         points: [CGPoint(x: 5, y: 20), CGPoint(x: 55, y: 20)],
                         settings: BrushSettings(size: 6))
        let p = canvas.pixel(at: CGPoint(x: 30, y: 20))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertLessThan(p.r, 0.4, "画笔没落墨")
        }
    }

    // MARK: - 控制器

    /// 缩放:夹取范围 + 文本
    func testControllerZoomClampAndText() {
        let c = CanvasController()
        c.setZoom(0.01)
        XCTAssertGreaterThanOrEqual(c.zoom, 0.05, "缩放没夹到下限")
        c.setZoom(100)
        XCTAssertLessThanOrEqual(c.zoom, 8, "缩放没夹到上限")
        XCTAssertFalse(c.zoomText.isEmpty, "缩放文本是空的")
    }

    /// 状态栏文本格式
    func testStatusTextsFormat() {
        let doc = makeDoc(1200, 630)
        let c = CanvasController()
        c.document = doc
        XCTAssertEqual(c.sizeText, "1200 × 630像素", "尺寸文本不对")
        XCTAssertFalse(c.zoomText.isEmpty)
    }

    // MARK: - 文档生命周期

    /// 新建文档:清空图层和历史
    func testNewDocumentResetsEverything() {
        let doc = makeDoc(50, 50)
        guard let layer = doc.selectedLayer else { return XCTFail("没有图层") }
        let rect = CGRect(x: 0, y: 0, width: 50, height: 50)
        let before = doc.capturePatch(layerID: layer.id, rect: rect)
        strokeBlackLine(doc, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 40, y: 40), width: 5)
        doc.commitPatch(title: "测试笔画", layerID: layer.id, rect: rect, before: before)
        XCTAssertTrue(doc.history.canUndo, "画一笔之后应该能撤销")

        doc.reset(to: CGSize(width: 200, height: 100))
        XCTAssertEqual(doc.size, CGSize(width: 200, height: 100))
        XCTAssertEqual(doc.layers.count, 1, "重置后图层数不对")
        XCTAssertFalse(doc.history.canUndo, "重置后还能撤销")
        XCTAssertFalse(doc.isDirty, "重置后还是脏的")
    }
}
