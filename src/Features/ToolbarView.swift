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
            // 调色板图标是彩色渐变,手绘路径对不上,直接抠原版像素(墨迹 10..29 / 10..28)
            WIBitmapIcon(name: "title_palette")
                .offset(x: 8, y: 7)

            Text(ScriptSplit.make(title,
                             latin: WIFont.titleFace().latin,
                             cjk: WIFont.titleFace().cjk))
                // 原版标题是 Segoe UI Semilight(拉丁)+ 微软雅黑(中文)。
                // macOS 上没有 Segoe UI,拉丁用系统的 light 顶(墨量更接近),
                // 中文保持 regular —— 混排按字种分段套字重,见 ScriptSplit。
                .foregroundStyle(WIPaint.ink)
                .offset(x: 36, y: WIFont.titleFace().yOffset)
                .allowsHitTesting(false)

            WindowButtonStrip()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// Windows 风格的 —/□/✕。原版是纯黑 1px 线性字形(— 12×1、□ 12×12、✕ 12×12),
/// 手绘路径对不上抗锯齿,直接用从原版抠下来的位图。
struct WindowButtonStrip: View {
    @State private var hovered: Int? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 实测墨迹:— x1330..1341/y18,□ x1388..1399/y13..24,✕ x1447..1458/y13..24
            button("title_min", x: 1325, y: 3, index: 0) { WinOps.minimize() }
            button("title_max", x: 1382, y: 3, index: 1) { WinOps.zoom() }
            button("title_close", x: 1440, y: 3, index: 2) { WinOps.close() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func button(_ icon: String, x: CGFloat, y: CGFloat, index: Int,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(hovered == index ? Color.black.opacity(0.06) : .clear)
                    .frame(width: 46, height: 26)
                WIBitmapIcon(name: icon)
            }
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
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
            fileMenu.offset(x: 18)
            editMenu.offset(x: 88)
            viewMenu.offset(x: 158)

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 214, y: 18)

            // 菜单行的保存图标和状态栏的软盘是同一个 Segoe 字形,直接复用抠下来的位图
            WIBitmapIcon(name: "floppy")
                .offset(x: 232, y: 20)
                .onTapGesture { model.save() }
                .help("保存")

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 270, y: 18)

            WIBitmapIcon(name: "menu_share")
                .offset(x: 285, y: 16)
                .onTapGesture { model.share() }
                .help("共享")

            Rectangle().fill(WIPaint.separator)
                .frame(width: 1, height: 26)
                .offset(x: 326, y: 18)

            WIBitmapIcon(name: "menu_undo")
                .offset(x: 343, y: 15)
                .onTapGesture { model.undo() }
                .help("撤销")

            WIBitmapIcon(name: "menu_redo")
                .offset(x: 392, y: 15)
                .onTapGesture { model.redo() }
                .help("重做")

            // 右半部分:贴右边
            // 原版墨迹:喇叭 x 1403..1423 / y 54..71,齿轮 x 1449..1467 / y 53..72
            WIBitmapIcon(name: "menu_megaphone")
                .offset(x: 1397, y: 17)
                .help("反馈")
            WIBitmapIcon(name: "menu_gear")
                .offset(x: 1444, y: 16)
                .help("设置")
        }
        .font(.system(size: 14))
        .foregroundStyle(WIPaint.ink)
        // 必须是 topLeading:.frame(maxWidth:.infinity) 默认是 **居中** 对齐,
        // ZStack 一旦没有贪婪子视图(以前右边那个 HStack 是贪婪的),
        // 整排绝对坐标就会被居中平移 (窗口宽 - ZStack 宽) / 2。
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("文件")
                .font(.system(size: 19, weight: .light))
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
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("编辑")
                .font(.system(size: 19, weight: .light))
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
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.clear)
                .frame(width: 48, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 26)
        .background(alignment: .topLeading) {
            Text("查看")
                .font(.system(size: 19, weight: .light))
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
                group(width: 71, label: "选择", labelX: 21, labelDX: -1, labelDY: 0) { selectContent }
                separator
                group(width: 197, label: "图像", labelX: 85, labelDX: -1, labelDY: -1) { imageContent }
                separator
                group(width: 170, label: "工具", labelX: 70, labelDX: -1, labelDY: -1) { toolContent }
                separator
                group(width: 64, label: "画笔", labelX: 20, labelDX: 0, labelDY: -1) { brushContent }
                separator
                group(width: 310, label: "形状", labelX: 143, labelDX: -1, labelDY: 0) { shapeContent }
                separator
                group(width: 440, label: "颜色", labelX: 205, labelDX: 0, labelDY: -1) { colorContent }
                separator
                group(width: 79, label: "Copilot", labelX: 16, labelScale: 1.09, labelDX: -2) { copilotContent }
                separator
                group(width: 80, label: "层", labelX: 32, labelDX: 0, labelDY: -1) { layerContent }

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

    private func group<Content: View>(width: CGFloat, label: String, labelX: CGFloat,
                                      labelScale: CGFloat = 1.1,
                                      labelDX: CGFloat = 0, labelDY: CGFloat = 0,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) { content() }
                .frame(width: width, height: contentHeight, alignment: .topLeading)
            // 组名按原版绝对坐标摆位(原版是按组宽居中,但中文字宽和原版差几个像素,
            // 居中就会整体偏;直接用绝对左缘最省事)。墨迹高 13px,y 从 199 起。
            Text(label)
                // 组名字面逐处实测:汉字用系统 Thin 15pt + 横向 1.05(meanΔ 10.8);
                // 拉丁(Copilot)沿用原来的 14.5pt ultraLight。
                .font(label.unicodeScalars.allSatisfy { $0.isASCII } ? .system(size: 14.5, weight: .ultraLight)
                                    : WIFont.font(WIFont.Face.groupLabel))
                .foregroundStyle(WIPaint.ink)
                // 横向拉一点补偿字体差:汉字字宽比原版的微软雅黑窄几个百分点
                .scaleEffect(x: label.unicodeScalars.allSatisfy { $0.isASCII } ? labelScale : WIFont.Face.groupLabel.scaleX,
                             y: 1, anchor: .leading)
                .fixedSize()
                .frame(width: width, height: labelHeight, alignment: .topLeading)
                .padding(.top, 3)
                .offset(x: labelX + labelDX, y: labelDY)
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
            // 原版是 28×28 的虚线方框,墨迹 x 22..49 / y 121..148
            WIIconView(icon: .selectBracket, size: 28)
                .offset(x: 22, y: 32)
                .onTapGesture { model.controller.tool = .select }
            WIBitmapIcon(name: "select_chev")
                .offset(x: 29, y: 71)
        }
    }

    // MARK: 图像(组起点 x=72)

    private var imageContent: some View {
        ZStack(alignment: .topLeading) {
            WIBitmapIcon(name: "img_crop")
                .offset(x: 21, y: 16)
                .onTapGesture { model.controller.tool = .crop }
                .help("裁剪")

            WIBitmapIcon(name: "img_rotate")
                .offset(x: 72, y: 17)
                .onTapGesture { model.handle(.rotateRight) }
                .help("旋转")
            WIBitmapIcon(name: "img_chev1")
                .offset(x: 105, y: 23)

            WIBitmapIcon(name: "img_removebg")
                .offset(x: 20, y: 67)
                .help("删除背景")

            WIBitmapIcon(name: "img_flip")
                .offset(x: 70, y: 66)
                .onTapGesture { model.handle(.flipHorizontal) }
                .help("翻转")
            WIBitmapIcon(name: "img_chev2")
                .offset(x: 105, y: 71)

            WIBitmapIcon(name: "img_resize")
                .offset(x: 144, y: 38)
                .onTapGesture { model.handle(.resize) }
                .help("调整大小")
        }
    }

    // MARK: 工具(组起点 x=270)

    private var toolContent: some View {
        ZStack(alignment: .topLeading) {
            WIBitmapIcon(name: "tool_pencil")
                .offset(x: 20, y: 16)
                .onTapGesture { model.controller.tool = .pencil }
                .help("铅笔")
            WIBitmapIcon(name: "tool_fillcan")
                .offset(x: 70, y: 16)
                .onTapGesture { model.controller.tool = .fill }
                .help("用颜色填充")
            WIBitmapIcon(name: "tool_text")
                .offset(x: 122, y: 17)
                .onTapGesture { model.controller.tool = .text }
                .help("文本")

            WIBitmapIcon(name: "tool_eraser")
                .offset(x: 22, y: 65)
                .onTapGesture { model.controller.tool = .eraser }
                .help("橡皮擦")
            WIBitmapIcon(name: "tool_dropper")
                .offset(x: 70, y: 67)
                .onTapGesture { model.controller.tool = .eyedropper }
                .help("取色器")
            WIBitmapIcon(name: "tool_magnifier")
                .offset(x: 120, y: 67)
                .onTapGesture { model.controller.tool = .magnifier }
                .help("放大镜")
        }
    }

    // MARK: 画笔(组起点 x=441)

    private var brushContent: some View {
        ZStack(alignment: .topLeading) {
            // 原版的选中框是 **1px** 蓝边 + 圆角 5:
            // 实测左边框 x=456 是纯 (0,103,192),x=457 已经是纯白内芯;
            // 之前用 1.5px,渲染成 1px 实 + 1px 半透明,内芯就被污染了。
            // 圆角也是量出来的:原版顶边那行只有 29 个蓝像素(宽 39),
            // 圆角 3 会画出 35 个 —— 39 - 2r = 29 反推 r = 5。
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(WIPaint.accent, lineWidth: 1)
                .frame(width: 39, height: 59)
                .offset(x: 15, y: 26)
            // 原版这个按钮是分体的:画笔和 ▾ 之间有一条分隔线
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 35, height: 1)
                .offset(x: 16, y: 63)
            WIBitmapIcon(name: "brush_paint")
                .offset(x: 17, y: 28)
                .onTapGesture { model.controller.tool = .brush }
                .help("画笔")
            WIBitmapIcon(name: "brush_chev")
                .offset(x: 25, y: 65)
        }
    }

    // MARK: 形状(组起点 x=506)

    private var shapeContent: some View {
        ZStack(alignment: .topLeading) {
            ShapeGalleryBox(controller: model.controller)
                .offset(x: 15, y: 6)

            // 轮廓样式(左上):圆角方块 + 一支斜插进来的笔
            WIBitmapIcon(name: "shape_outline")
                .offset(x: 188, y: 20)
                .onTapGesture { model.controller.tool = .shape }
                .help("轮廓样式")
            WIBitmapIcon(name: "shape_chev1")
                .offset(x: 222, y: 24)

            // 填充样式(右):圆角方块 + 波纹
            WIBitmapIcon(name: "shape_fill")
                .offset(x: 254, y: 34)
                .help("填充样式")

            // 油漆桶(左下)
            WIBitmapIcon(name: "shape_thick")
                .offset(x: 188, y: 67)
                .help("填充方式")
            WIBitmapIcon(name: "shape_chev2")
                .offset(x: 222, y: 73)

            WIBitmapIcon(name: "shape_chev3")
                .offset(x: 265, y: 73)
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
            // 原版徽标是 30×28 的多色渐变缎带(中间镂空)。
            // 手描路径画不出那种圆润的色带边界,实测整块糊成方块,
            // 直接抠原版像素当位图贴回(Resources/icons/copilot_badge.png)。
            WIBitmapIcon(name: "copilot_badge")
                .offset(x: 22, y: 30)
                .help("Copilot(不实现)")
            // ▾ 比原版低 1px(原版墨迹 160..163)
            WIIconView(icon: .chevronDown, size: 12)
                .offset(x: 34, y: 66)
        }
    }

    // MARK: 层(组起点 x=1338)

    private var layerContent: some View {
        ZStack(alignment: .topLeading) {
            // 原版是「三层堆叠、中间一层是蓝的」字形,手绘路径画不出来,直接抠原版像素
            WIBitmapIcon(name: "group_layers")
                .offset(x: 22, y: 38)
                .onTapGesture { model.controller.showsLayerPanel.toggle() }
                .help("图层")
        }
    }
}

// MARK: - 形状库

/// 形状库:只有一圈很淡的边框,内部和功能区同色(原版并没有白底!)
///
/// 原版实测:面板 x 521..682 / y 95..194(162×100),滚动条 x 674..676 / y 116..150。
/// 网格 cell 22×22,列距 28、行距 27,左上角 cell 在 (528, 102)——这些是抠位图的基准。
struct ShapeGalleryBox: View {
    @Bindable var controller: CanvasController

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 6), count: 5)
    private let rows = Array(repeating: GridItem(.fixed(22), spacing: 5), count: 4)

    /// 原版截图里前三行是完整的,第四行被面板底边裁掉一截(只剩星星尖)。
    /// 前四行都用抠下来的位图保证逐像素一致(第四行抠的是被裁后剩下的那 11 行);
    /// 第五行原版截图里根本没有,继续用矢量画,往下滚动还能看到完整图形。
    private static let bitmapCount = 20

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(ShapeKind.allCases.enumerated()), id: \.element) { index, kind in
                    cell(index: index, kind: kind)
                }
            }
            .padding(.leading, 6)
            .padding(.top, 7)
            .padding(.trailing, 20)
        }
        .frame(width: 162, height: 100)
        // 原版第四行形状被面板底边裁掉,只露出一个尖。ScrollView 默认不裁,
        // 第四行会画到面板边框外面去 —— 必须裁到面板高度。
        .clipped()
        .overlay(alignment: .topTrailing) {
            // 原版右侧那根细滚动条
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.black.opacity(0.22))
                .frame(width: 3, height: 35)
                .padding(.trailing, 6)
                .padding(.top, 21)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cell(index: Int, kind: ShapeKind) -> some View {
        Group {
            if index < Self.bitmapCount {
                WIBitmapIcon(name: String(format: "shape_%02d", index))
            } else {
                // 第五行原版截图里没有,矢量画,往下滚动能看到完整图形
                WIShapeIconView(icon: kind.galleryIcon, size: 20)
            }
        }
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
