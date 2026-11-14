import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 文件读写错误
enum FileServiceError: LocalizedError {
    case cannotCreateDestination
    case writeFailed
    case readFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestination: return "无法创建输出文件"
        case .writeFailed: return "写入失败"
        case .readFailed: return "读取失败"
        }
    }
}

/// `.winpaint` 项目格式:JSON 元数据 + 每层一张 base64 PNG。
/// 目的是把多图层结构完整往返,这是位图格式做不到的。
@MainActor
enum ProjectFile {
    static let utType = UTType(exportedAs: "com.andershsueh.winpaint", conformingTo: .package)

    private struct LayerPayload: Codable {
        var name: String
        var visible: Bool
        var opacity: Double
        var pngBase64: String
    }

    private struct Payload: Codable {
        var formatVersion: Int
        var width: Int
        var height: Int
        var selectedLayer: Int
        var layers: [LayerPayload]
    }

    static func write(document: PaintDocument, to url: URL) throws {
        let layers = document.layers.map { layer -> LayerPayload in
            LayerPayload(name: layer.name,
                         visible: layer.isVisible,
                         opacity: layer.opacity,
                         pngBase64: Self.pngBase64(layer.canvas.image()))
        }
        let payload = Payload(formatVersion: 1,
                              width: Int(document.size.width),
                              height: Int(document.size.height),
                              selectedLayer: document.selectedLayerIndex,
                              layers: layers)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    /// 把位图编码成 base64 PNG
    private static func pngBase64(_ image: CGImage?) -> String {
        guard let image else { return "" }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return ""
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return "" }
        return (data as Data).base64EncodedString()
    }

    @MainActor
    static func read(from url: URL, into document: PaintDocument) throws {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let size = CGSize(width: payload.width, height: payload.height)

        var layers: [PaintLayer] = []
        for item in payload.layers {
            let canvas = BitmapCanvas(pixelSize: size)
            if let bytes = Data(base64Encoded: item.pngBase64),
               let image = CGImageSourceCreateWithData(bytes as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) {
                canvas.draw(image: image, in: CGRect(origin: .zero, size: size))
            }
            let layer = PaintLayer(name: item.name, canvas: canvas)
            layer.isVisible = item.visible
            layer.opacity = item.opacity
            layers.append(layer)
        }
        guard !layers.isEmpty else { throw FileServiceError.readFailed }

        document.size = size
        document.layers = layers
        document.selectedLayerIndex = min(max(0, payload.selectedLayer), layers.count - 1)
        document.history.clear()
        document.markDirty()
        document.isDirty = false
    }
}
