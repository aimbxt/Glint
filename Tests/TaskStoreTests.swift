import Foundation
import CoreGraphics

@main
struct TaskStoreTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let store = try TaskStore(inMemory: true)
        store.add("   \n ")
        expect(store.items.isEmpty, "Ignore whitespace-only tasks")
        store.add("  First task  ")
        store.add("Second task")
        store.add("Third task")
        expect(store.active.map(\.text) == ["First task", "Second task", "Third task"], "Trim and order added tasks")
        let first = store.active[0].id
        let second = store.active[1].id
        let third = store.active[2].id
        let creation = store.active[0].createdAt
        store.toggle(first)
        expect(store.active.count == 2 && store.completed.first?.id == first, "Complete into completed section")
        store.undoManager.undo()
        expect(store.active.first?.id == first && store.completed.isEmpty, "Undo completion")
        store.undoManager.redo()
        expect(store.completed.first?.id == first, "Redo completion")
        store.toggle(first)
        expect(store.active.first?.id == first, "Reopen restores list order")
        store.edit(first, text: "   ")
        expect(store.active.first?.text == "First task", "Blank edits preserve task")
        store.edit(first, text: "A longer task\nwith a second line")
        expect(store.active.first?.text.contains("\n") == true, "Multiline task content")
        store.undoManager.undo()
        expect(store.active.first?.text == "First task", "Undo edit")
        store.move(third, before: first)
        expect(store.active.map(\.id) == [third, first, second], "Drag reorder")
        store.undoManager.undo()
        expect(store.active.map(\.id) == [first, second, third], "Undo reorder")
        store.undoManager.redo()
        expect(store.active.map(\.id) == [third, first, second], "Redo reorder")
        store.move(third, offset: 1)
        expect(store.active.map(\.id) == [first, third, second], "Keyboard-accessible move down")
        store.delete(first)
        expect(!store.items.contains { $0.id == first }, "Delete task")
        store.undoManager.undo()
        expect(store.items.first?.id == first && store.items.first?.createdAt == creation, "Undo deletion preserves identity and date")
        let snapshot = store.snapshot()
        store.move(UUID(), before: first)
        store.move(first, offset: -1)
        store.delete(UUID())
        expect(store.snapshot() == snapshot, "Invalid moves and stale IDs are harmless")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlintTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        var saved: [TaskRecord] = []
        do {
            let disk = try TaskStore(url: url)
            disk.add("Saved first")
            disk.add("Saved second")
            disk.toggle(disk.active[0].id)
            disk.edit(disk.active[0].id, text: "Saved edit")
            saved = disk.snapshot()
        }
        let reopened = try TaskStore(url: url)
        expect(reopened.snapshot() == saved, "Relaunch restores all task fields and completion state")
        expect(reopened.errorMessage == nil, "Successful persistence has no error")
        let frame = CGRect(x: 100, y: 200, width: 200, height: 60)
        let minimum = PanelGeometry.pillMinimum, maximum = PanelGeometry.pillMaximum
        func resize(_ edges: PanelGeometry.Edges, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            PanelGeometry.resized(frame, delta: CGSize(width: dx, height: dy), edges: edges, minimum: minimum, maximum: maximum)
        }
        expect(resize(.right, 50, 0) == CGRect(x: 100, y: 200, width: 250, height: 60), "Right edge grows without moving left edge")
        expect(resize(.left, -50, 0) == CGRect(x: 50, y: 200, width: 250, height: 60), "Left edge keeps right edge anchored")
        expect(resize(.top, 0, 30) == CGRect(x: 100, y: 200, width: 200, height: 90), "Top edge keeps bottom edge anchored")
        expect(resize(.bottom, 0, -30) == CGRect(x: 100, y: 170, width: 200, height: 90), "Bottom edge keeps top edge anchored")
        expect(resize([.right, .bottom], 50, -30) == CGRect(x: 100, y: 170, width: 250, height: 90), "Corner resizes both dimensions")
        expect(resize(.left, 1000, 0).maxX == frame.maxX && resize(.left, 1000, 0).width == minimum.width, "Minimum width keeps opposite edge fixed")
        expect(resize(.bottom, 0, -1000).maxY == frame.maxY && resize(.bottom, 0, -1000).height == maximum.height, "Maximum height keeps opposite edge fixed")
        expect(PanelGeometry.pillSize(CGSize(width: 360, height: 72)) == CGSize(width: 360, height: 72), "Saved custom pill size is preserved")
        expect(PanelGeometry.pillSize(CGSize(width: 1, height: 1)) == minimum, "Restored pill respects minimum size")
        expect(PanelGeometry.pillSize(CGSize(width: CGFloat.infinity, height: CGFloat.nan)) == PanelGeometry.pillDefault, "Invalid saved dimensions use defaults")
        print("Passed \(checks) task, persistence, and window geometry checks.")
    }
}
