import AppKit
import SwiftUI

// MARK: - 行 1 · 标题栏
//
// Windows 画图第一行:调色板图标 + 「文件名 - 画图」,右侧自绘 —/□/✕ 三个窗口按钮
// (macOS 原生标题栏整体隐藏,红绿灯不出现,这样才是原版的窗口形态)。

struct TitleBarRow: View {
    let title: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            WIIconView(icon: .palette, size: 20)
                .offset(x: 10, y: 9)

            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WIPaint.ink)
                .offset(x: 37, y: 10)
                .allowsHitTesting(false)

            WindowButtonStrip()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: 32)
        .background {
            WIMica.horizontal(WIMica.chrome)
            WindowDragArea()
            WindowConfigurator()
        }
    }
}

/// 隐藏标题栏后,自己接管窗口拖拽
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 把窗口改成「全尺寸内容视图」:标题栏透明、系统红绿灯隐藏,
/// 内容从窗口最顶端开始 —— 否则 SwiftUI 会留 28pt 顶部安全区,自绘标题行就贴不上顶。
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowConfigView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Windows 画图没有红绿灯,自己画 —/□/✕
        for button in [NSWindow.ButtonType.closeButton,
                       NSWindow.ButtonType.miniaturizeButton,
                       NSWindow.ButtonType.zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
    }
}

// MARK: 窗口按钮

/// Windows 风格的 —/□/✕。原版是灰色线性图标,不是 macOS 的红绿灯。
struct WindowButtonStrip: View {
    @State private var hovered: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            button(.minimize, index: 0) { WinOps.minimize() }
            button(.maximize, index: 1) { WinOps.zoom() }
            button(.close, index: 2) { WinOps.close() }
        }
    }

    private func button(_ glyph: WindowGlyph, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph
                .stroke(Color(white: 0.28), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .frame(width: 58, height: 32)
        .background(hovered == index ? Color.black.opacity(0.06) : .clear)
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
    }
}

@MainActor
enum WinOps {
    static var target: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
    }
    static func minimize() { target?.miniaturize(nil) }
    static func zoom() { target?.zoom(nil) }
    static func close() { target?.performClose(nil) }
}

/// 三个窗口按钮的字形
enum WindowGlyph: Shape {
    case minimize, maximize, close

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch self {
        case .minimize:
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .maximize:
            p.addRoundedRect(in: rect.insetBy(dx: 0.5, dy: 0.5),
                             cornerSize: CGSize(width: 1.5, height: 1.5))
        case .close:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return p
    }
}

// MARK: - 行 2 · 菜单行
//
// 文件 / 编辑 / 查看 + 竖线 + 保存 / 分享 / 撤销 / 重做,右侧喇叭(反馈)与齿轮(设置)。
// 横坐标全部照原版截图的绝对像素排。

struct MenuBarRow: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 左半部分:绝对坐标排版(和原版截图逐像素对齐)
            fileMenu.offset(x: 19)
            editMenu.offset(x: 89)
            viewMenu.offset(x: 159)

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 214, y: 18)

            WIIconView(icon: .save, size: 20)
                .frame(width: 20, height: 20)
                .offset(x: 232, y: 20)
                .onTapGesture { model.save() }
                .help("保存")

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 270, y: 18)

            WIIconView(icon: .share, size: 22)
                .frame(width: 22, height: 22)
                .offset(x: 287, y: 18)
                .onTapGesture { model.share() }
                .help("共享")

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 326, y: 18)

            WIIconView(icon: .undo, size: 22)
                .frame(width: 22, height: 22)
                .offset(x: 345, y: 17)
                .foregroundStyle(WIPaint.inkSoft)
                .onTapGesture { model.undo() }
                .help("撤销")

            WIIconView(icon: .redo, size: 22)
                .frame(width: 22, height: 22)
                .offset(x: 394, y: 17)
                .foregroundStyle(WIPaint.inkSoft)
                .onTapGesture { model.redo() }
                .help("重做")

            // 右半部分:贴右边
            HStack(spacing: 25) {
                WIIconView(icon: .megaphone, size: 24)
                    .frame(width: 24, height: 24)
                    .help("反馈")
                WIIconView(icon: .gear, size: 24)
                    .frame(width: 24, height: 24)
                    .help("设置")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .offset(y: 20)
        }
        .font(.system(size: 14))
        .foregroundStyle(WIPaint.ink)
        .frame(maxWidth: .infinity)
        // 关键:Menu 的固有高度比 56 小,`ZStack` 会被后面的 `.frame(height: 56)`
        // **居中**放置 → 整排绝对坐标全部下移 13px。显式指定 alignment 顶对齐,
        // 让 ZStack 的原点严格等于菜单行顶端(绝对 y=32)。
        .frame(height: 56, alignment: .topLeading)
        .background(WIMica.horizontal(WIMica.chrome))
    }

    private var fileMenu: some View {
        Menu {
            Button("新建") { model.newDocument() }
            Button("打开…") { model.openImage() }
            Button("导入到画布…") { model.importImage() }
            Divider()
            Button("保存") { model.save() }
            Button("另存为…") { model.saveAs() }
            Button("另存为项目…") { model.saveProject() }
            Divider()
            Button("打印…") { model.printDocument() }
            Button("共享") { model.share() }
            Divider()
            Button("设置为桌面背景") { model.setAsDesktopBackground() }
            Button("图像属性…") { model.showingResizeSheet = true }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        } label: {
            // SwiftUI 的 Menu 会把 label 压扁(borderlessButton 样式下高度只有 ~20px,
            // 宽度甚至能被 fixedSize 收到 0),19pt 的汉字会被裁掉。所以 label 只放
            // 一份**透明**文字占位(保留固有尺寸),真正可见的文字另放在 background 层。
            Text("文件")
                .font(.system(size: 19))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("文件")
                .font(.system(size: 19))
                .foregroundStyle(WIPaint.ink)
                .offset(x: 0, y: 21)
        }
    }

    private var editMenu: some View {
        Menu {
            Button("撤销") { model.undo() }
                .disabled(!model.document.history.canUndo)
            Button("重做") { model.redo() }
                .disabled(!model.document.history.canRedo)
            Divider()
            Button("全选") { model.selectAll() }
            Button("取消选择") { model.clearSelection() }
        } label: {
            // SwiftUI 的 Menu 会把 label 压扁(borderlessButton 样式下高度只有 ~20px,
            // 宽度甚至能被 fixedSize 收到 0),19pt 的汉字会被裁掉。所以 label 只放
            // 一份**透明**文字占位(保留固有尺寸),真正可见的文字另放在 background 层。
            Text("编辑")
                .font(.system(size: 19))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("编辑")
                .font(.system(size: 19))
                .foregroundStyle(WIPaint.ink)
                .offset(x: 0, y: 21)
        }
    }

    private var viewMenu: some View {
        Menu {
            Menu {
                Button("放大") { model.controller.setZoom(model.controller.zoom * 1.25) }
                Button("缩小") { model.controller.setZoom(model.controller.zoom / 1.25) }
                Divider()
                Button("实际大小") { model.controller.setZoom(1.0) }
                Button("适应窗口") { model.controller.fitToWindow() }
            } label: {
                Label("缩放", systemImage: "plus.magnifyingglass")
            }
            Toggle("标尺", isOn: $model.controller.showsRulers)
            Toggle("网格线", isOn: $model.controller.showsGrid)
            Divider()
            Toggle("状态栏", isOn: $model.controller.showsStatusBar)
            Toggle("始终显示工具栏", isOn: Binding(
                get: { true }, set: { _ in }
            ))
            Toggle("自动隐藏工具栏", isOn: Binding(
                get: { false }, set: { _ in }
            ))
            Divider()
            Toggle("全屏", isOn: Binding(
                get: { false }, set: { _ in }
            ))
            Toggle("缩略图", isOn: $model.controller.showsLayerPanel)
        } label: {
            // SwiftUI 的 Menu 会把 label 压扁(borderlessButton 样式下高度只有 ~20px,
            // 宽度甚至能被 fixedSize 收到 0),19pt 的汉字会被裁掉。所以 label 只放
            // 一份**透明**文字占位(保留固有尺寸),真正可见的文字另放在 background 层。
            Text("查看")
                .font(.system(size: 19))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("查看")
                .font(.system(size: 19))
                .foregroundStyle(WIPaint.ink)
                .offset(x: 0, y: 21)
        }
    }
}

// MARK: - 行 3 · 功能区
//
// 组顺序、组内排布、组名位置全部照原版:
// 选择 | 图像 | 工具 | 画笔 | 形状 | 颜色 | Copilot | 层
// 横坐标用绝对像素锚定(原版 1484px 宽窗口),窗口变窄时右侧自动压缩。

struct RibbonView: View {
    @Bindable var model: AppModel

    /// 功能区内容区高度(原版 89..194)
    private let contentHeight: CGFloat = 105
    /// 组名行高度(原版 194..225)
    private let labelHeight: CGFloat = 31

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                group(width: 71, label: "选择") { selectContent }
                separator
                group(width: 197, label: "图像") { imageContent }
                separator
                group(width: 170, label: "工具") { toolContent }
                separator
                group(width: 64, label: "画笔") { brushContent }
                separator
                group(width: 310, label: "形状") { shapeContent }
                separator
                group(width: 440, label: "颜色") { colorContent }
                separator
                group(width: 79, label: "Copilot") { copilotContent }
                separator
                group(width: 80, label: "层") { layerContent }

                Spacer(minLength: 0)
            }

            // 原版最右侧有一个展开箭头的 ▾(在组名行上,不是内容区)
            WIIconView(icon: .chevronDown, size: 15)
                .offset(x: 1457, y: 109)
        }
        .frame(height: contentHeight + labelHeight, alignment: .top)
        .background(WIMica.horizontal(WIMica.ribbon))
    }

    // MARK: 组容器

    private func group<Content: View>(width: CGFloat, label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) { content() }
                .frame(width: width, height: contentHeight, alignment: .topLeading)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WIPaint.ink)
                .frame(width: width, height: labelHeight, alignment: .top)
                .padding(.top, 2)
        }
    }

    /// 组间竖分隔线。原版在 x = 71 / 269 / 440 / 505 / 816 / 1257 / 1337,
    /// 纵向从 94 贯到 219(不是只画上半段)。
    private var separator: some View {
        Rectangle()
            .fill(WIPaint.separator)
            .frame(width: 1, height: 126)
            .padding(.top, 5)
    }

    // MARK: 选择(组起点 x=0)

    private var selectContent: some View {
        ZStack(alignment: .topLeading) {
            WIIconView(icon: .selectBracket, size: 30)
                .offset(x: 21, y: 31)
                .onTapGesture { model.controller.tool = .select }
            WIIconView(icon: .chevronDown, size: 12)
                .offset(x: 31, y: 70)
        }
    }

    // MARK: 图像(组起点 x=72)

    private var imageContent: some View {
        ZStack(alignment: .topLeading) {
            WIIconView(icon: .crop, size: 24)
                .offset(x: 23, y: 18)
                .onTapGesture { model.controller.tool = .crop }
                .help("裁剪")

            WIIconView(icon: .rotate, size: 24)
                .offset(x: 74, y: 19)
                .onTapGesture { model.handle(.rotateRight) }
                .help("旋转")
            WIIconView(icon: .chevronDown, size: 10)
                .offset(x: 107, y: 26)

            WIIconView(icon: .removeBackground, size: 24)
                .offset(x: 22, y: 69)
                .help("删除背景")

            WIIconView(icon: .flip, size: 24)
                .offset(x: 72, y: 68)
                .onTapGesture { model.handle(.flipHorizontal) }
                .help("翻转")
            WIIconView(icon: .chevronDown, size: 10)
                .offset(x: 107, y: 74)

            WIIconView(icon: .resize, size: 28, grid: 32)
                .offset(x: 148, y: 42)
                .onTapGesture { model.handle(.resize) }
                .help("调整大小")
        }
    }

    // MARK: 工具(组起点 x=270)

    private var toolContent: some View {
        ZStack(alignment: .topLeading) {
            WIIconView(icon: .pencil, size: 24)
                .offset(x: 22, y: 18)
                .onTapGesture { model.controller.tool = .pencil }
                .help("铅笔")
            WIIconView(icon: .fillCan, size: 24)
                .offset(x: 72, y: 18)
                .onTapGesture { model.controller.tool = .fill }
                .help("用颜色填充")
            WIIconView(icon: .textA, size: 24)
                .offset(x: 124, y: 19)
                .onTapGesture { model.controller.tool = .text }
                .help("文本")

            WIIconView(icon: .eraser, size: 24)
                .offset(x: 24, y: 67)
                .onTapGesture { model.controller.tool = .eraser }
                .help("橡皮擦")
            WIIconView(icon: .eyedropper, size: 24)
                .offset(x: 72, y: 69)
                .onTapGesture { model.controller.tool = .eyedropper }
                .help("取色器")
            WIIconView(icon: .magnifier, size: 24)
                .offset(x: 122, y: 69)
                .onTapGesture { model.controller.tool = .magnifier }
                .help("放大镜")
        }
    }

    // MARK: 画笔(组起点 x=441)

    private var brushContent: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(WIPaint.accent, lineWidth: 1.5)
                .frame(width: 37, height: 58)
                .offset(x: 15, y: 27)
            // 原版这个按钮是分体的:画笔和 ▾ 之间有一条分隔线
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 35, height: 1)
                .offset(x: 16, y: 63)
            WIIconView(icon: .brush, size: 26)
                .offset(x: 20, y: 32)
                .onTapGesture { model.controller.tool = .brush }
                .help("画笔")
            WIIconView(icon: .chevronDown, size: 12)
                .offset(x: 28, y: 68)
        }
    }

    // MARK: 形状(组起点 x=506)

    private var shapeContent: some View {
        ZStack(alignment: .topLeading) {
            ShapeGalleryBox(controller: model.controller)
                .offset(x: 11, y: 10)

            // 轮廓样式(左上):圆角方块 + 一支斜插进来的笔
            OutlineStyleGlyph()
                .frame(width: 24, height: 24)
                .offset(x: 191, y: 23)
                .onTapGesture { model.controller.tool = .shape }
                .help("轮廓样式")
            WIIconView(icon: .chevronDown, size: 10)
                .offset(x: 225, y: 27)

            // 填充样式(右):圆角方块 + 波纹
            FillStyleGlyph()
                .frame(width: 30, height: 30)
                .offset(x: 257, y: 37)
                .help("填充样式")

            // 油漆桶(左下)
            ThicknessGlyph()
                .frame(width: 22, height: 22)
                .offset(x: 191, y: 70)
                .help("填充方式")
            WIIconView(icon: .chevronDown, size: 10)
                .offset(x: 225, y: 76)

            WIIconView(icon: .chevronDown, size: 10)
                .offset(x: 268, y: 76)
        }
    }

    // MARK: 颜色(组起点 x=817)

    private var colorContent: some View {
        ZStack(alignment: .topLeading) {
            ColorGroupView(controller: model.controller)
        }
    }

    // MARK: Copilot(组起点 x=1258)

    private var copilotContent: some View {
        ZStack(alignment: .topLeading) {
            CopilotGlyph()
                .frame(width: 30, height: 30)
                .offset(x: 25, y: 34)
                .help("Copilot(不实现)")
            WIIconView(icon: .chevronDown, size: 12)
                .offset(x: 34, y: 67)
        }
    }

    // MARK: 层(组起点 x=1338)

    private var layerContent: some View {
        ZStack(alignment: .topLeading) {
            WIIconView(icon: .layers, size: 26)
                .offset(x: 27, y: 43)
                .onTapGesture { model.controller.showsLayerPanel.toggle() }
                .help("图层")
        }
    }
}

// MARK: - 形状库

/// 形状库:只有一圈很淡的边框,内部和功能区同色(原版并没有白底!)
/// 原版实测:边框 523..681 / 95..193,右侧滚动条在 x 672..676
struct ShapeGalleryBox: View {
    @Bindable var controller: CanvasController

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 6), count: 5)
    private let rows = Array(repeating: GridItem(.fixed(22), spacing: 7), count: 4)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(ShapeKind.allCases) { kind in
                    WIShapeIconView(icon: kind.galleryIcon, size: 20)
                        .foregroundStyle(controller.shapeKind == kind ? WIPaint.accent : WIPaint.ink)
                        // 原版只有「形状」工具激活时才高亮当前形状;默认是铅笔工具,不显示高亮
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(controller.tool == .shape && controller.shapeKind == kind
                                      ? WIPaint.accent.opacity(0.15) : .clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            controller.shapeKind = kind
                            controller.tool = .shape
                        }
                        .help(kind.displayName)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .frame(width: 158, height: 98)
        .overlay(alignment: .trailing) {
            // 原版右侧那根细滚动条
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(0.22))
                .frame(width: 3, height: 38)
                .padding(.trailing, 4)
                .padding(.top, 18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 功能区里的小字形

/// 填充样式:圆角方框 + 左半边四道波纹(原版波纹压在方框左边上)
/// 原版位置:形状组右侧 x 763..793 / y 126..149
struct FillStyleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 30.0
            ctx.scaleBy(x: s, y: s)
            let grey = WIPaint.iconGrey

            // 外壳:圆角方框
            var shell = Path()
            shell.addRoundedRect(in: CGRect(x: 0.8, y: 0.8, width: 28.4, height: 21.4),
                                 cornerSize: CGSize(width: 3.4, height: 3.4))
            ctx.stroke(shell, with: .color(grey), lineWidth: 1.7)

            // 四道波纹(压在方框左半边)
            for i in 0..<5 {
                let y = 4.2 + Double(i) * 2.9
                var w = Path()
                w.move(to: CGPoint(x: 1.6, y: y))
                w.addCurve(to: CGPoint(x: 21, y: y),
                           control1: CGPoint(x: 6.5, y: y + 2.0), control2: CGPoint(x: 11, y: y - 2.0))
                w.addCurve(to: CGPoint(x: 21, y: y),
                           control1: CGPoint(x: 16, y: y + 2.0), control2: CGPoint(x: 18.5, y: y - 2.0))
                ctx.stroke(w, with: .color(grey), lineWidth: 1.4)
            }
        }
    }
}

/// 轮廓样式:圆角方框 + 一支从右上斜插进来的笔
/// 原版位置:形状组左上 x 699..719 / y 113..128
struct OutlineStyleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24.0
            ctx.scaleBy(x: s, y: s)
            let grey = WIPaint.iconGrey

            // 圆角方框
            var box = Path()
            box.addRoundedRect(in: CGRect(x: 1.8, y: 1.4, width: 14.6, height: 14),
                               cornerSize: CGSize(width: 2.6, height: 2.6))
            ctx.stroke(box, with: .color(grey), lineWidth: 1.6)

            // 斜插进来的笔(两笔:笔杆 + 笔尖那条边)
            var pen = Path()
            pen.move(to: CGPoint(x: 21.2, y: 2.0))
            pen.addLine(to: CGPoint(x: 7.4, y: 14.2))
            ctx.stroke(pen, with: .color(grey), lineWidth: 2.0)

            var tip = Path()
            tip.move(to: CGPoint(x: 8.2, y: 12.6))
            tip.addLine(to: CGPoint(x: 6.0, y: 14.6))
            tip.addLine(to: CGPoint(x: 9.4, y: 14.6))
            ctx.stroke(tip, with: .color(grey), lineWidth: 1.4)
        }
    }
}

/// 填充方式:斜着的油漆桶(菱形)+ 圆角方框 + 一滴颜料
/// 原版位置:形状组左下 x 699..719 / y 161..178
struct ThicknessGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 22.0
            ctx.scaleBy(x: s, y: s)
            let grey = WIPaint.iconGrey

            // 后面的圆角方框
            var box = Path()
            box.addRoundedRect(in: CGRect(x: 2, y: 3, width: 19, height: 15),
                               cornerSize: CGSize(width: 2.4, height: 2.4))
            ctx.stroke(box, with: .color(grey), lineWidth: 1.5)

            // 斜着的桶身(菱形)
            var can = Path()
            can.move(to: CGPoint(x: 7, y: 2.2))
            can.addLine(to: CGPoint(x: 12.6, y: 7.4))
            can.addLine(to: CGPoint(x: 8, y: 14))
            can.addLine(to: CGPoint(x: 2.6, y: 8.2))
            can.closeSubpath()
            ctx.stroke(can, with: .color(grey), lineWidth: 1.7)

            // 桶顶的小尖
            var spout = Path()
            spout.move(to: CGPoint(x: 7, y: 2.2))
            spout.addLine(to: CGPoint(x: 7.4, y: 5.4))
            ctx.stroke(spout, with: .color(grey), lineWidth: 1.4)

            // 颜料滴
            var drop = Path()
            drop.move(to: CGPoint(x: 14.6, y: 9.6))
            drop.addCurve(to: CGPoint(x: 17, y: 14.4),
                          control1: CGPoint(x: 16.2, y: 11.4), control2: CGPoint(x: 17, y: 12.8))
            drop.addCurve(to: CGPoint(x: 12.2, y: 14.4),
                          control1: CGPoint(x: 17, y: 16.0), control2: CGPoint(x: 12.2, y: 16.0))
            drop.addCurve(to: CGPoint(x: 14.6, y: 9.6),
                          control1: CGPoint(x: 12.2, y: 13.0), control2: CGPoint(x: 13.6, y: 11.4))
            drop.closeSubpath()
            ctx.stroke(drop, with: .color(grey), lineWidth: 1.4)
        }
    }
}

/// Copilot 徽标。
///
/// 轮廓是照原版截图(1484×985)里的徽标逐像素描出来的:
/// 30×28,一条折起来的缎带 —— 屋顶横带 + 左侧竖板 + 右侧竖板 + 底部甩出去的尾巴,
/// 中间是镂空的。色板也按原版采样:
/// 屋顶蓝 → 左腿青绿/绿/黄 → 尾巴橙/红 → 右腿紫/品红/粉。
struct CopilotGlyph: View {
    var body: some View {
        ZStack {
            // 底层:整条缎带的竖向渐变
            silhouette
                .fill(LinearGradient(stops: [
                    .init(color: Self.rgb(18, 152, 235), location: 0.00),
                    .init(color: Self.rgb(38, 168, 205), location: 0.28),
                    .init(color: Self.rgb(66, 172, 137), location: 0.36),
                    .init(color: Self.rgb(122, 184, 86), location: 0.46),
                    .init(color: Self.rgb(206, 194, 30), location: 0.61),
                    .init(color: Self.rgb(247, 198, 5), location: 0.68),
                    .init(color: Self.rgb(254, 164, 96), location: 0.75),
                    .init(color: Self.rgb(221, 67, 60), location: 0.86),
                    .init(color: Self.rgb(252, 212, 164), location: 0.96)
                ], startPoint: .top, endPoint: .bottom))

            // 上层:右半边叠紫 → 品红 → 粉,用横向遮罩淡入
            silhouette
                .fill(LinearGradient(stops: [
                    .init(color: Self.rgb(32, 86, 208), location: 0.00),
                    .init(color: Self.rgb(60, 92, 214), location: 0.18),
                    .init(color: Self.rgb(178, 81, 211), location: 0.36),
                    .init(color: Self.rgb(203, 82, 181), location: 0.50),
                    .init(color: Self.rgb(241, 91, 137), location: 0.68),
                    .init(color: Self.rgb(247, 129, 112), location: 0.78)
                ], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.50),
                    .init(color: .white, location: 0.80),
                    .init(color: .white, location: 1.00)
                ], startPoint: .leading, endPoint: .trailing))
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// 描出来的轮廓(30×30 网格,外形 + 镂空的孔)
    private var silhouette: Path {
        var p = Path()
        p.move(to: CGPoint(x: 6, y: 0))
        p.addLine(to: CGPoint(x: 20, y: 0))
        p.addLine(to: CGPoint(x: 20, y: 1))
        p.addLine(to: CGPoint(x: 22, y: 1))
        p.addLine(to: CGPoint(x: 22, y: 3))
        p.addLine(to: CGPoint(x: 23, y: 3))
        p.addLine(to: CGPoint(x: 23, y: 6))
        p.addLine(to: CGPoint(x: 24, y: 6))
        p.addLine(to: CGPoint(x: 24, y: 7))
        p.addLine(to: CGPoint(x: 26, y: 7))
        p.addLine(to: CGPoint(x: 26, y: 8))
        p.addLine(to: CGPoint(x: 29, y: 8))
        p.addLine(to: CGPoint(x: 29, y: 9))
        p.addLine(to: CGPoint(x: 30, y: 9))
        p.addLine(to: CGPoint(x: 30, y: 17))
        p.addLine(to: CGPoint(x: 29, y: 17))
        p.addLine(to: CGPoint(x: 29, y: 20))
        p.addLine(to: CGPoint(x: 28, y: 20))
        p.addLine(to: CGPoint(x: 28, y: 23))
        p.addLine(to: CGPoint(x: 27, y: 23))
        p.addLine(to: CGPoint(x: 27, y: 25))
        p.addLine(to: CGPoint(x: 26, y: 25))
        p.addLine(to: CGPoint(x: 26, y: 26))
        p.addLine(to: CGPoint(x: 25, y: 26))
        p.addLine(to: CGPoint(x: 25, y: 27))
        p.addLine(to: CGPoint(x: 24, y: 27))
        p.addLine(to: CGPoint(x: 24, y: 28))
        p.addLine(to: CGPoint(x: 10, y: 28))
        p.addLine(to: CGPoint(x: 10, y: 27))
        p.addLine(to: CGPoint(x: 9, y: 27))
        p.addLine(to: CGPoint(x: 9, y: 26))
        p.addLine(to: CGPoint(x: 8, y: 26))
        p.addLine(to: CGPoint(x: 8, y: 23))
        p.addLine(to: CGPoint(x: 7, y: 23))
        p.addLine(to: CGPoint(x: 7, y: 21))
        p.addLine(to: CGPoint(x: 5, y: 21))
        p.addLine(to: CGPoint(x: 5, y: 20))
        p.addLine(to: CGPoint(x: 1, y: 20))
        p.addLine(to: CGPoint(x: 1, y: 19))
        p.addLine(to: CGPoint(x: 0, y: 19))
        p.addLine(to: CGPoint(x: 0, y: 11))
        p.addLine(to: CGPoint(x: 1, y: 11))
        p.addLine(to: CGPoint(x: 1, y: 8))
        p.addLine(to: CGPoint(x: 2, y: 8))
        p.addLine(to: CGPoint(x: 2, y: 5))
        p.addLine(to: CGPoint(x: 3, y: 5))
        p.addLine(to: CGPoint(x: 3, y: 3))
        p.addLine(to: CGPoint(x: 4, y: 3))
        p.addLine(to: CGPoint(x: 4, y: 2))
        p.addLine(to: CGPoint(x: 5, y: 2))
        p.addLine(to: CGPoint(x: 5, y: 1))
        p.addLine(to: CGPoint(x: 6, y: 1))
        p.closeSubpath()

        // 中间的孔(逆时针 —— 非零环绕规则下形成镂空)
        p.move(to: CGPoint(x: 17, y: 8))
        p.addLine(to: CGPoint(x: 16, y: 8))
        p.addLine(to: CGPoint(x: 16, y: 9))
        p.addLine(to: CGPoint(x: 15, y: 9))
        p.addLine(to: CGPoint(x: 15, y: 10))
        p.addLine(to: CGPoint(x: 14, y: 10))
        p.addLine(to: CGPoint(x: 14, y: 12))
        p.addLine(to: CGPoint(x: 13, y: 12))
        p.addLine(to: CGPoint(x: 13, y: 16))
        p.addLine(to: CGPoint(x: 12, y: 16))
        p.addLine(to: CGPoint(x: 12, y: 19))
        p.addLine(to: CGPoint(x: 11, y: 19))
        p.addLine(to: CGPoint(x: 11, y: 20))
        p.addLine(to: CGPoint(x: 14, y: 20))
        p.addLine(to: CGPoint(x: 14, y: 19))
        p.addLine(to: CGPoint(x: 15, y: 19))
        p.addLine(to: CGPoint(x: 15, y: 18))
        p.addLine(to: CGPoint(x: 16, y: 18))
        p.addLine(to: CGPoint(x: 16, y: 16))
        p.addLine(to: CGPoint(x: 17, y: 16))
        p.addLine(to: CGPoint(x: 17, y: 12))
        p.addLine(to: CGPoint(x: 18, y: 12))
        p.addLine(to: CGPoint(x: 18, y: 10))
        p.addLine(to: CGPoint(x: 19, y: 10))
        p.addLine(to: CGPoint(x: 19, y: 8))
        p.closeSubpath()
        return p
    }
}
