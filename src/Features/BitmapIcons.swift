import AppKit
import SwiftUI

/// 从原版截图抠下来的 UI 图标(带 alpha)。
///
/// 原版用的是 Segoe MDL2 字形:曲线走向、端点圆角、虚线节奏都很难用 bezier 逼近。
/// 实测手绘的方块比原版窄 27%(14px vs 19px),虚线框因为描边不足 1px 直接被抗锯齿
/// 压成灰色(最暗 114 vs 原版 26)。这些小图标于是直接抠成带 alpha 的 PNG 资源
/// (`tools/extract-icons.py` 生成),原位贴回后与原版逐像素一致。
///
/// 抠图原理:原图是「近黑前景 + 亮背景」,所以
///     alpha = (bg - lum) / (bg - fg),  RGB = fg
/// 这样抗锯齿边缘也能原样保留。
struct WIBitmapIcon: View {
    let name: String

    /// 资源图。app 运行时从 bundle 取;`swift run` / 单元测试下回退到源码树。
    static func image(_ name: String) -> NSImage? {
        if let cached = Self.cache[name] { return cached }
        var img: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "icons") {
            img = NSImage(contentsOf: url)
        }
        if img == nil {
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // src/Features
                .deletingLastPathComponent()   // src
                .deletingLastPathComponent()   // 仓库根
            img = NSImage(contentsOf: repoRoot.appendingPathComponent("Resources/icons/\(name).png"))
        }
        if let img { Self.cache[name] = img }
        return img
    }

    private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let img = Self.image(name) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: img.size.width, height: img.size.height)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
        .allowsHitTesting(false)
    }
}
