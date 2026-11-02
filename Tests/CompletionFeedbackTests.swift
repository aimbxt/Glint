import AppKit
import Foundation

@main
struct CompletionFeedbackTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FeedbackChecksDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor static func runChecks() async throws {
        let resultURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("completion-feedback-result.txt")
        try "RUNNING\n".write(to: resultURL, atomically: true, encoding: .utf8)
        let domain = Bundle.main.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let store = try TaskStore(inMemory: true)
        store.add("First animation task")
        store.add("Second animation task\nwith wrapping text")
        let first = store.active[0].id, second = store.active[1].id
        let controller = PanelController(store: store, preferences: Preferences())
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            let passed = value()
            if !passed { try? "FAILED: \(message)\n".write(to: resultURL, atomically: true, encoding: .utf8) }
            precondition(passed, message)
            checks += 1
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        controller.toggleTask(first)
        expect(store.completed.contains { $0.id == first }, "Completion saves before the first animation frame")
        expect(controller.completionEffects.count == 1, "Successful completion creates one effect")
        expect(controller.completionEffects[0].record.text == "First animation task", "The departure retains a value snapshot")
        expect(controller.completionEffects[0].retainsListRow == !reduced, "Reduce Motion removes the row immediately")
        controller.toggleTask(second)
        expect(controller.completionEffects.count == 2, "Rapid completions have independent effects")
        store.undoManager.undo()
        expect(controller.completionEffects.map(\.id) == [first], "Undo cancels only the restored task's effect")
        try await Task.sleep(for: .milliseconds(650))
        expect(controller.completionEffects.isEmpty, "All finished effects are cleaned up")
        let pulse = controller.completionPulse
        controller.toggleTask(first)
        expect(controller.completionEffects.isEmpty && controller.completionPulse == pulse, "Reopening does not celebrate")
        controller.toggleTask(UUID())
        expect(controller.completionEffects.isEmpty && controller.completionPulse == pulse, "Invalid identifiers do not celebrate")
        controller.focus(on: first)
        controller.completeFocusedTask()
        expect(store.completed.contains { $0.id == first }, "Focused completion saves immediately")
        expect(controller.state.presentation == (reduced ? .countPill : .focusPill), "Focus holds only its short animated checkmark beat")
        try await Task.sleep(for: .milliseconds(260))
        expect(controller.state.presentation == .countPill && controller.state.focusedTaskID == nil, "Focused completion returns to the count pill")
        store.undoManager.undo()
        expect(controller.state.focusedTaskID == nil && controller.completionEffects.isEmpty, "Undo after the handoff restores no focus or sparkle")
        controller.focus(on: first)
        controller.completeFocusedTask()
        store.undoManager.undo()
        expect(controller.state.presentation == .countPill && controller.state.focusedTaskID == nil, "Immediate Undo also clears focus")
        expect(controller.completionEffects.isEmpty, "Immediate Undo cancels the focus handoff task")
        try await Task.sleep(for: .milliseconds(250))
        expect(store.active.contains { $0.id == first }, "A cancelled handoff cannot complete the restored task later")
        controller.showList()
        controller.toggleTask(first)
        let oldToken = controller.completionEffects[0].token
        controller.toggleTask(first)
        controller.toggleTask(first)
        expect(controller.completionEffects.count == 1 && controller.completionEffects[0].token != oldToken, "Recompletion replaces a cancelled effect with a fresh token")
        store.delete(first)
        expect(controller.completionEffects.isEmpty, "Deleting a departing task cancels its visual")
        controller.toggleTask(second)
        expect(!controller.completionEffects.isEmpty, "Remaining task can still complete")
        controller.hide()
        expect(controller.completionEffects.isEmpty, "Hiding clears unfinished visual effects")

        // Exercise the real hosted SwiftUI field and AppKit field editor. These
        // checks run only in this helper app, with its own in-memory task list.
        let keyBeforePassiveShow = NSApp.keyWindow
        controller.show(focus: false)
        expect(NSApp.keyWindow === keyBeforePassiveShow && controller.focusRequest == nil,
               "Passive showing never requests entry or replaces keyboard focus")
        controller.show()
        for _ in 0..<40 {
            if controller.hasKeyboardFocus && controller.panel.firstResponder is NSTextView { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        expect(controller.hasKeyboardFocus && NSApp.isActive && controller.panel.isKeyWindow,
               "Summoning waits for real app and panel keyboard focus (active: \(NSApp.isActive), key: \(controller.panel.isKeyWindow), observed: \(controller.hasKeyboardFocus))")
        expect(controller.focusRequest != nil && controller.panel.firstResponder is NSTextView,
               "Summoning focuses the actual SwiftUI field editor")
        let firstRequest = controller.focusRequest
        let editor = controller.panel.firstResponder as! NSTextView
        editor.insertText("Keyboard draft survives hiding", replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.hide()
        expect(!controller.hasKeyboardFocus && controller.focusRequest == nil,
               "Hiding cancels the entry request and keyboard-focus indication")
        controller.show()
        for _ in 0..<40 {
            if controller.hasKeyboardFocus && controller.panel.firstResponder is NSTextView { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        expect(controller.focusRequest != firstRequest && controller.focusRequest != nil,
               "Showing again creates a fresh focus request")
        expect((controller.panel.firstResponder as? NSTextView)?.string == "Keyboard draft survives hiding",
               "Hide/show preserves the unfinished draft in the real editor")
        controller.openSettings()
        try await Task.sleep(for: .milliseconds(100))
        expect(!controller.hasKeyboardFocus && controller.focusRequest == nil,
               "Settings clears the list's keyboard-focus state")
        NSApp.keyWindow?.performClose(nil)
        controller.show()
        for _ in 0..<40 {
            if controller.hasKeyboardFocus && controller.panel.firstResponder is NSTextView { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        expect(controller.panel.firstResponder is NSTextView && controller.hasKeyboardFocus,
               "Task entry reacquires a real field editor after Settings")
        controller.hide()
        controller.show()
        controller.hide()
        try await Task.sleep(for: .milliseconds(100))
        expect(!controller.visible && !controller.hasKeyboardFocus && controller.focusRequest == nil,
               "An immediately hidden panel cannot revive a queued focus request")
        let result = "Passed \(checks) completion-feedback and keyboard-focus checks (Reduce Motion: \(reduced))."
        print(result)
        try result.write(to: resultURL, atomically: true, encoding: .utf8)
    }
}

@MainActor
private final class FeedbackChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await CompletionFeedbackTests.runChecks() }
            catch {
                let resultURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("completion-feedback-result.txt")
                try? "FAILED: \(error)\n".write(to: resultURL, atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }
}
