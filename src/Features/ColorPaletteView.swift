import AppKit
import SwiftUI

/// 「颜色」组。布局照抄 Windows 画图:
/// 左边主色槽(黑盘 + 蓝色高亮环),下面副色槽(白盘 + 灰环);
/// 中间 2×10 直径 20 的圆形色板,再下面一行 10 个空的自定义色位;最右是彩虹轮。
///
/// 全部坐标以组内容区左上角为原点,数值取自原版截图的绝对像素。
struct ColorGroupView: View {
    @Bindable var controller: CanvasController
    @State private var showingPicker = false

    /// 原版色板(截图逐格采样):第一行深色、第二行浅色
    private static let palette: [RGBA] = [
        // 第 1 行
        RGBA(0, 0, 0), RGBA(0.498, 0.498, 0.498), RGBA(0.533, 0, 0.082), RGBA(0.929, 0.110, 0.141),
        RGBA(1, 0.498, 0.153), RGBA(1, 0.949, 0), RGBA(0.133, 0.694, 0.298), RGBA(0, 0.635, 0.910),
        RGBA(0.247, 0.282, 0.800), RGBA(0.639, 0.286, 0.643),
        // 第 2 行
        // 第二行是原版浅色行,数值逐格取自截图:
        // 白 / 灰25% (195,195,195) / 棕 (185,122,87) / 玫瑰 (255,174,201) / 金 (255,201,14)
        // 浅黄 (239,228,176) / 柠檬绿 (181,230,29) / 浅青 (153,217,234) / 蓝灰 (112,146,190) / 薰衣草 (200,191,231)
        RGBA(1, 1, 1), RGBA(0.765, 0.765, 0.765), RGBA(0.725, 0.478, 0.341), RGBA(1, 0.682, 0.788),
        RGBA(1, 0.788, 0.055), RGBA(0.937, 0.894, 0.690), RGBA(0.710, 0.902, 0.114), RGBA(0.600, 0.851, 0.918),
        RGBA(0.439, 0.573, 0.745), RGBA(0.784, 0.749, 0.906),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 主色槽:黑盘(29.12)+ 蓝色高亮环(40)
            primaryWell
                .offset(x: 14.05, y: 11.1)

            // 副色槽:白盘 + 灰环
            secondaryWell
                .offset(x: 20.5, y: 66)

            // 2×10 色板(行距 30)
            ForEach(0..<20, id: \.self) { i in
                let row = i / 10
                let col = i % 10
                swatch(Self.palette[i], row: row, col: col)
                    .offset(x: 70 + CGFloat(col) * 30, y: 15 + CGFloat(row) * 30)
            }

            // 一行 10 个空自定义色位
            ForEach(0..<10, id: \.self) { col in
                WIPaletteTile(name: "slot-c\(col)")
                    .offset(x: 70 + CGFloat(col) * 30, y: 75)
            }

            // 彩虹轮
            ColorWheelIcon()
                .offset(x: 384, y: 39)
                .onTapGesture { showingPicker = true }
                .help("编辑颜色")
        }
        .frame(width: 440, height: 107, alignment: .topLeading)
        .popover(isPresented: $showingPicker) {
            ColorPicker("选择颜色", selection: Binding(
                get: { controller.primaryColor.color },
                set: { newValue in
                    // SwiftUI 的 Color 没有分量访问器,借 NSColor 转一手
                    let ns = NSColor(newValue)
                    controller.primaryColor = RGBA(
                        Double(ns.redComponent),
                        Double(ns.greenComponent),
                        Double(ns.blueComponent),
                        Double(ns.alphaComponent)
                    )
                }
            ), supportsOpacity: false)
            .padding(12)
            .frame(width: 240)
        }
    }

    /// 主色槽。黑色圆盘 + 蓝色高亮环。
    ///
    /// 全部参数都是对原版截图做**逐像素反解**出来的(别凭感觉调):
    /// - 槽心在 (852.0, 120.5)。原版黑盘在 y=120 那一行的覆盖率剖面是
    ///   `x=837 56% | x=838..865 100% | x=866 56%` —— 硬边圆,半径 14.56,
    ///   所以 frame = 29.12(不是 29.1,差 0.5px 会让边缘像素整体错半格)。
    /// - 蓝环是一条宽 1.32 的细环,半径区间 [18.68, 20.0],环芯色 **(13,111,194)**。
    ///   `strokeBorder` 是向内收缩的,所以外沿 = frame/2 → frame 取 40.0、
    ///   lineWidth 取 1.32,环带正好落在 [18.68, 20.0]。
    /// - 原版黑盘在**竖直方向**比水平方向多一圈柔灰晕(竖直 r=15 处还有 31% 灰),
    ///   水平方向则是硬边。这个各向异性还没复刻,见 wiki。
    private var primaryWell: some View {
        ZStack {
            Circle()
                .fill(controller.primaryColor.color)
                .frame(width: 29.12, height: 29.12)
                .offset(x: 0.5)
            Circle()
                .strokeBorder(Color(red: 13.0 / 255.0, green: 111.0 / 255.0,
                                    blue: 194.0 / 255.0),
                              lineWidth: 1.32)
                .frame(width: 40.0, height: 40.0)
        }
        .frame(width: 41.0, height: 41.0)
        .contentShape(Circle())
        .onTapGesture { showingPicker = true }
        .help("主色(点击选择)")
    }

    /// 副色槽
    private var secondaryWell: some View {
        Circle()
            .fill(controller.secondaryColor.color)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(Color(white: 0.62), lineWidth: 1.6))
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .onTapGesture {
                let tmp = controller.primaryColor
                controller.primaryColor = controller.secondaryColor
                controller.secondaryColor = tmp
            }
            .help("副色(点击与主色互换)")
    }

    /// 色块。原版每个色块外面都有一圈 2px 的边。
    ///
    /// 现在色块整体是抠出来的位图(见 `WIPaletteTile`),下面这套解析规则留作档案:
    /// 原版色块是**三层同心圆** —— 本体(半径 8)→ 本体×0.89(半径 9)→
    /// 描边色(半径 10)。0.89 是逐像素实测的,8 种颜色全对:
    /// 红 (237,28,36)→(211,25,32)、橙 (255,127,39)→(227,113,35)、
    /// 黄 (255,242,0)→(227,215,0)、绿 (34,177,76)→(30,158,68)、
    /// 天蓝 (0,162,232)→(0,144,207)、白 (255,255,255)→(227,227,227)。
    /// 描边色 = 本色 × 0.23 + 中性灰 140 × 0.77
    /// (红 (237,28,36)→(162,114,114)、绿 (34,177,76)→(116,147,124)、
    ///  黄 (255,242,0)→(166,162,106))—— 但 45° 对角线上原版是 (160,73,76),
    /// 公式给不出,所以整块抠成位图。

    private func swatch(_ color: RGBA, row: Int, col: Int) -> some View {
        WIPaletteTile(name: "swatch-r\(row)c\(col)")
            .contentShape(Circle())
            .onTapGesture { controller.primaryColor = color }
            .contextMenu {
                Button("设为副色") { controller.secondaryColor = color }
                Button("复制颜色值") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(color.hexString, forType: .string)
                }
            }
            .help(color.hexString)
    }
}

/// 色板图块(20×20)。
///
/// 原版色块的边缘在 45° 对角线上是 (160,73,76) 这种「更暗更饱和」的暗红,
/// 正上/正右方向却是 (162,116,117) 的中性灰边 —— 这是原图缩放/锐化留下的
/// 通道相关残留(纯色 (237,28,36) 不可能混出 R=160),任何解析公式都复刻不出来。
/// 所以直接抠成位图,由 `tools/extract-palette.py` 从原版截图生成,
/// 和 Resources/colorwheel.png、Resources/icons/copilot_badge.png 同一套路。
///
/// 抠取规则:纯 Mica 底色的像素 alpha=0(运行时用 App 自己的底色透出来),
/// 其余像素原样拷贝。位图按 1:1 显示(`interpolation(.none)`),不做任何缩放。
struct WIPaletteTile: View {
    let name: String

    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = Self.cache[name] { return cached }
        var img: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "palette") {
            img = NSImage(contentsOf: url)
        }
        if img == nil {
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // src/Features
                .deletingLastPathComponent()   // src
                .deletingLastPathComponent()   // 仓库根
            img = NSImage(contentsOf: repoRoot.appendingPathComponent("Resources/palette/\(name).png"))
        }
        if let img { Self.cache[name] = img }
        return img
    }

    var body: some View {
        Group {
            if let img = Self.image(name) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: img.size.width, height: img.size.height)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
        }
    }
}

/// 彩虹轮图标(对应 Windows 画图的「编辑颜色」按钮)
///
/// 原版是一张 34×34 的资源图,不是能推出来的矢量:
/// 色相环上还有一圈明暗过渡(同一半径 V 值最大差 30),右上角压着 ⊕ 徽标,
/// 解析重画(SV 锥 / 径向渐变)只能逼近到 Δ5~15,32px 下仍看得出偏差。
/// Windows 自己也是把这张图当资源发布的,所以这里直接用从原版截图抠下来的位图,
/// 由 `tools/extract-wheel.py` 生成,叠回功能区后与原版逐像素一致(meanΔ ≈ 0)。
struct ColorWheelIcon: View {
    /// 资源图。app 运行时从 bundle 取;`swift run` / 单元测试下回退到源码树。
    static let asset: NSImage? = {
        if let url = Bundle.main.url(forResource: "colorwheel", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            dumpInfo(img, url)
            return img
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // src/Features
            .deletingLastPathComponent()   // src
            .deletingLastPathComponent()   // 仓库根
        let url = repoRoot.appendingPathComponent("Resources/colorwheel.png")
        let img = NSImage(contentsOf: url)
        dumpInfo(img, url)
        return img
    }()

    private static func dumpInfo(_ img: NSImage?, _ url: URL) {
        guard let img else {
            NSLog("[WinPaint] colorwheel 加载失败:%@", url.path)
            return
        }
        var info = "size=\(img.size)"
        for rep in img.representations {
            info += " rep=\(rep.pixelsWide)x\(rep.pixelsHigh)@\(rep.size)"
        }
        NSLog("[WinPaint] colorwheel %@ -> %@", url.lastPathComponent, info)
    }

    /// 原版彩虹轮 + ⊕ 徽标的外接框尺寸(实测 34×34)
    private let side: CGFloat = 34

    var body: some View {
        Group {
            if let img = Self.asset {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
    }
}
