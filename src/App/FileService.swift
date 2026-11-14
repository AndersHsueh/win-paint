import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 文件读写
@MainActor
enum FileService {

    /// 支持打开的图片类型
    static let openableTypes: [UTType] = [.png, .jpeg, .tiff, .bmp, .gif, .image]

    /// 保存为 PNG
    static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FileServiceError.cannotCreateDestination
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw FileServiceError.writeFailed
        }
    }

    static func savePNG(_ image: CGImage, to url: URL, fallbackExtension: String = "png") throws {
        var target = url
        if target.pathExtension.isEmpty {
            target = target.appendingPathExtension(fallbackExtension)
        }
        try savePNG(image, to: target)
    }

    /// 打开面板
    static func chooseOpenImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = openableTypes
        panel.message = "选择要打开的图片"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 保存面板
    static func chooseSaveLocation(suggestedName: String, defaultExtension: String = "png") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultExtension.isEmpty ? suggestedName : "\(suggestedName).\(defaultExtension)"
        panel.message = "保存图片"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 项目文件(保留图层结构)
    static func chooseSaveProject(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [ProjectFile.utType]
        panel.nameFieldStringValue = "\(suggestedName).winpaint"
        panel.message = "保存项目(保留图层)"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseOpenProject() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [ProjectFile.utType]
        panel.message = "打开项目"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
