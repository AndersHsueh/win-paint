import CoreGraphics
import Foundation

/// 图层。持有一块与文档等尺寸的位图 + 若干显示属性。
final class PaintLayer: Identifiable {
    let id: UUID
    var name: String
    var isVisible: Bool = true
    var opacity: Double = 1.0
    var canvas: BitmapCanvas

    init(id: UUID = UUID(), name: String, canvas: BitmapCanvas) {
        self.id = id
        self.name = name
        self.canvas = canvas
    }

    /// 结构化快照,用于「整档撤销」(增删图层、改文档尺寸这类无法用区域补丁表达的操作)
    struct State {
        var id: UUID
        var name: String
        var isVisible: Bool
        var opacity: Double
        var image: CGImage?
    }

    func captureState() -> State {
        State(id: id, name: name, isVisible: isVisible, opacity: opacity, image: canvas.image())
    }

    func restore(from state: State) {
        name = state.name
        isVisible = state.isVisible
        opacity = state.opacity
        if let img = state.image {
            canvas.draw(image: img, in: CGRect(origin: .zero, size: canvas.pixelSize))
        }
    }

    /// 缩略图(供层面板显示)
    func thumbnail(maxEdge: CGFloat = 88) -> CGImage? {
        guard let img = canvas.image() else { return nil }
        let w = canvas.pixelSize.width
        let h = canvas.pixelSize.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(maxEdge / w, maxEdge / h, 1.0)
        let size = CGSize(width: (CGFloat(w) * scale).rounded(), height: (CGFloat(h) * scale).rounded())
        guard let ctx = CGContext(
            data: nil,
            width: max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // 透明底衬一层白,免得缩略图在浅色 UI 上看不出边界
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.draw(img, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}
