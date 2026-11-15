import AppKit
import SwiftUI

// MARK: - 应用状态

@MainActor
@Observable
final class AppModel {
    var document: PaintDocument
    var controller: CanvasController
    var showingResizeSheet = false
    var errorMessage: String?

    init() {
        let doc = PaintDocument(size: CGSize(width: 1200, height: 630))
        // 开发快照模式:允许指定文档名。原版截图打开的是一张真实文件,
        // 标题栏是「pragmata-capcom-spotlight-social - 画图」;用同一个名字起快照,
        // 标题栏的文字排版才能和原版逐像素比对(默认的「无标题」字形完全不同,没法比)。
        if let name = ProcessInfo.processInfo.environment["WINPAINT_SNAPSHOT_TITLE"] {
            doc.documentTitle = name
        }
        let ctrl = CanvasController()
        ctrl.document = doc
        self.document = doc
        self.controller = ctrl
    }

    var windowTitle: String {
        let base = document.fileURL?.deletingPathExtension().lastPathComponent ?? document.documentTitle
        return "\(base) - 画图"
    }

    // MARK: 文件

    func newDocument() {
        document.reset(to: CGSize(width: 1200, height: 630))
        document.documentTitle = "无标题"
        document.fileURL = nil
        controller.selectionRect = nil
        controller.fitToWindow()
    }

    func openImage() {
        guard let url = FileService.chooseOpenImage() else { return }
        guard let image = PaintDocument.loadImage(at: url) else {
            errorMessage = "无法读取所选文件"
            return
        }
        document.load(image: image, title: url.lastPathComponent)
        document.fileURL = url
        controller.selectionRect = nil
        controller.fitToWindow()
    }

    func openProject() {
        guard let url = FileService.chooseOpenProject() else { return }
        do {
            try ProjectFile.read(from: url, into: document)
            document.fileURL = url
            document.documentTitle = url.deletingPathExtension().lastPathComponent
            controller.fitToWindow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importImage() {
        guard let url = FileService.chooseOpenImage() else { return }
        document.importImage(from: url)
    }

    func save() {
        guard let url = document.fileURL else {
            saveAs()
            return
        }
        persist(to: url)
    }

    func saveAs() {
        let suggested = document.fileURL?.deletingPathExtension().lastPathComponent ?? document.documentTitle
        guard let url = FileService.chooseSaveLocation(suggestedName: suggested) else { return }
        persist(to: url)
    }

    func saveProject() {
        let suggested = document.fileURL?.deletingPathExtension().lastPathComponent ?? document.documentTitle
        guard let url = FileService.chooseSaveProject(suggestedName: suggested) else { return }
        do {
            try ProjectFile.write(document: document, to: url)
            document.fileURL = url
            document.isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(to url: URL) {
        guard let image = document.composite() else { return }
        do {
            try FileService.savePNG(image, to: url)
            document.fileURL = url
            document.documentTitle = url.deletingPathExtension().lastPathComponent
            document.isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 共享:导出 PNG 并放到剪贴板(同时提供文件 URL,方便拖到别的 App)
    func share() {
        guard let image = document.composite() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = rep.representation(using: .tiff, properties: [:]) {
            pasteboard.setData(tiff, forType: .tiff)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(document.documentTitle).png")
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: tmp)
            pasteboard.writeObjects([tmp as NSURL])
        }
    }

    /// 打印
    func printDocument() {
        guard let image = document.composite() else { return }
        let size = NSSize(width: image.width, height: image.height)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        let info = NSPrintInfo.shared
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        let op = NSPrintOperation(view: imageView)
        op.printInfo = info
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    /// 设置为桌面背景
    func setAsDesktopBackground() {
        guard let image = document.composite() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let tmp = URL(fileURLWithPath: "/tmp/winpaint-desktop.png")
        try? data.write(to: tmp)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            try? NSWorkspace.shared.setDesktopImageURL(tmp, for: screen, options: [:])
        }
    }

    // MARK: 编辑

    func undo() { document.undo() }
    func redo() { document.redo() }

    func selectAll() {
        controller.selectionRect = CGRect(origin: .zero, size: document.size)
    }

    func clearSelection() {
        controller.selectionRect = nil
    }

    // MARK: 剪贴板

    /// App 内部的剪贴板。
    ///
    /// 自己复制的东西存一份在这儿,不走系统剪贴板 —— 否则用户切到别的 App 复制了
    /// 一张图,回到画图按 ⌘V 粘回来的就不是刚才复制的那块了。
    /// 系统剪贴板只在**跨 App** 时才读(`Clipboard.read()`)。
    private var clipboardImage: CGImage?

    /// 有选区才能复制/剪切
    var canEditSelection: Bool { controller.selectionRect != nil }

    func copySelection() {
        guard let sel = controller.selectionRect,
              let img = SelectionOps.copyImage(document: document, selection: sel) else { return }
        clipboardImage = img
        Clipboard.write(img)
    }

    func cutSelection() {
        guard let sel = controller.selectionRect,
              let img = SelectionOps.copyImage(document: document, selection: sel) else { return }
        clipboardImage = img
        Clipboard.write(img)
        SelectionOps.eraseSelection(document: document, selection: sel)
    }

    func paste() {
        guard let img = clipboardImage ?? Clipboard.read() else { return }
        // 有选区就贴回选区左上角(剪切后紧接着粘贴 = 原地放回),没选区就贴到画布左上角
        let origin: CGPoint
        if let sel = controller.selectionRect {
            origin = sel.origin
        } else {
            origin = CGPoint(x: 0, y: max(0, document.size.height - CGFloat(img.height)))
        }
        controller.selectionRect = SelectionOps.pasteImage(document: document, image: img, at: origin)
    }

    /// 把画布裁剪到选区(所有图层一起裁,画布尺寸跟着变)
    func cropToSelection() {
        guard let sel = controller.selectionRect else { return }
        document.crop(to: sel)
        controller.selectionRect = nil
    }

    // MARK: 图像

    func handle(_ action: ImageAction) {
        switch action {
        case .rotateRight:
            document.rotateDocument(clockwise: true)
        case .rotateLeft:
            document.rotateDocument(clockwise: false)
        case .flipHorizontal:
            document.flipDocument(horizontal: true)
        case .flipVertical:
            document.flipDocument(horizontal: false)
        case .resize:
            showingResizeSheet = true
        case .importImage:
            importImage()
        case .crop:
            break
        }
    }
}

// MARK: - 应用

@main
struct WinPaintApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    DevSnapshot.applyRequestedWindowSize()
                    model.controller.fitToWindow()
                    DevSnapshot.scheduleIfRequested()
                }
        }
        .defaultSize(width: 1484, height: 985)
        // 隐藏原生标题栏,改成 Windows 画图那样的"图标 + 标题"行
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(model: model)
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // 行 1 · 标题栏 0..31
            TitleBarRow(title: model.windowTitle)

            // 行 2 · 菜单行 32..87
            MenuBarRow(model: model)

            // 行界横线 #EBEBEB(原版在 y=88)
            WIDividerLine()

            // 行 3 · 功能区 89..224
            RibbonView(model: model)

            // 行界横线(原版在 y=225)
            WIDividerLine()

            // 画布区 226..937(左侧浮动滑块、右侧浮动层面板都压在画布上,跟原版一样)
            ZStack(alignment: .topLeading) {
                MicaWorkspaceBackground()

                CanvasView(controller: model.controller, document: model.document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if model.controller.showsToolOptions {
                    ToolOptionsFloat(controller: model.controller)
                        .padding(.leading, 16)
                        .padding(.top, 130)
                }

                if model.controller.showsLayerPanel {
                    LayerPanelView(document: model.document)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 16)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if model.controller.showsStatusBar {
                // 行界横线(原版在 y=937)+ 状态栏 938..983
                // 底部留 1px 空行:原版最底下一行是 Win11 的 DWM 窗口阴影,
                // 去掉这行分隔线就会整体上移 1px,状态栏里所有图标全部错位。
                VStack(spacing: 0) {
                    WIDividerLine()
                    StatusBarView(
                        controller: model.controller,
                        document: model.document,
                        onFitToWindow: { model.controller.fitToWindow() },
                        onZoom: { model.controller.setZoom($0) }
                    )
                }
                .padding(.bottom, 1)
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        // 隐藏标题栏后 SwiftUI 仍会留 28pt 顶部安全区,自绘标题行要贴顶就得手动忽略
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.showingResizeSheet) {
            ResizeSheet(document: model.document)
        }
        .alert("出错了", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - 菜单

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建") { model.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("打开…") { model.openImage() }
                .keyboardShortcut("o", modifiers: .command)
            Button("打开项目…") { model.openProject() }
            Divider()
            Button("导入到画布…") { model.importImage() }
            Divider()
            Button("保存") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("另存为…") { model.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("另存为项目…") { model.saveProject() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.document.history.canUndo)
            Button("重做") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.document.history.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("剪切") { model.cutSelection() }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!model.canEditSelection)
            Button("复制") { model.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!model.canEditSelection)
            Button("粘贴") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
            Divider()
            Button("全选") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("取消选择") { model.clearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
        }

        CommandMenu("图像") {
            Button("向右旋转 90°") { model.handle(.rotateRight) }
            Button("向左旋转 90°") { model.handle(.rotateLeft) }
            Divider()
            Button("水平翻转") { model.handle(.flipHorizontal) }
            Button("垂直翻转") { model.handle(.flipVertical) }
            Divider()
            Button("裁剪") { model.cropToSelection() }
                .disabled(!model.canEditSelection)
            Button("调整大小…") { model.handle(.resize) }
                .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu("视图") {
            Toggle("标尺", isOn: Binding(get: { model.controller.showsRulers }, set: { model.controller.showsRulers = $0 }))
                .keyboardShortcut("r", modifiers: .control)
            Toggle("网格线", isOn: Binding(get: { model.controller.showsGrid }, set: { model.controller.showsGrid = $0 }))
                .keyboardShortcut("g", modifiers: .control)
            Divider()
            Toggle("状态栏", isOn: Binding(get: { model.controller.showsStatusBar }, set: { model.controller.showsStatusBar = $0 }))
            Toggle("工具选项", isOn: Binding(get: { model.controller.showsToolOptions }, set: { model.controller.showsToolOptions = $0 }))
            Toggle("图层面板", isOn: Binding(get: { model.controller.showsLayerPanel }, set: { model.controller.showsLayerPanel = $0 }))
            Divider()
            Button("放大") { model.controller.setZoom(model.controller.zoom * 1.25) }
                .keyboardShortcut("+", modifiers: .command)
            Button("缩小") { model.controller.setZoom(model.controller.zoom / 1.25) }
                .keyboardShortcut("-", modifiers: .command)
            Button("实际大小") { model.controller.setZoom(1.0) }
                .keyboardShortcut("0", modifiers: .command)
            Button("适应窗口") { model.controller.fitToWindow() }
                .keyboardShortcut("9", modifiers: .command)
        }
    }
}

// MARK: - 调整大小对话框

struct ResizeSheet: View {
    let document: PaintDocument
    @Environment(\.dismiss) private var dismiss

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var keepAspect = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("调整大小")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("宽度", text: $widthText)
                    .frame(width: 90)
                    .onChange(of: widthText) { _, newValue in
                        guard keepAspect, let w = Double(newValue), w > 0 else { return }
                        let ratio = document.size.height / document.size.width
                        heightText = String(Int((w * ratio).rounded()))
                    }
                Text("×")
                    .foregroundStyle(.secondary)
                TextField("高度", text: $heightText)
                    .frame(width: 90)
                    .onChange(of: heightText) { _, newValue in
                        guard keepAspect, let h = Double(newValue), h > 0 else { return }
                        let ratio = document.size.width / document.size.height
                        widthText = String(Int((h * ratio).rounded()))
                    }
                Toggle("保持纵横比", isOn: $keepAspect)
                    .toggleStyle(.checkbox)
            }

            Text("当前: \(Int(document.size.width)) × \(Int(document.size.height)) 像素")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("确定") {
                    if let w = Double(widthText), let h = Double(heightText), w >= 1, h >= 1 {
                        document.resizeDocument(to: CGSize(width: w, height: h))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            widthText = String(Int(document.size.width))
            heightText = String(Int(document.size.height))
        }
    }
}
