// 文字扫描台(Swift 侧):按参数批量渲染字符串,输出覆盖率掩码(PNM P5)。
//
// 目的:标题/菜单/组名/状态栏的字体几何(字号、字重、字距、横向缩放)是最耗时的
// 调参项,每次改 SwiftUI 再全量重编译再截图比对,一轮要几分钟。这里把
// 「渲染」从「编译」里拆出来,一次编译渲染几百个候选,交给 Python 打分。
//
// 用法: swiftc -O tools/textprobe.swift -o /tmp/textprobe
//       /tmp/textprobe <spec.json>
// spec.json 形如:
// {
//   "text": "文件",
//   "W": 220, "H": 56,
//   "originX": 19, "originY": 50,     // 文本绘制起点(左上角锚点,基线由字体算)
//   "outDir": "/tmp/sweep_menu",
//   "candidates": [ {"size":15.5,"weight":"light","tracking":0,"scaleX":1.0}, ... ]
// }
//
// 掩码约定:白=有墨(1.0),黑=无墨(0.0)。和 PGM 一致,Python 直接读。

import AppKit
import CoreText
import Foundation

struct Candidate: Decodable {
    var size: Double
    var weight: String
    var tracking: Double
    var scaleX: Double
    /// 可选:PostScript 字体名(如 PingFangSC-UltraLight)。给了就用它,忽略 weight。
    var ps: String?
    /// 可选:字体文件绝对路径(如 Segoe UI 的 ttf)。优先于 ps。
    var path: String?
}

struct Spec: Decodable {
    var text: String
    var W: Int
    var H: Int
    var originX: Double
    var originY: Double
    var outDir: String
    var candidates: [Candidate]
    var label: String?
    /// 可选:分段字体。每一段 {text, ps | path},按顺序拼成一个富文本。
    /// 用来测「拉丁走 Segoe UI + 中文走雅黑」这种混排。
    var ranges: [RangeSpec]?
}

struct RangeSpec: Decodable {
    var text: String
    var ps: String?
    var path: String?
}

func weight(_ name: String) -> NSFont.Weight {
    switch name {
    case "ultraLight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    default: return .regular
    }
}

/// 渲染一张覆盖率掩码:白底黑字,输出 [Double] 0..1(1=全墨)
func renderMask(attributed: NSAttributedString, scaleX: Double,
                W: Int, H: Int, originX: Double, originY: Double) -> [Double] {
    var pixels = [Double](repeating: 0, count: W * H)
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: W, space: cs,
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return pixels }
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let line = CTLineCreateWithAttributedString(attributed)
    // CoreText 是 y 向上坐标系,CGContext 位图默认也是 y 向上(原点左下)。
    // 所以:不要加 scaleBy(y:-1)——那会把字形镜像。
    // 直接把基线移到 device 坐标,device y = H-1-originY(originY 是自上而下的基线行)。
    // 横向缩放以文字左端为锚点。
    ctx.translateBy(x: originX, y: CGFloat(H - 1) - CGFloat(originY))
    ctx.scaleBy(x: CGFloat(scaleX), y: 1)
    ctx.textPosition = CGPoint(x: 0, y: 0)
    CTLineDraw(line, ctx)

    guard let data = ctx.data else { return pixels }
    let buf = data.bindMemory(to: UInt8.self, capacity: W * H)
    // CGContext 位图内存第 0 行 = 图像最上一行(与 PIL/PNG 行序一致),直接照抄
    for i in 0..<(W * H) { pixels[i] = Double(buf[i]) / 255.0 }
    return pixels
}

func renderMask(text: String, font: NSFont, tracking: Double, scaleX: Double,
                W: Int, H: Int, originX: Double, originY: Double) -> [Double] {
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    if tracking != 0 { attrs[.kern] = tracking }
    let attributed = NSAttributedString(string: text, attributes: attrs)
    return renderMask(attributed: attributed, scaleX: scaleX, W: W, H: H,
                      originX: originX, originY: originY)
}

func writePGM(_ pixels: [Double], W: Int, H: Int, to path: String) {
    var bytes = Data()
    bytes.append(contentsOf: Array("P5\n\(W) \(H)\n255\n".utf8))
    for v in pixels { bytes.append(UInt8(max(0, min(255, Int(v * 255 + 0.5))))) }
    try? bytes.write(to: URL(fileURLWithPath: path))
}

// MARK: - 主流程

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("用法: textprobe <spec.json>\n".data(using: .utf8)!)
    exit(2)
}
let specData = try! Data(contentsOf: URL(fileURLWithPath: args[1]))
let spec = try! JSONDecoder().decode(Spec.self, from: specData)

try? FileManager.default.createDirectory(atPath: spec.outDir, withIntermediateDirectories: true)

var lines: [String] = ["file\tsize\tweight\ttracking\tscaleX\tdx\tdy\tinkX0\tinkX1\tinkY0\tinkY1"]
/// 从字体文件加载字体(用于系统里没装、但磁盘上有 ttf/otf 的情况)
func fontFromFile(path: String, size: CGFloat) -> NSFont? {
    guard let data = NSData(contentsOfFile: path) else { return nil }
    guard let provider = CGDataProvider(data: data) else { return nil }
    let descs = CTFontManagerCreateFontDescriptorsFromData(data) as? [CTFontDescriptor] ?? []
    _ = provider
    guard let d = descs.first else { return nil }
    return NSFont(descriptor: d, size: size)
}

for (i, c) in spec.candidates.enumerated() {
    var mask: [Double]
    var fname: String
    if let ranges = spec.ranges, !ranges.isEmpty {
        // 分段字体:每段各自选字体,拼成一个富文本
        let whole = NSMutableAttributedString()
        for r in ranges {
            var f: NSFont
            let rPath = (r.path ?? c.path)
            let rPS = (r.ps ?? c.ps)
            if let p = rPath, !p.isEmpty, let ff = fontFromFile(path: p, size: CGFloat(c.size)) {
                f = ff
            } else if let ps = rPS, !ps.isEmpty, let ff = NSFont(name: ps, size: CGFloat(c.size)) {
                f = ff
            } else {
                f = NSFont.systemFont(ofSize: CGFloat(c.size), weight: weight(c.weight))
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: f,
                .foregroundColor: NSColor.white,
            ]
            if c.tracking != 0 { attrs[.kern] = c.tracking }
            whole.append(NSAttributedString(string: r.text, attributes: attrs))
        }
        mask = renderMask(attributed: whole, scaleX: c.scaleX, W: spec.W, H: spec.H,
                          originX: spec.originX, originY: spec.originY)
        fname = "mixed"
    } else {
        let font: NSFont
        if let p = c.path, !p.isEmpty, let f = fontFromFile(path: p, size: CGFloat(c.size)) {
            font = f
        } else if let ps = c.ps, !ps.isEmpty, let named = NSFont(name: ps, size: CGFloat(c.size)) {
            font = named
        } else {
            font = NSFont.systemFont(ofSize: CGFloat(c.size), weight: weight(c.weight))
        }
        mask = renderMask(text: spec.text, font: font, tracking: c.tracking, scaleX: c.scaleX,
                          W: spec.W, H: spec.H, originX: spec.originX, originY: spec.originY)
        fname = (c.ps ?? (c.path.map { URL(fileURLWithPath: $0).lastPathComponent }) ?? "sys")
            .replacingOccurrences(of: " ", with: "")
    }
    let name = String(format: "%03d_%.2f_%@_tr%.1f_sc%.3f_%@.pgm", i, c.size, c.weight, c.tracking, c.scaleX, fname)
    writePGM(mask, W: spec.W, H: spec.H, to: spec.outDir + "/" + name)

    // 墨迹 bbox(>0.15 视为有墨)
    var x0 = spec.W, x1 = -1, y0 = spec.H, y1 = -1
    for y in 0..<spec.H {
        for x in 0..<spec.W where mask[y * spec.W + x] > 0.15 {
            if x < x0 { x0 = x }; if x > x1 { x1 = x }
            if y < y0 { y0 = y }; if y > y1 { y1 = y }
        }
    }
    lines.append("\(name)\t\(c.size)\t\(c.weight)\t\(c.tracking)\t\(c.scaleX)\t\t\t\(x0)\t\(x1)\t\(y0)\t\(y1)")
}
try! lines.joined(separator: "\n").write(toFile: spec.outDir + "/index.tsv", atomically: true, encoding: .utf8)
print("渲染 \(spec.candidates.count) 个候选 -> \(spec.outDir)")
