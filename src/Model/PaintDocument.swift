import CoreGraphics
import Foundation
import ImageIO
import Observation

/// 画作文档。持有图层栈、尺寸、历史。
///
/// 坐标系统一为 Core Graphics 原生(原点左下,y 向上),详见 `BitmapCanvas` 的说明。
@MainActor
@Observable
final class PaintDocument {
    /// 文档尺寸(像素)
    var size: CGSize
    /// 图层栈,index 0 = 最底层
    var layers: [PaintLayer]
    /// 当前选中图层下标
    var selectedLayerIndex: Int = 0
    /// 撤销/重做
    let history = HistoryManager()
    /// 是否有未保存修改
    var isDirty: Bool = false
    /// 已保存到哪个文件
    var fileURL: URL?
    /// 文档标题
    var documentTitle: String = "无标题"

    /// 合成结果缓存。层内容变化时置空。
    private var compositeCache: CGImage?
    /// 渲染版本号。任何影响画面的改动都会 +1,SwiftUI 靠它触发重绘。
    private(set) var renderVersion: Int = 0

    init(size: CGSize = CGSize(width: 1200, height: 630), background: RGBA = .white) {
        self.size = size
        let canvas = BitmapCanvas(pixelSize: size)
        canvas.fillAll(with: background.cgColor)
        self.layers = [PaintLayer(name: "图层 1", canvas: canvas)]
    }

    // MARK: - 渲染

    /// 把所有可见图层合成一张图
    func composite() -> CGImage? {
        if let cache = compositeCache { return cache }
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        for layer in layers where layer.isVisible {
            guard let img = layer.canvas.image() else { continue }
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.draw(img, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
        let result = ctx.makeImage()
        compositeCache = result
        return result
    }

    /// 标记画面已变化
    func markDirty() {
        compositeCache = nil
        encodedSizeCache = nil
        renderVersion &+= 1
    }

    // MARK: - 编码体积

    /// PNG 编码后的字节数。状态栏「大小」显示的就是它 ——
    /// Windows 画图给的是图片文件本身的体积(原版截图里 1200×630 的照片显示 118.2KB),
    /// 不是裸位图的 1200×630×4 = 3.02MB。
    private var encodedSizeCache: Int?

    func encodedByteSize() -> Int {
        if let cached = encodedSizeCache { return cached }
        let bytes = Self.pngByteSize(of: composite())
        encodedSizeCache = bytes
        return bytes
    }

    /// 把 CGImage 编成 PNG,返回字节数。
    static func pngByteSize(of image: CGImage?) -> Int {
        guard let image else { return 0 }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil) else { return 0 }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return 0 }
        return data.length
    }

    var selectedLayer: PaintLayer? {
        layers.indices.contains(selectedLayerIndex) ? layers[selectedLayerIndex] : nil
    }

    func layer(with id: UUID) -> PaintLayer? {
        layers.first { $0.id == id }
    }

    // MARK: - 像素编辑事务

    /// 编辑前抓取区域快照
    func capturePatch(layerID: UUID, rect: CGRect) -> CGImage? {
        layer(with: layerID)?.canvas.snapshot(in: rect)
    }

    /// 把一张图写入图层指定区域(用于合成笔迹缓冲区)
    func applyImage(_ image: CGImage, layerID: UUID, rect: CGRect) {
        guard let layer = layer(with: layerID) else { return }
        layer.canvas.draw(image: image, in: rect)
        markDirty()
    }

    /// 结束一次像素编辑并记入历史
    func commitPatch(title: String, layerID: UUID, rect: CGRect, before: CGImage?) {
        guard let layer = layer(with: layerID) else { return }
        guard let after = layer.canvas.snapshot(in: rect) else { return }
        let record = PatchRecord(layerID: layerID, rect: rect, before: before, after: after)
        history.record(HistoryEntry(title: title, actions: [.patch(record)]))
        markDirty()
        isDirty = true
    }

    // MARK: - 历史

    func undo() {
        guard let entry = history.popUndo() else { return }
        for action in entry.actions.reversed() {
            switch action {
            case .patch(let rec):
                restorePatch(rec, useBefore: true)
            case .structure(let rec):
                restoreSnapshot(rec.before)
            }
        }
        markDirty()
        isDirty = true
    }

    func redo() {
        guard let entry = history.popRedo() else { return }
        for action in entry.actions {
            switch action {
            case .patch(let rec):
                restorePatch(rec, useBefore: false)
            case .structure(let rec):
                restoreSnapshot(rec.after)
            }
        }
        markDirty()
        isDirty = true
    }

    private func restorePatch(_ rec: PatchRecord, useBefore: Bool) {
        guard let layer = layer(with: rec.layerID) else { return }
        let image = useBefore ? rec.before : rec.after
        layer.canvas.restore(image, in: rec.rect)
    }

    private func restoreSnapshot(_ snap: DocumentSnapshot) {
        size = snap.size
        var rebuilt: [PaintLayer] = []
        for state in snap.layers {
            let canvas = BitmapCanvas(pixelSize: snap.size)
            if let img = state.image {
                canvas.draw(image: img, in: CGRect(origin: .zero, size: snap.size))
            }
            let layer = PaintLayer(id: state.id, name: state.name, canvas: canvas)
            layer.isVisible = state.isVisible
            layer.opacity = state.opacity
            rebuilt.append(layer)
        }
        layers = rebuilt
        selectedLayerIndex = layers.isEmpty ? 0 : min(max(0, snap.selectedLayerIndex), layers.count - 1)
    }

    /// 记录一次结构性变更(自动前后快照)
    private func recordStructure(title: String, _ mutate: () -> Void) {
        let before = DocumentSnapshot(document: self)
        mutate()
        let after = DocumentSnapshot(document: self)
        history.record(HistoryEntry(title: title, actions: [.structure(StructureRecord(before: before, after: after))]))
        markDirty()
        isDirty = true
    }

    // MARK: - 图层操作

    func addLayer() {
        recordStructure(title: "新建图层") {
            let canvas = BitmapCanvas(pixelSize: size)
            let layer = PaintLayer(name: "图层 \(layers.count + 1)", canvas: canvas)
            layers.append(layer)
            selectedLayerIndex = layers.count - 1
        }
    }

    func deleteLayer(at index: Int) {
        guard layers.count > 1, layers.indices.contains(index) else { return }
        recordStructure(title: "删除图层") {
            layers.remove(at: index)
            selectedLayerIndex = min(selectedLayerIndex, layers.count - 1)
        }
    }

    /// 把图层从 from 移到 to(0 = 最底层)
    func moveLayer(from: Int, to: Int) {
        guard layers.indices.contains(from), layers.indices.contains(to), from != to else { return }
        recordStructure(title: "调整图层顺序") {
            let layer = layers.remove(at: from)
            layers.insert(layer, at: to)
            selectedLayerIndex = to
        }
    }

    func setLayerVisible(_ index: Int, _ visible: Bool) {
        guard layers.indices.contains(index) else { return }
        layers[index].isVisible = visible
        markDirty()
    }

    func setLayerOpacity(_ index: Int, _ opacity: Double) {
        guard layers.indices.contains(index) else { return }
        layers[index].opacity = opacity
        markDirty()
    }

    func renameLayer(_ index: Int, to name: String) {
        guard layers.indices.contains(index) else { return }
        layers[index].name = name
    }

    func selectLayer(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        selectedLayerIndex = index
    }

    // MARK: - 文档级操作

    /// 调整文档尺寸。所有图层按新尺寸缩放(保持内容比例会变形,故此处为拉伸,另提供保持比例的入口)
    func resizeDocument(to newSize: CGSize, scaleLayers: Bool = true) {
        let clamped = CGSize(width: max(1, newSize.width), height: max(1, newSize.height))
        guard clamped != size else { return }
        recordStructure(title: "调整尺寸") {
            size = clamped
            if scaleLayers {
                for layer in layers {
                    if let scaled = layer.canvas.scaled(to: clamped) {
                        let fresh = BitmapCanvas(pixelSize: clamped)
                        fresh.draw(image: scaled, in: CGRect(origin: .zero, size: clamped))
                        layer.canvas = fresh
                    }
                }
            } else {
                for layer in layers {
                    layer.canvas = BitmapCanvas(pixelSize: clamped)
                }
            }
        }
    }

    /// 清空整个文档并重置历史
    func reset(to newSize: CGSize, background: RGBA = .white) {
        size = newSize
        let canvas = BitmapCanvas(pixelSize: newSize)
        canvas.fillAll(with: background.cgColor)
        layers = [PaintLayer(name: "图层 1", canvas: canvas)]
        selectedLayerIndex = 0
        history.clear()
        compositeCache = nil
        encodedSizeCache = nil
        renderVersion &+= 1
        isDirty = false
    }

    /// 打开一张图片作为新文档
    func load(image: CGImage, title: String) {
        let pixelSize = CGSize(width: image.width, height: image.height)
        size = pixelSize
        let canvas = BitmapCanvas(pixelSize: pixelSize)
        canvas.draw(image: image, in: CGRect(origin: .zero, size: pixelSize))
        layers = [PaintLayer(name: "图层 1", canvas: canvas)]
        selectedLayerIndex = 0
        history.clear()
        compositeCache = nil
        encodedSizeCache = nil
        renderVersion &+= 1
        documentTitle = title
        isDirty = false
    }

    /// 把外部图片作为新图层导入当前画布(对应 Windows 的「导入到画布」)
    func importLayer(image: CGImage, name: String) {
        recordStructure(title: "导入到画布") {
            let canvas = BitmapCanvas(pixelSize: size)
            let drawRect = CGRect(origin: .zero, size: size)
            canvas.draw(image: image, in: drawRect)
            let layer = PaintLayer(name: name, canvas: canvas)
            layers.append(layer)
            selectedLayerIndex = layers.count - 1
        }
    }
}
