import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图像类操作的意图
enum ImageAction {
    case rotateRight
    case rotateLeft
    case flipHorizontal
    case flipVertical
    case resize
    case importImage
    case crop
}

// MARK: - 位图变换

extension BitmapCanvas {
    /// 旋转 90°。返回新画布,不修改自身。
    func rotated(clockwise: Bool) -> BitmapCanvas {
        let oldW = pixelSize.width
        let oldH = pixelSize.height
        let out = BitmapCanvas(pixelSize: CGSize(width: oldH, height: oldW))
        guard let img = image() else { return out }
        let ctx = out.context
        ctx.saveGState()
        if clockwise {
            // (x, y) → (y, oldW - x)
            ctx.translateBy(x: 0, y: oldW)
            ctx.rotate(by: -.pi / 2)
        } else {
            // (x, y) → (oldH - y, x)
            ctx.translateBy(x: oldH, y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: oldW, height: oldH)))
        ctx.restoreGState()
        return out
    }

    /// 镜像。返回新画布,不修改自身。
    func flipped(horizontal: Bool) -> BitmapCanvas {
        let out = BitmapCanvas(pixelSize: pixelSize)
        guard let img = image() else { return out }
        let ctx = out.context
        ctx.saveGState()
        if horizontal {
            ctx.translateBy(x: pixelSize.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        } else {
            ctx.translateBy(x: 0, y: pixelSize.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(img, in: CGRect(origin: .zero, size: pixelSize))
        ctx.restoreGState()
        return out
    }
}

// MARK: - 文档级图像操作

extension PaintDocument {
    /// 整档旋转(所有图层 + 文档尺寸一起转)
    func rotateDocument(clockwise: Bool) {
        let before = DocumentSnapshot(document: self)
        for i in layers.indices {
            layers[i].canvas = layers[i].canvas.rotated(clockwise: clockwise)
        }
        size = CGSize(width: size.height, height: size.width)
        let after = DocumentSnapshot(document: self)
        history.record(HistoryEntry(title: clockwise ? "向右旋转" : "向左旋转",
                                    actions: [.structure(StructureRecord(before: before, after: after))]))
        markDirty()
        isDirty = true
    }

    /// 整档镜像
    func flipDocument(horizontal: Bool) {
        let before = DocumentSnapshot(document: self)
        for i in layers.indices {
            layers[i].canvas = layers[i].canvas.flipped(horizontal: horizontal)
        }
        let after = DocumentSnapshot(document: self)
        history.record(HistoryEntry(title: horizontal ? "水平翻转" : "垂直翻转",
                                    actions: [.structure(StructureRecord(before: before, after: after))]))
        markDirty()
        isDirty = true
    }

    /// 把外部图片作为新图层导入(对应 Windows 的「导入到画布」)
    func importImage(from url: URL) {
        guard let image = ImageIOLoader.load(url: url) else { return }
        let name = url.lastPathComponent
        importLayer(image: image, name: name)
    }

    /// 读取图片文件
    static func loadImage(at url: URL) -> CGImage? {
        ImageIOLoader.load(url: url)
    }
}

/// 图片文件读取(ImageIO,支持 PNG / JPEG / TIFF / BMP / GIF)
enum ImageIOLoader {
    static func load(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
