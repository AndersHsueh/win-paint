import CoreGraphics
import Foundation

/// 一次可撤销动作。
///
/// 两种形态:
/// - `.patch` 像素级:只记录被改动矩形区域的 before/after 位图,内存占用与改动面积成正比
/// - `.structure` 结构级:图层增删/重排/文档改尺寸这类无法用区域表达的操作,退化为整档快照
enum HistoryAction {
    case patch(PatchRecord)
    case structure(StructureRecord)
}

/// 像素级记录:某图层某矩形区域的前后快照
struct PatchRecord {
    var layerID: UUID
    var rect: CGRect
    var before: CGImage?
    var after: CGImage?
}

/// 结构级记录:整档快照
struct StructureRecord {
    var before: DocumentSnapshot
    var after: DocumentSnapshot
}

/// 文档结构快照
struct DocumentSnapshot {
    var size: CGSize
    var layers: [PaintLayer.State]
    var selectedLayerIndex: Int

    @MainActor
    init(document: PaintDocument) {
        self.size = document.size
        self.layers = document.layers.map { $0.captureState() }
        self.selectedLayerIndex = document.selectedLayerIndex
    }}

/// 一条历史记录 = 一次用户操作
struct HistoryEntry {
    var title: String
    var actions: [HistoryAction]

    init(title: String, actions: [HistoryAction]) {
        self.title = title
        self.actions = actions
    }

    var isStructural: Bool {
        actions.contains { if case .structure = $0 { return true } else { return false } }
    }
}

/// 撤销/重做栈。
///
/// 只负责存,不负责用 —— 真正把补丁贴回图层是 `PaintDocument` 的事,
/// 这样历史层不必知道图层的内部结构。
@MainActor
@Observable
final class HistoryManager {
    private(set) var undoStack: [HistoryEntry] = []
    private(set) var redoStack: [HistoryEntry] = []

    /// 上限,防止长会话把内存吃光
    var limit: Int = 64

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String? { undoStack.last?.title }
    var redoTitle: String? { redoStack.last?.title }

    func record(_ entry: HistoryEntry) {
        undoStack.append(entry)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    func popUndo() -> HistoryEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry
    }

    func popRedo() -> HistoryEntry? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
