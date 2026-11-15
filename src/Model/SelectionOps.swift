import CoreGraphics
import Foundation

/// 选区相关的文档级操作。
///
/// 这块以前整个埋在 `PaintCanvasView`(NSView)里 —— 单测够不着,而它恰恰是最容易出错的一块:
/// 坐标翻反、复制出空白、裁剪只裁一层、撤销恢复出垃圾。
///
/// 抽到模型层之后,菜单、视图、单测共用同一套实现:
/// - 视图只负责"用户在哪儿按下、拖到哪儿",具体的像素操作交给这里
/// - 单测直接调这些函数,不用模拟鼠标事件
///
/// 坐标系提醒:文档坐标是 Core Graphics 原生坐标(原点左下、y 向上)。
@MainActor
enum SelectionOps {

    // MARK: - 复制

    /// 取选区里的画面(所见即所复)。
    ///
    /// 取的是**所有可见图层的合成结果**,不是只看当前图层 —— 用户看到的就是合成的,
    /// 复制出来的也得是他看到的那一块。
    static func copyImage(document: PaintDocument, selection: CGRect) -> CGImage? {
        guard let composite = document.composite() else { return nil }
        let r = selection.intersection(CGRect(origin: .zero, size: document.size)).integral
        guard r.width >= 1, r.height >= 1 else { return nil }
        // composite 是图像坐标(y 向下),文档坐标 y 向上 → 翻一次
        let crop = CGRect(x: r.minX,
                          y: CGFloat(composite.height) - r.maxY,
                          width: r.width,
                          height: r.height)
        return composite.cropping(to: crop)
    }

    // MARK: - 剪切

    /// 擦掉当前图层里选区的内容(剪切用)。
    ///
    /// 只擦当前图层:上面叠着的其它图层不动 —— 这是「图层」语义应有的行为,
    /// 跨图层擦会把用户没选中的图层内容也吃掉。
    static func eraseSelection(document: PaintDocument, selection: CGRect, title: String = "剪切") {
        guard let layer = document.selectedLayer else { return }
        let r = layer.canvas.clampedRect(selection)
        guard !r.isEmpty else { return }
        let before = document.capturePatch(layerID: layer.id, rect: r)

        layer.canvas.context.saveGState()
        layer.canvas.context.setBlendMode(.clear)
        layer.canvas.context.fill(r)
        layer.canvas.context.restoreGState()

        document.markDirty()
        document.commitPatch(title: title, layerID: layer.id, rect: r, before: before)
    }

    // MARK: - 粘贴

    /// 把一张图贴进当前图层,返回落点矩形。
    ///
    /// 落点会被夹回画布内 —— 免得粘上去的东西整块跑到画布外面看不见。
    @discardableResult
    static func pasteImage(document: PaintDocument, image: CGImage, at origin: CGPoint) -> CGRect {
        guard let layer = document.selectedLayer else { return .zero }
        let size = CGSize(width: image.width, height: image.height)
        guard size.width >= 1, size.height >= 1 else { return .zero }

        let bounds = CGRect(origin: .zero, size: document.size)
        var anchor = origin
        if size.width <= bounds.width {
            anchor.x = min(max(anchor.x, bounds.minX), bounds.maxX - size.width)
        }
        if size.height <= bounds.height {
            anchor.y = min(max(anchor.y, bounds.minY), bounds.maxY - size.height)
        }
        let rect = CGRect(origin: anchor, size: size)

        let before = document.capturePatch(layerID: layer.id, rect: rect)
        layer.canvas.draw(image: image, in: rect)
        document.markDirty()
        document.commitPatch(title: "粘贴", layerID: layer.id, rect: rect, before: before)
        return rect
    }

    // MARK: - 移动选区内容

    /// 把选区里的内容搬到新位置,返回新位置的矩形。
    ///
    /// 原位会被擦掉(和原版 Windows 画图一致:拖走的内容不会在原地留下副本)。
    /// 目标位置和原位有重叠时,新内容盖在上面。
    @discardableResult
    static func moveContent(document: PaintDocument, from selection: CGRect, to newOrigin: CGPoint) -> CGRect {
        guard let layer = document.selectedLayer else { return .zero }
        let r = layer.canvas.clampedRect(selection)
        guard !r.isEmpty, let content = layer.canvas.snapshot(in: r) else { return .zero }

        let target = CGRect(origin: newOrigin, size: r.size)
        let bounds = CGRect(origin: .zero, size: layer.canvas.pixelSize)
        let affected = r.union(target).intersection(bounds)
        guard !affected.isEmpty else { return .zero }
        let before = document.capturePatch(layerID: layer.id, rect: affected)

        // 先擦原位
        layer.canvas.context.saveGState()
        layer.canvas.context.setBlendMode(.clear)
        layer.canvas.context.fill(r)
        layer.canvas.context.restoreGState()

        // 再画到新位置
        layer.canvas.draw(image: content, in: target)

        document.markDirty()
        document.commitPatch(title: "移动选区", layerID: layer.id, rect: affected, before: before)
        return target
    }
}
