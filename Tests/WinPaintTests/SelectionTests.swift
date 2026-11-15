import AppKit
import CoreGraphics
import XCTest
@testable import WinPaint

/// 第三批功能测试:选区操作(复制 / 剪切 / 粘贴 / 移动 / 裁剪)。
///
/// 这一批对应的是**原版 Windows 画图的基本功**,而复刻到这一版时它们还完全没实现:
/// `CommandGroup(replacing: .pasteboard)` 里只有「全选 / 取消选择」,⌘C / ⌘X / ⌘V 都没绑定;
/// 裁剪只裁当前图层、不改画布尺寸、还不能撤销。
///
/// 顺手也钉住一个**真 bug**:撤销一笔画在画布边缘的笔迹,以前会恢复出垃圾 ——
/// 快照越界裁剪后尺寸和记录里的矩形对不上,贴回去的时候被拉伸了。
@MainActor
final class SelectionTests: XCTestCase {

    // MARK: - 复制

    /// 复制出来的得是**用户看到的那一块**(所有可见图层的合成),不是只当前图层
    func testCopySelectionReturnsWhatUserSees() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40))
        // 底层:红块
        let bottom = doc.selectedLayer!
        bottom.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        bottom.canvas.context.fill(CGRect(x: 5, y: 5, width: 30, height: 30))
        doc.markDirty()

        // 上层:一小块蓝
        doc.addLayer()
        let top = doc.selectedLayer!
        top.canvas.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        top.canvas.context.fill(CGRect(x: 15, y: 15, width: 10, height: 10))
        doc.markDirty()

        let sel = CGRect(x: 10, y: 10, width: 20, height: 20)
        guard let img = SelectionOps.copyImage(document: doc, selection: sel) else {
            return XCTFail("复制没拿到图")
        }
        XCTAssertEqual(img.width, 20)
        XCTAssertEqual(img.height, 20)

        // 裁剪块正中间那一小块应该是上层盖住的蓝
        let p = pixel(in: img, x: 10, y: 10)   // 裁剪块内的图像坐标(y 从上往下)
        XCTAssertEqual(p?.b ?? 0, 1, accuracy: 0.05, "复制没拿到上层的蓝色")
        XCTAssertEqual(p?.r ?? 1, 0, accuracy: 0.05, "复制没拿到上层的蓝色")

        // 四角应该是底层的红
        let corner = pixel(in: img, x: 1, y: 1)
        XCTAssertEqual(corner?.r ?? 0, 1, accuracy: 0.05, "复制没拿到底层的红色")
    }

    /// 空选区 / 越界选区不该复制出东西来
    func testCopyRejectsEmptySelection() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        XCTAssertNil(SelectionOps.copyImage(document: doc, selection: .zero))
        XCTAssertNil(SelectionOps.copyImage(
            document: doc,
            selection: CGRect(x: 100, y: 100, width: 10, height: 10)
        ), "选区完全在画布外也复制出了东西")
    }

    // MARK: - 剪切

    /// 剪切要把选区擦成透明(不是涂成背景色)
    func testCutClearsSelectionToTransparent() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40))
        let layer = doc.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        doc.markDirty()

        SelectionOps.eraseSelection(document: doc, selection: CGRect(x: 10, y: 10, width: 10, height: 10))

        let p = layer.canvas.pixel(at: CGPoint(x: 15, y: 15))
        XCTAssertLessThan(p?.a ?? 1, 0.05, "剪切没把选区擦掉")
    }

    /// 剪切要能撤销
    func testCutIsUndoable() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 40))
        let layer = doc.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        doc.markDirty()

        SelectionOps.eraseSelection(document: doc, selection: CGRect(x: 10, y: 10, width: 10, height: 10))
        XCTAssertTrue(doc.history.canUndo, "剪切没进历史")

        doc.undo()
        let p = layer.canvas.pixel(at: CGPoint(x: 15, y: 15))
        XCTAssertGreaterThan(p?.a ?? 0, 0.9, "撤销剪切没把内容还回来")
        XCTAssertEqual(p?.r ?? 0, 1, accuracy: 0.05, "撤销剪切还回来的颜色不对")
    }

    // MARK: - 粘贴

    /// 粘贴要落在指定位置,尺寸和源图一致
    func testPasteLandsAtRequestedOrigin() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60))
        let img = solidImage(width: 8, height: 6, color: CGColor(srgbRed: 0, green: 0.4, blue: 0.8, alpha: 1))

        let rect = SelectionOps.pasteImage(document: doc, image: img, at: CGPoint(x: 12, y: 20))
        XCTAssertEqual(rect.origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 20, accuracy: 0.001)
        XCTAssertEqual(rect.width, 8, accuracy: 0.001)
        XCTAssertEqual(rect.height, 6, accuracy: 0.001)
    }

    /// 贴进去的像素得是对的
    func testPastePutsTheRightPixelsDown() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60))
        let img = solidImage(width: 8, height: 6, color: CGColor(srgbRed: 0, green: 0.4, blue: 0.8, alpha: 1))

        SelectionOps.pasteImage(document: doc, image: img, at: CGPoint(x: 12, y: 20))

        let layer = doc.selectedLayer!
        let p = layer.canvas.pixel(at: CGPoint(x: 15, y: 22))
        XCTAssertEqual(p?.b ?? 0, 0.8, accuracy: 0.05, "粘贴的像素颜色不对")
        // 落点外面还是原来的白底
        let outside = layer.canvas.pixel(at: CGPoint(x: 30, y: 40))
        XCTAssertGreaterThan(outside?.r ?? 0, 0.9, "粘贴污染了落点以外的像素")
    }

    /// 粘贴要能撤销
    func testPasteIsUndoable() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60))
        let img = solidImage(width: 8, height: 6, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))

        SelectionOps.pasteImage(document: doc, image: img, at: CGPoint(x: 12, y: 20))
        XCTAssertTrue(doc.history.canUndo)

        doc.undo()
        let p = doc.selectedLayer?.canvas.pixel(at: CGPoint(x: 15, y: 22))
        XCTAssertGreaterThan(p?.r ?? 0, 0.9, "撤销粘贴没把原像素还回来")
    }

    /// 粘贴的东西不该跑出画布
    func testPasteStaysInsideCanvas() {
        let doc = PaintDocument(size: CGSize(width: 30, height: 30))
        let img = solidImage(width: 20, height: 20, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))

        let rect = SelectionOps.pasteImage(document: doc, image: img, at: CGPoint(x: 25, y: 25))
        XCTAssertLessThanOrEqual(rect.maxX, 30, "粘贴跑出画布右边了")
        XCTAssertLessThanOrEqual(rect.maxY, 30, "粘贴跑出画布上边了")
    }

    // MARK: - 移动选区内容

    /// 拖动选区:内容搬到新位置,原位被擦掉
    func testMoveSelectionContentRelocatesPixels() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60))
        let layer = doc.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        doc.markDirty()

        let sel = CGRect(x: 10, y: 10, width: 10, height: 10)
        let moved = SelectionOps.moveContent(document: doc, from: sel, to: CGPoint(x: 30, y: 30))

        XCTAssertEqual(moved.origin.x, 30, accuracy: 0.001)
        XCTAssertEqual(moved.origin.y, 30, accuracy: 0.001)

        // 原位空了(擦成透明,白底从下层透出来的是空的)
        XCTAssertLessThan(layer.canvas.pixel(at: CGPoint(x: 15, y: 15))?.a ?? 1, 0.05,
                          "原位没擦干净")
        // 新位置是红的 —— 用绿通道区分,白色背景的 r 也是 1,不能只看 r
        let p = layer.canvas.pixel(at: CGPoint(x: 35, y: 35))
        XCTAssertEqual(p?.g ?? 1, 0, accuracy: 0.05, "新位置没有内容")
        XCTAssertGreaterThan(p?.r ?? 0, 0.9, "新位置不是红的")
    }

    /// 移动要能撤销
    func testMoveSelectionContentIsUndoable() {
        let doc = PaintDocument(size: CGSize(width: 60, height: 60))
        let layer = doc.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        doc.markDirty()

        let sel = CGRect(x: 10, y: 10, width: 10, height: 10)
        SelectionOps.moveContent(document: doc, from: sel, to: CGPoint(x: 30, y: 30))
        doc.undo()

        let back = layer.canvas.pixel(at: CGPoint(x: 15, y: 15))
        XCTAssertEqual(back?.g ?? 1, 0, accuracy: 0.05, "撤销移动没把内容搬回去")
        XCTAssertGreaterThan(back?.r ?? 0, 0.9, "撤销移动搬回来的不是红的")
        // 新位置恢复成原来的白底(不是透明 —— 白底本来就是不透明的)
        let moved = layer.canvas.pixel(at: CGPoint(x: 35, y: 35))
        XCTAssertEqual(moved?.g ?? 0, 1, accuracy: 0.05, "撤销移动没把新位置还原")
    }

    // MARK: - 裁剪

    /// 裁剪是**文档级**操作:画布尺寸要跟着变
    func testCropResizesCanvasToSelection() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 30))
        doc.crop(to: CGRect(x: 10, y: 5, width: 20, height: 10))
        XCTAssertEqual(doc.size.width, 20, accuracy: 0.001)
        XCTAssertEqual(doc.size.height, 10, accuracy: 0.001)
    }

    /// 裁剪要把**所有图层**都裁了,不是只裁当前图层
    func testCropAffectsEveryLayer() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 30))
        doc.addLayer()
        doc.selectedLayer?.canvas.context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        doc.selectedLayer?.canvas.context.fill(CGRect(x: 12, y: 7, width: 5, height: 5))
        doc.markDirty()

        doc.crop(to: CGRect(x: 10, y: 5, width: 20, height: 10))

        for (i, layer) in doc.layers.enumerated() {
            XCTAssertEqual(layer.canvas.pixelSize.width, 20, accuracy: 0.001,
                           "第 \(i) 层没跟着裁")
            XCTAssertEqual(layer.canvas.pixelSize.height, 10, accuracy: 0.001,
                           "第 \(i) 层没跟着裁")
        }
        // 裁剪后那块绿还在(坐标变成 2..7)
        let p = doc.selectedLayer?.canvas.pixel(at: CGPoint(x: 4, y: 4))
        XCTAssertEqual(p?.g ?? 0, 1, accuracy: 0.05, "裁剪把内容裁没了")
    }

    /// 裁剪要能撤销
    func testCropIsUndoable() {
        let doc = PaintDocument(size: CGSize(width: 40, height: 30))
        doc.crop(to: CGRect(x: 10, y: 5, width: 20, height: 10))
        XCTAssertTrue(doc.history.canUndo)

        doc.undo()
        XCTAssertEqual(doc.size.width, 40, accuracy: 0.001)
        XCTAssertEqual(doc.size.height, 30, accuracy: 0.001)
        XCTAssertEqual(doc.layers.first?.canvas.pixelSize.width ?? 0, 40, accuracy: 0.001)
    }

    // MARK: - 回归:边缘笔迹的撤销

    /// **回归测试**。
    ///
    /// 以前 `snapshot(in:)` 越界裁剪后返回的是「交集尺寸」的图,而历史记录里存的
    /// 还是原始矩形 —— 撤销时 `restore` 就把那张小图**拉伸**贴回大矩形里,
    /// 于是画在画布边缘的一笔撤销完,边缘会糊掉 / 出现色块。
    ///
    /// 这里用「整层像素逐字节比对」来钉死:撤销后必须和动手前**一模一样**。
    func testUndoRestoresEdgeStrokeExactly() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        let layer = doc.selectedLayer!

        // 背景铺红 —— 白色背景下拉伸也看不出来,得有色差才测得出
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.fillAll(with: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        doc.markDirty()

        let pristine = allPixels(layer.canvas)

        // 在左下角画一个**超出画布**的黑方块
        let rect = CGRect(x: -5, y: -5, width: 10, height: 10)
        let before = doc.capturePatch(layerID: layer.id, rect: rect)
        layer.canvas.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(rect)
        doc.markDirty()
        doc.commitPatch(title: "边缘笔画", layerID: layer.id, rect: rect, before: before)

        // 画完:角落是黑的
        XCTAssertLessThan(layer.canvas.pixel(at: CGPoint(x: 1, y: 1))?.r ?? 1, 0.2,
                          "边缘笔画没画上")

        doc.undo()

        XCTAssertEqual(allPixels(layer.canvas), pristine,
                       "撤销边缘笔画后像素没有精确还原(快照被拉伸了)")
    }

    /// 历史里记的矩形必须是**夹到画布内**的那个,不能是原始的越界矩形
    func testHistoryRecordsClampedRect() {
        let doc = PaintDocument(size: CGSize(width: 20, height: 20))
        let layer = doc.selectedLayer!
        let rect = CGRect(x: -5, y: -5, width: 10, height: 10)
        let before = doc.capturePatch(layerID: layer.id, rect: rect)
        doc.commitPatch(title: "越界", layerID: layer.id, rect: rect, before: before)

        guard let entry = doc.history.undoStack.last,
              case .patch(let rec) = entry.actions.first else {
            return XCTFail("历史里没有像素级记录")
        }
        XCTAssertEqual(rec.rect, CGRect(x: 0, y: 0, width: 5, height: 5),
                       "历史里记的还是越界矩形")
        XCTAssertEqual(rec.before?.width, 5, "before 快照尺寸和记录对不上")
        XCTAssertEqual(rec.after?.width, 5, "after 快照尺寸和记录对不上")
    }

    // MARK: - AppModel 链路

    /// 复制 → 取消选择 → 粘贴:内容要落到画布左上角
    func testAppModelCopyPasteRoundTrip() {
        let m = AppModel()
        let layer = m.document.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 100, y: 100, width: 50, height: 50))
        m.document.markDirty()

        m.controller.selectionRect = CGRect(x: 100, y: 100, width: 50, height: 50)
        m.copySelection()

        m.controller.selectionRect = nil
        m.paste()

        // 没选区 → 贴到画布左上角
        let p = layer.canvas.pixel(at: CGPoint(x: 10, y: m.document.size.height - 10))
        XCTAssertEqual(p?.r ?? 0, 1, accuracy: 0.05, "粘贴的内容没落到画布左上角")
        // 选区跟着变成粘贴区域
        XCTAssertEqual(m.controller.selectionRect?.width ?? 0, 50, accuracy: 0.001)
    }

    /// 剪切:内容没了,选区还在,接着粘贴能原地放回
    func testAppModelCutThenPasteRestoresInPlace() {
        let m = AppModel()
        let layer = m.document.selectedLayer!
        layer.canvas.context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        layer.canvas.context.fill(CGRect(x: 100, y: 100, width: 50, height: 50))
        m.document.markDirty()

        let sel = CGRect(x: 100, y: 100, width: 50, height: 50)
        m.controller.selectionRect = sel
        m.cutSelection()

        XCTAssertLessThan(layer.canvas.pixel(at: CGPoint(x: 120, y: 120))?.a ?? 1, 0.05,
                          "剪切没擦掉内容")
        XCTAssertEqual(m.controller.selectionRect, sel, "剪切把选区弄丢了")

        m.paste()
        let p = layer.canvas.pixel(at: CGPoint(x: 120, y: 120))
        XCTAssertEqual(p?.g ?? 0, 1, accuracy: 0.05, "剪切后粘贴没放回原位")
    }

    /// 菜单里的裁剪要走文档级裁剪
    func testAppModelCropToSelectionResizesCanvas() {
        let m = AppModel()
        m.controller.selectionRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        m.cropToSelection()
        XCTAssertEqual(m.document.size.width, 100, accuracy: 0.001)
        XCTAssertEqual(m.document.size.height, 50, accuracy: 0.001)
        XCTAssertNil(m.controller.selectionRect, "裁剪后选区没清掉")
    }

    // MARK: - 辅助

    /// 造一张纯色图
    private func solidImage(width: Int, height: Int, color: CGColor) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// 读图像像素。`x` / `y` 是**图像坐标**(y 从上往下),跟 CGImage 的内存排布一致。
    private func pixel(in image: CGImage, x: Int, y: Int) -> RGBA? {
        let w = image.width, h = image.height
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        let i = (y * w + x) * 4
        guard buffer.count >= i + 4 else { return nil }
        let r = Double(buffer[i]) / 255, g = Double(buffer[i + 1]) / 255
        let b = Double(buffer[i + 2]) / 255, a = Double(buffer[i + 3]) / 255
        guard a > 0 else { return RGBA(0, 0, 0, 0) }
        return RGBA(min(r / a, 1), min(g / a, 1), min(b / a, 1), a)
    }

    /// 整层的原始字节(逐字节比对用)
    private func allPixels(_ canvas: BitmapCanvas) -> [UInt8] {
        guard let img = canvas.image() else { return [] }
        let w = img.width, h = img.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return [] }
        ctx.setBlendMode(.copy)
        ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        return buffer
    }
}
