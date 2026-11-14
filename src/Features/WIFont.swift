import AppKit
import Foundation
import SwiftUI

/// 字体解析。
///
/// Windows 11 画图整套界面用 Segoe UI(拉丁)+ 微软雅黑(中文),macOS 上都没有。
/// 本机装了 Segoe UI 的话(用户自己装在标准字体目录里)就用真字体渲染,
/// 找不到就退回系统字体(SF Pro + 苹方),界面照样能用、字形也对得上。
///
/// 字体文件**不进仓库**:Segoe UI 和微软雅黑都是微软的版权物,
/// 这里只做「本机装了就在运行时用」,不做任何再分发。
@MainActor
enum WIFont {
    /// 找 Segoe UI(标准字体目录里装了就找得到)。返回 PostScript 名或 nil。
    static var segoeName: String? {
        if let cached = cachedName { return cached }
        for n in ["Segoe UI Semilight", "Segoe UI", "Segoe UI Light"] {
            if NSFont(name: n, size: 14) != nil {
                cachedName = n
                return n
            }
        }
        cachedName = nil
        return nil
    }
    private static var cachedName: String?

    /// 标题栏用的字体 + 竖向微调。
    ///
    /// 原版标题:拉丁是 Segoe UI Semilight(墨量 919 px),中文是实心黑(231 px)。
    /// 系统字体没有 Semilight 这一档,拿 `.light` 顶(墨量 992,比 regular 的
    /// 1106 更接近),中文保持 `.regular` —— 一个 Text 里两段两种字重。
    static func titleFace() -> (latin: Font, cjk: Font, yOffset: CGFloat) {
        if let name = segoeName {
            return (.custom(name, size: 14.25),
                    .system(size: 14.25, weight: .regular),
                    8)
        }
        return (.system(size: 14.25, weight: .light),
                .system(size: 14.25, weight: .regular),
                10)
    }
}

/// 把字符串按「拉丁 / 中日韩」切成段,分别套不同字体。
///
/// 标题栏「文件名 - 画图」这种混排,原版 Windows 是两套字:
/// 拉丁 Segoe UI Semilight、中文微软雅黑实心。macOS 上苹方的字重映射不一样,
/// 整串套一个字重必然一头重一头轻 —— 只能分段。
enum ScriptSplit {
    /// 判断是否中日韩字符(统一表意文字、假名、谚文、全角标点)
    static func isCJK(_ ch: Character) -> Bool {
        guard let u = ch.unicodeScalars.first else { return false }
        switch u.value {
        case 0x1100...0x11FF,   // 谚文字母
             0x2E80...0x303F,   // CJK 部首 + 标点
             0x3040...0x30FF,   // 平假名 / 片假名
             0x3130...0x318F,   // 谚文兼容字母
             0x3400...0x4DBF,   // 扩展 A
             0x4E00...0x9FFF,   // 基本汉字
             0xA960...0xA97F,
             0xAC00...0xD7AF,   // 谚文音节
             0xF900...0xFAFF,   // 兼容汉字
             0xFF00...0xFF60,   // 全角形式
             0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }

    /// 生成混排富文本:拉丁段用 `latin`,CJK 段用 `cjk`
    static func make(_ text: String, latin: Font, cjk: Font) -> AttributedString {
        var out = AttributedString()
        var buffer = ""
        var bufferIsCJK: Bool?

        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            piece.font = (bufferIsCJK ?? false) ? cjk : latin
            out += piece
            buffer = ""
        }

        for ch in text {
            let isCJK = Self.isCJK(ch)
            if let cur = bufferIsCJK, cur != isCJK {
                flush()
            }
            bufferIsCJK = isCJK
            buffer.append(ch)
        }
        flush()
        return out
    }
}
