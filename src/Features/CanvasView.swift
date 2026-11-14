import SwiftUI

/// SwiftUI → AppKit 画布桥接。
///
/// 依赖观察靠 `onChange` 建立:body 里读到的这些值一旦变化,SwiftUI 会重新求值 body,
/// 从而调用 `updateNSView`,进而触发 NSView 重绘。
struct CanvasView: View {
    let controller: CanvasController
    let document: PaintDocument

    var body: some View {
        CanvasRepresentable(controller: controller, document: document)
            .onChange(of: document.renderVersion) { _, _ in }
            .onChange(of: controller.zoom) { _, _ in }
            .onChange(of: controller.pan) { _, _ in }
            .onChange(of: controller.selectionRect) { _, _ in }
            .onChange(of: controller.showsGrid) { _, _ in }
            .onChange(of: document.selectedLayerIndex) { _, _ in }
            // 底色透明,由外层 Mica 背景负责
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let controller: CanvasController
    let document: PaintDocument

    func makeNSView(context: Context) -> PaintCanvasView {
        let view = PaintCanvasView(frame: .zero)
        view.controller = controller
        view.document = document
        view.onChange = { }
        return view
    }

    func updateNSView(_ nsView: PaintCanvasView, context: Context) {
        nsView.controller = controller
        nsView.document = document
        nsView.needsDisplay = true
    }
}
