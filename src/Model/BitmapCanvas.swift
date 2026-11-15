import CoreGraphics
import Foundation

/// 与文档等尺寸的位图层。内部是一个 CGBitmapContext。
///
/// 坐标约定(重要,全项目统一):
/// - 文档坐标系 = Core Graphics 原生坐标系,原点位于**左下角**,y 向上
/// - 因此 `context.makeImage()` 产出的 CGImage 与绘制时的视觉方向一致,可直接叠画
/// - 鼠标/触控坐标(y 向下)转换到文档坐标时,统一用 `docY = height - viewY`
///
/// 这样做的代价是鼠标转换要翻一次 y;换来的是位图、贴图、文字全部不会上下颠倒。
final class BitmapCanvas {
    let context: CGContext
    let pixelSize: CGSize

    init(pixelSize: CGSize) {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        self.pixelSize = CGSize(width: width, height: height)

        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("BitmapCanvas: 无法分配 \(width)x\(height) 位图上下文")
        }
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        self.context = ctx
    }

    /// 导出整层位图
    func image() -> CGImage? {
        context.makeImage()
    }

    /// 清空整层为透明
    func clearAll() {
        context.clear(CGRect(origin: .zero, size: pixelSize))
    }

    /// 填充整层为指定颜色
    func fillAll(with color: CGColor) {
        context.saveGState()
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.restoreGState()
    }

    /// 把矩形夹到画布内,并对齐到整数像素。
    ///
    /// 快照的**尺寸必须和矩形尺寸严格一致** —— 不一致的话 `restore` 会把图拉伸,
    /// 撤销一笔画在画布边缘的笔迹就会恢复出垃圾(以前就踩过:
    /// `snapshot` 越界裁剪后返回的是交集尺寸,`restore` 又按原 rect 拉伸贴回去)。
    func clampedRect(_ rect: CGRect) -> CGRect {
        let bounds = CGRect(origin: .zero, size: pixelSize)
        let r = rect.intersection(bounds)
        guard !r.isEmpty else { return .zero }
        let x = floor(r.minX), y = floor(r.minY)
        let w = ceil(r.maxX) - x, h = ceil(r.maxY) - y
        let integral = CGRect(x: x, y: y, width: w, height: h)
        let out = integral.intersection(bounds)
        return out.isEmpty ? .zero : out
    }

    /// 区域快照。`rect` 为文档坐标(y 向上)。
    /// 返回的 CGImage 已按图像坐标(y 向下)裁好,可直接 `restore` 回原处。
    /// 矩形会被夹到画布内并取整,返回图像尺寸恒等于实际裁到的区域。
    func snapshot(in rect: CGRect) -> CGImage? {
        guard let img = context.makeImage() else { return nil }
        let r = clampedRect(rect)
        guard !r.isEmpty else { return nil }
        // 文档 y 向上 → 图像 y 向下的转换
        let crop = CGRect(x: r.minX, y: pixelSize.height - r.maxY, width: r.width, height: r.height)
        return img.cropping(to: crop)
    }

    /// 把区域快照写回。`rect` 为文档坐标(y 向上)。
    /// 传入 nil 表示"恢复成透明",用于撤销时清除原本不存在的像素。
    func restore(_ patch: CGImage?, in rect: CGRect) {
        context.saveGState()
        if let patch {
            context.setBlendMode(.copy)
            // 用贴图自身的尺寸画 —— 万一尺寸对不上也不会被拉伸成糊的
            context.draw(patch, in: CGRect(origin: rect.origin,
                                           size: CGSize(width: patch.width, height: patch.height)))
        } else {
            context.clear(rect)
        }
        context.restoreGState()
    }

    /// 绘制外部图像到指定矩形(文档坐标,y 向上)。
    func draw(image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// 用一张"遮罩图"擦除本层像素(对应橡皮擦)。
    /// 遮罩中不透明的像素会被扣掉,半透明像素按比例扣减。
    func applyMask(_ mask: CGImage) {
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.draw(mask, in: CGRect(origin: .zero, size: pixelSize))
        context.restoreGState()
    }

    /// 把整层缩放到新尺寸(最近邻之外用高质量插值)。
    func scaled(to newSize: CGSize) -> CGImage? {
        guard let img = context.makeImage() else { return nil }
        let w = max(1, Int(newSize.width.rounded()))
        let h = max(1, Int(newSize.height.rounded()))
        guard let out = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        out.interpolationQuality = .high
        out.draw(img, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        return out.makeImage()
    }

    /// 读取某个文档坐标处的像素。取不到返回 nil。
    ///
    /// 读像素必须知道字节序,所以这里自己开一块 `premultipliedLast | byteOrder32Big`
    /// 的缓冲区(R,G,B,A 顺序确定),不依赖调用方的实现假设。
    func pixel(at point: CGPoint) -> RGBA? {
        let w = Int(pixelSize.width.rounded())
        let h = Int(pixelSize.height.rounded())
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, x < w, y >= 0, y < h else { return nil }
        guard let img = context.makeImage() else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let bufCtx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        bufCtx.setBlendMode(.copy)
        bufCtx.draw(img, in: CGRect(origin: .zero, size: pixelSize))

        // 文档 y 向上,内存行 0 在顶部
        let row = h - 1 - y
        let i = (row * w + x) * 4
        guard buffer.count >= i + 4 else { return nil }
        let r = Double(buffer[i]) / 255
        let g = Double(buffer[i + 1]) / 255
        let b = Double(buffer[i + 2]) / 255
        let a = Double(buffer[i + 3]) / 255
        // 预乘还原
        guard a > 0 else { return RGBA(0, 0, 0, 0) }
        return RGBA(min(r / a, 1), min(g / a, 1), min(b / a, 1), a)
    }
}
