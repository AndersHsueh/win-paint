import AppKit
import SwiftUI

/// 开发期自截图。
///
/// 用途:本机的屏幕录制权限经常拿不到(`screencapture` 直接报 "could not create image from display"),
/// 但自己渲染自己不需要任何权限 —— `NSView.cacheDisplay(in:to:)` 直接问 AppKit 要位图。
///
/// 用法:
///   WINPAINT_SNAPSHOT=/tmp/shot.png open dist/WinPaint.app
/// 启动后会自动把窗口内容写成 PNG 并退出(设 WINPAINT_SNAPSHOT_EXIT=1 可自动关闭)。
@MainActor
enum DevSnapshot {
    static let pathKey = "WINPAINT_SNAPSHOT"
    static let exitKey = "WINPAINT_SNAPSHOT_EXIT"
    static let sizeKey = "WINPAINT_SNAPSHOT_SIZE"
    static let rulersKey = "WINPAINT_SNAPSHOT_RULERS"
    static let gridKey = "WINPAINT_SNAPSHOT_GRID"
    static let loadKey = "WINPAINT_SNAPSHOT_LOAD"
    static let layersKey = "WINPAINT_SNAPSHOT_LAYERS"

    /// 开发期:截图时把某张图加载进文档,再截图。
    ///
    /// 用途:官网首屏要一张「真在画东西」的图,空白画布没法看。
    /// 用法:`WINPAINT_SNAPSHOT_LOAD=/tmp/demo.png WINPAINT_SNAPSHOT=/tmp/hero.png open dist/WinPaint.app`
    static func applyRequestedDocument(_ document: PaintDocument) {
        guard let raw = ProcessInfo.processInfo.environment[loadKey] else { return }
        let url = URL(fileURLWithPath: raw)
        guard let image = PaintDocument.loadImage(at: url) else {
            NSLog("[WinPaint] 加载演示图失败:%@", raw)
            return
        }
        document.load(image: image, title: url.deletingPathExtension().lastPathComponent)
        NSLog("[WinPaint] 已加载演示图:%@", raw)
    }

    /// 开发期:截图时把某些开关打开,用来肉眼验证它们**不是摆设**、或拍产品图。
    ///
    /// 用法:`WINPAINT_SNAPSHOT_RULERS=1 WINPAINT_SNAPSHOT=/tmp/ruler.png open dist/WinPaint.app`
    static func applyRequestedToggles(_ controller: CanvasController) {
        let env = ProcessInfo.processInfo.environment
        if env[rulersKey] != nil { controller.showsRulers = true }
        if env[gridKey] != nil { controller.showsGrid = true }
        if env[layersKey] != nil { controller.showsLayerPanel = true }
    }

    /// 截图前先把窗口强行设成指定尺寸,方便和原版截图逐像素比对。
    /// 用法:`WINPAINT_SNAPSHOT_SIZE=1484x985`
    static func applyRequestedWindowSize() {
        guard let raw = ProcessInfo.processInfo.environment[sizeKey] else { return }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return }
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        window.setContentSize(NSSize(width: parts[0], height: parts[1]))
    }

    /// 在窗口显示后稍等片刻再截,给 SwiftUI 布局留时间
    static func scheduleIfRequested(delay: TimeInterval = 2.0) {
        guard let path = ProcessInfo.processInfo.environment[pathKey], !path.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: path)
            if ProcessInfo.processInfo.environment[exitKey] != nil {
                NSApp.terminate(nil)
            }
        }
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView else { return }

        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 关键点 1:必须显式调用 `cacheDisplay(in:to:)`。
        // `bitmapImageRepForCachingDisplay` 只是分配缓冲,本身不抓内容。
        let scale = view.window?.backingScaleFactor ?? 1
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)

        guard let cg = rep.cgImage else { return }

        let probe = rep.colorAt(x: 10, y: 10)
        NSLog("[WinPaint] rep %dx%d scale=%.1f cs=%@ hasAlpha=%@ bps=%d spp=%d alphaInfo=%d probe=%@",
              rep.pixelsWide, rep.pixelsHigh, scale,
              rep.colorSpace.localizedName ?? "?",
              rep.hasAlpha ? "yes" : "no",
              rep.bitsPerSample, rep.samplesPerPixel,
              cg.alphaInfo.rawValue,
              probe.map { "\(Int($0.redComponent*255)),\(Int($0.greenComponent*255)),\(Int($0.blueComponent*255)),a\(Int($0.alphaComponent*255))" } ?? "nil")

        // 关键点 2:**必须转成 sRGB 再存**。`cacheDisplay` 抓的是屏幕原生色彩空间
        // (本机是 Display P3),而原版 Windows 截图是 sRGB。直接拿两边的原始数值
        // 比对,饱和色能差到 95(纯红 255,0,0 → 241,77,65),近中性色才只差 1~2 ——
        // 会被误判成"颜色没对齐"。转回 sRGB 后才能逐像素对齐。
        let ctx = CIContext(options: [.outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let ci = CIImage(cgImage: cg)
        guard let srgb = ctx.createCGImage(ci, from: ci.extent) else { return }
        let out = NSBitmapImageRep(cgImage: srgb)

        let probe2 = out.colorAt(x: 10, y: 10)
        NSLog("[WinPaint] 抓图 %dx%d -> %@ probe=%@",
              rep.pixelsWide, rep.pixelsHigh,
              out.colorSpace.localizedName ?? "?",
              probe2.map { "\(Int($0.redComponent*255)),\(Int($0.greenComponent*255)),\(Int($0.blueComponent*255)),a\(Int($0.alphaComponent*255))" } ?? "nil")

        guard let data = out.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("[WinPaint] 快照已保存:%@", path)
        } catch {
            NSLog("[WinPaint] 快照失败:%@", error.localizedDescription)
        }
    }
}
