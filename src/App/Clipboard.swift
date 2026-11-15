import AppKit
import Foundation

/// 系统剪贴板读写(只做图像)。
///
/// 内部复制的内容由 `AppModel` 自己存一份,不走这里 —— 这样在 App 内复制粘贴
/// 不会因为系统剪贴板被别的程序抢走而丢东西。
/// 这里负责的是**跨 App 互通**:从别的 App 贴图进来,或把内容贴到别的 App 去。
enum Clipboard {

    /// 写一张图到系统剪贴板(PNG + TIFF 两种格式,让各家 App 都能认)
    static func write(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.representation(using: .tiff, properties: [:]) {
            pb.setData(tiff, forType: .tiff)
        }
    }

    /// 从系统剪贴板读一张图(PNG 优先,其次 TIFF)
    static func read() -> CGImage? {
        let pb = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pb.data(forType: type) else { continue }
            guard let rep = NSBitmapImageRep(data: data) else { continue }
            if let img = rep.cgImage { return img }
        }
        return nil
    }
}
