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
        registerBundledSegoe()
        for n in ["Segoe UI Semilight", "Segoe UI", "Segoe UI Light"] {
            if NSFont(name: n, size: 14) != nil {
                cachedName = n
                return n
            }
        }
        cachedName = nil
        return nil
    }
    /// 进程级注册「Windows App」自带的 Segoe UI —— 只在进程内生效,不落盘、不进仓库。
    private static func registerBundledSegoe() {
        let dir = "/Applications/Windows App.app/Contents/Resources"
        for f in ["segoeuisl.ttf", "segoeui.ttf", "segoeuil.ttf"] {
            let p = dir + "/" + f
            guard FileManager.default.fileExists(atPath: p) else { continue }
            var err: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: p) as CFURL, .process, &err)
        }
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
                    font(Face.titleCJK),
                    8)
        }
        // 中文段换 15pt Noto 之后,行内最高字面变了,整行基线被顶下去 3px,
        // 拉丁段也跟着下移 —— 所以这里要把整行抬回 3px。
        //
        // 字重必须是 **regular**:App 实测(标题文字区 meanΔ)
        //   14.25 light = 23.26 / 14.25 regular = **15.93** / 14.25 medium = 25.84
        // 扫描台(CoreText 直绘)当时给的结论是 light 更好,完全反了 —— 扫描台的
        // 栅格化路径跟 SwiftUI 不一样,这种地方一律以 App 实测为准。
        return (.system(size: 14.25, weight: .regular),
                font(Face.titleCJK),
                7)
    }
}

// MARK: - 中文字面表

extension WIFont {
    /// 一个界面位置上的中文字面。
    ///
    /// 原版 Windows 画图的中文全部走微软雅黑,macOS 上没有。实测下来:
    /// **没有任何一套字面能通吃所有位置** —— 标题、状态栏、功能区组名、菜单行
    /// 的字号/字重/横向缩放各不相同,每处单独扫出来的最优值差得很远。
    ///
    /// 数值全部来自 `tools/sweep.py` + `tools/textscore.py` 的实测:
    /// 每处都扫了苹方/苹方 Light/Thin/Regular、Hiragino Sans GB、Noto Sans CJK SC
    /// 的各档字重、STHeiti、微软雅黑本体文件,按与原版截图的亮度 meanΔ 排序。
    /// 换字体/字号/字重前先重跑扫描,别凭感觉调。
    struct Face {
        var size: CGFloat
        /// 系统字重(仅当 `ps` 找不到时用)
        var weight: Font.Weight = .regular
        /// PostScript 名。找不到就退回 `weight`
        var ps: String?
        /// 横向缩放,补偿字库宽度差
        var scaleX: CGFloat = 1

        /// 标题栏「画图」。本机装了微软雅黑就用真字体 —— App 实测
        /// Noto Sans CJK SC Light 15pt meanΔ 23.45,**微软雅黑 15pt 是 22.12**。
        /// (苹方 14.25 regular 是 47 —— 差近一倍。)
        static let titleCJK = Face(size: 15, weight: .light, ps: "Microsoft YaHei")

        /// 状态栏「像素」。微软雅黑 14.5pt,App 实测 meanΔ 25.92 → **21.15**;
        /// Noto Sans CJK SC Thin 15.5 是 25.92,14.5 Thin(不换字体)只有 22.28 但
        /// 全局持平。字号很敏感:微软雅黑 14pt 会掉到 25.22。
        static let statusPixelCJK = Face(size: 14.5, weight: .thin, ps: "Microsoft YaHei")

        /// 状态栏「大小」。这一处反倒是苹方 Thin 最准,meanΔ 10.4
        /// (Noto Thin 是 20.6)—— 两处标签原版的字距不同,不能套同一个面。
        static let statusSizeCJK = Face(size: 15, weight: .thin, ps: "PingFangSC-Thin")

        /// 功能区组名。系统 ultraLight 14.5pt + 横向 1.1。
        ///
        /// 扫描台(CoreText 直绘)说 thin 更准,但 **App 实测反过来**:
        /// 换成 ultraLight 之后选择组 4.24→4.20、图像组 2.05→1.84、
        /// 工具组 2.11→1.94、层 1.81→1.76,四个组全降。
        /// 扫描台和 SwiftUI 的字形栅格化路径不同,以 App 实测为准。
        static let groupLabel = Face(size: 14.5, weight: .thin, scaleX: 1.1)

        /// 菜单行汉字。系统 ultraLight 19pt,meanΔ 18.5(light 是 19.7)。
        static let menuCJK = Face(size: 19, weight: .ultraLight)
    }

    /// 把 Face 变成 SwiftUI Font。`ps` 在本机不存在时退回系统字重。
    static func font(_ f: Face) -> Font {
        if let ps = f.ps, NSFont(name: ps, size: f.size) != nil {
            return .custom(ps, size: f.size)
        }
        return .system(size: f.size, weight: f.weight)
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
