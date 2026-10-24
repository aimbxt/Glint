import Foundation
import CoreGraphics
import Combine

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
        let suite = "GlintTests.Focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let focusStore = try TaskStore(inMemory: true)
        focusStore.add("First focus task")
        focusStore.add("Second focus task")
        let firstFocus = focusStore.active[0].id, secondFocus = focusStore.active[1].id
        func activeIDs() -> Set<UUID> { Set(focusStore.active.map(\.id)) }
        let state = PanelState(defaults: defaults, activeTaskIDs: activeIDs())
        let subscription = focusStore.$revision.dropFirst().sink { _ in state.reconcile(activeTaskIDs: activeIDs()) }
        defer { subscription.cancel() }

        expect(state.presentation == .list && state.focusedTaskID == nil, "Fresh installation starts in list mode")
        state.collapse()
        expect(state.presentation == .countPill, "No focus selection uses task-count pill")
        state.focus(on: firstFocus, activeTaskIDs: activeIDs())
        expect(state.presentation == .focusPill && state.focusedTaskID == firstFocus, "Selecting a task enters focus mode")
        let originalTasks = focusStore.snapshot()
        state.showList()
        expect(state.presentation == .list && state.focusedTaskID == firstFocus, "List view retains focus selection")
        state.collapse()
        expect(state.presentation == .focusPill, "Collapsing list resumes selected task")
        state.focus(on: secondFocus, activeTaskIDs: activeIDs())
        expect(state.focusedTaskID == secondFocus, "A new focus selection replaces the previous one")
        expect(focusStore.snapshot() == originalTasks, "Changing focus does not change task data")
        state.focus(on: UUID(), activeTaskIDs: activeIDs())
        expect(state.focusedTaskID == secondFocus, "Stale IDs cannot replace valid focus")
        focusStore.edit(secondFocus, text: "Updated focus text")
        expect(state.focusedTaskID == secondFocus && focusStore.active.first(where: { $0.id == state.focusedTaskID })?.text == "Updated focus text", "Editing preserves focus and updates its task")

        state.saveSize(CGSize(width: 420, height: 600), for: .list)
        state.saveSize(CGSize(width: 210, height: 50), for: .countPill)
        state.saveSize(CGSize(width: 380, height: 100), for: .focusPill)
        let restored = PanelState(defaults: defaults, activeTaskIDs: activeIDs())
        expect(restored.presentation == .focusPill && restored.focusedTaskID == secondFocus, "Relaunch restores focus pill and selected task")
        expect(restored.savedSize(for: .list) == CGSize(width: 420, height: 600), "Expanded size is saved independently")
        expect(restored.savedSize(for: .countPill) == CGSize(width: 210, height: 50), "Count pill size is saved independently")
        expect(restored.savedSize(for: .focusPill) == CGSize(width: 380, height: 100), "Focus pill size is saved independently")
        state.showList()
        let restoredList = PanelState(defaults: defaults, activeTaskIDs: activeIDs())
        expect(restoredList.presentation == .list && restoredList.focusedTaskID == secondFocus, "Relaunch preserves list view with paused focus selection")
        state.collapse()
        focusStore.toggle(secondFocus)
        expect(state.presentation == .countPill && state.focusedTaskID == nil, "Successful completion returns to task-count pill")
        expect(focusStore.active.count == 1, "Focus completion never automatically chooses next task")
        focusStore.undoManager.undo()
        expect(focusStore.active.contains(where: { $0.id == secondFocus }) && state.focusedTaskID == nil, "Undo restores task without restoring focus")
        state.focus(on: firstFocus, activeTaskIDs: activeIDs())
        state.showList()
        focusStore.delete(firstFocus)
        expect(state.presentation == .list && state.focusedTaskID == nil, "Deleting selected task from list clears focus without collapsing")
        state.focus(on: secondFocus, activeTaskIDs: activeIDs())
        state.stopFocusing()
        expect(state.presentation == .countPill && state.focusedTaskID == nil, "Stop focusing from focus pill returns to count pill")
        state.focus(on: secondFocus, activeTaskIDs: activeIDs())
        state.showList()
        state.stopFocusing()
        expect(state.presentation == .list && state.focusedTaskID == nil, "Stop focusing in list stays in list")
        defaults.set(firstFocus.uuidString, forKey: "focusedTaskID")
        defaults.set(true, forKey: "collapsed")
        let stale = PanelState(defaults: defaults, activeTaskIDs: activeIDs())
        expect(stale.presentation == .countPill && stale.focusedTaskID == nil, "Stale saved selection falls back to count pill")
        expect(defaults.string(forKey: "focusedTaskID") == nil, "Invalid saved selection is removed")
        expect(PanelPresentation.focusPill.clamped(CGSize(width: 1, height: 1)) == CGSize(width: 240, height: 48), "Focus pill minimum keeps buttons and text reachable")
        expect(PanelPresentation.focusPill.clamped(CGSize(width: 999, height: 999)) == CGSize(width: 520, height: 180), "Focus pill maximum respects design bounds")
        checks += runSnappingTests()
        print("Passed \(checks) task, persistence, geometry, focus, and snapping checks.")
    }
}
