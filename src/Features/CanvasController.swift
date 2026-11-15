import AppKit
import Foundation
import Observation
import SwiftUI

/// 画布相关的全部 UI 状态。
///
/// 拆成两层:
/// - `PaintDocument` 持有**画面内容**(图层、像素、历史)
/// - `CanvasController` 持有**交互状态**(工具、颜色、缩放、选区)
///
/// 这样"撤销"只碰前者,重绘只碰后者,职责不串。
@MainActor
@Observable
final class CanvasController {
    // MARK: 视图

    /// 缩放倍率
    var zoom: CGFloat = 1.0
    /// 文档原点(0,0)在视图中的位置(视图坐标,y 向上)
    var pan: CGPoint = .zero
    var showsGrid: Bool = false
    var showsRulers: Bool = false
    var showsStatusBar: Bool = true
    var showsLayerPanel: Bool = false
    var showsToolOptions: Bool = true
    /// 首次布局完成后自动适应一次(那时才知道视口真实尺寸)
    var didInitialFit: Bool = false
    /// 用户是否手动平移/缩放过。一旦为 true,视口尺寸变化时就不再自动重新居中。
    var didUserPan: Bool = false
    /// 网格间距(文档像素)
    var gridSpacing: CGFloat = 10

    // MARK: 工具

    var tool: PaintTool = .pencil
    var shapeKind: ShapeKind = .rectangle
    var brush = BrushSettings()
    var primaryColor: RGBA = .black
    var secondaryColor: RGBA = .white
    var fillStyle: FillStyle = .solid
    var strokeStyle: OutlineStyle = .stroked
    var lineWidth: CGFloat = 3
    var textSize: CGFloat = 24

    // MARK: 选区

    /// 当前选区(文档坐标)。nil 表示没有选区。
    var selectionRect: CGRect?

    // MARK: 派生

    /// 状态栏显示用的画布尺寸文本
    var sizeText: String {
        guard let doc = document else { return "—" }
        return "\(Int(doc.size.width)) × \(Int(doc.size.height))像素"
    }

    var zoomText: String {
        "\(Int((zoom * 100).rounded()))%"
    }

    /// 由 App 注入,用于尺寸/大小读数
    weak var document: PaintDocument?

    // MARK: 缩放

    /// 画布视口尺寸(由 NSView 布局时同步)
    var viewportSize: CGSize = .zero

    /// 以视口中心为锚设置缩放
    func setZoom(_ value: CGFloat) {
        // 上限必须和滑块能表示的范围一致(ZoomSlider 是 0.05~8,也就是 800%)。
        // 以前这里夹到 32,「放大」按钮点几下就能到 3200%,但滑块只能画到 800% ——
        // 百分比文字和滑块对不上。
        let clamped = min(max(value, 0.05), 8)
        guard zoom > 0 else { zoom = clamped; return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let docPoint = CGPoint(x: (center.x - pan.x) / zoom, y: (center.y - pan.y) / zoom)
        zoom = clamped
        pan = CGPoint(x: center.x - docPoint.x * clamped, y: center.y - docPoint.y * clamped)
    }

    /// 让文档完整落在视口内(和原版一样,最大只到 100%,居中显示)
    func fitToWindow() {
        guard let doc = document, viewportSize.width > 1, viewportSize.height > 1 else { return }
        let scale = min(viewportSize.width / doc.size.width, viewportSize.height / doc.size.height)
        zoom = min(max(scale, 0.02), 1.0)
        pan = CGPoint(
            x: (viewportSize.width - doc.size.width * zoom) / 2,
            y: (viewportSize.height - doc.size.height * zoom) / 2
        )
        didUserPan = false
    }
}

/// 人类可读的字节数
enum ByteFormat {
    static func string(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1fKB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fMB", mb) }
        return String(format: "%.2fGB", mb / 1024)
    }
}
