import AppKit
import SwiftUI
import Combine

final class GlintPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu)?
    var onUserDragBeginning: (() -> Void)?
    var onUserDragEnded: ((NSEvent.ModifierFlags) -> Void)?
    var onUserResizeBeginning: (() -> Void)?
    private var dragMovement: WindowDragMovement?
    var isUserDragging: Bool { dragMovement != nil }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // Claim real keyboard focus before SwiftUI starts a field editor.
            // Ordering the floating panel alone does not activate its app.
            if !NSApp.isActive { NSApp.activate() }
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func recordDragMovement() -> Bool { dragMovement?.record(frame.origin) ?? false }
    func performUserDrag(with event: NSEvent) -> Bool {
        onUserDragBeginning?()
        dragMovement = WindowDragMovement(origin: frame.origin)
        performDrag(with: event)
        _ = recordDragMovement()
        let didDrag = dragMovement?.didDrag == true
        dragMovement = nil
        if didDrag { onUserDragEnded?(NSEvent.modifierFlags) }
        return didDrag
    }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    let store: TaskStore
    let preferences: Preferences
    let state: PanelState
    let snapping = SnapState()
    let shortcut = GlobalShortcut()
    var panel: GlintPanel!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var changingFrame = false
    private var appliedPresentation: PanelPresentation = .list
    private var snapTimer: Timer?
    private var snapTarget: NSRect?
    private var screenLayoutTimer: Timer?
    private var lastScreenLayout: [SnapScreen] = []
    @Published private(set) var focusRequest: UUID?
    @Published private(set) var hasKeyboardFocus = false
    private var entryFocusPending = false
    @Published var visible = true
    @Published private(set) var completionPulse = 0
    @Published private(set) var completionEffects: [TaskCompletionEffect] = []
    private var completionTasks: [UUID: Task<Void, Never>] = [:]
    private var completingFocusID: UUID?

    init(store: TaskStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        self.state = PanelState(activeTaskIDs: Set(store.active.map(\.id)))
        super.init()
        // A normal activating panel acquires keyboard focus on interaction.
        // Passive orderFrontRegardless still leaves the other app's focus alone.
        let window = GlintPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 380), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel = window
        window.title = "Glint"
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        window.animationBehavior = .none
        window.delegate = self
        window.onUserDragBeginning = { [weak self] in self?.cancelSnapAnimation(finish: true) }
        window.onUserDragEnded = { [weak self] flags in self?.finishUserDrag(bypass: flags.contains(.option)) }
        window.onUserResizeBeginning = { [weak self] in self?.prepareForManualResize() }
        window.contextMenuProvider = { [weak self] in self?.makePanelMenu() ?? NSMenu() }
        window.contentView = GlintHostingView(rootView: TodoView(store: store, preferences: preferences, controller: self, state: state))
        updatePin()
        restoreFrame()
        preferences.$pinned.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updatePin() }
        }.store(in: &subscriptions)
        snapping.$enabled.dropFirst().sink { [weak self] enabled in
            if !enabled { self?.cancelSnapAnimation(finish: false) }
        }.store(in: &subscriptions)
        store.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            // Undo, reopening, deletion, or a failed save must remove stale visuals.
            for effect in self.completionEffects where !self.store.completed.contains(where: {
                $0.id == effect.id && $0.completedAt == effect.record.completedAt
            }) {
                self.removeCompletionEffect(effect.id)
            }
            if self.state.presentation == .focusPill,
               let id = self.completingFocusID, self.state.focusedTaskID == id,
               self.store.completed.contains(where: { $0.id == id }) { return }
            self.transition { self.state.reconcile(activeTaskIDs: Set(self.store.active.map(\.id))) }
        }.store(in: &subscriptions)
        shortcut.onPress = { [weak self] in self?.toggleVisibility() }
        updateShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationResignedActive), name: NSApplication.didResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Track usable bounds, including Dock changes, while attached. Reposition
        // only when those bounds actually change, and never during a user drag.
        let monitor = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.snapping.attachment != nil, self.snapTimer == nil,
                      !self.changingFrame, !self.panel.isUserDragging else { return }
                let screens = self.snapScreens
                if screens != self.lastScreenLayout {
                    self.lastScreenLayout = screens
                    self.ensureReachable()
                }
            }
        }
        screenLayoutTimer = monitor
        RunLoop.main.add(monitor, forMode: .common)
    }

    func updatePin() { panel.level = preferences.pinned ? .floating : .normal }
    func updateShortcut() {
        preferences.shortcutError = shortcut.register(key: preferences.shortcutKey, modifiers: preferences.shortcutModifiers) ? nil : "That shortcut is already in use or unavailable. Record a different combination."
    }

    func show(focus: Bool = true) {
        visible = true
        ensureReachable()
        if focus {
            showList()
            entryFocusPending = true
            // A shortcut or Show command explicitly asks us to take focus.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            updateKeyboardFocus()
        } else { panel.orderFrontRegardless() }
    }
    func hide() { cancelEntryFocus(); clearCompletionEffects(); panel.makeFirstResponder(nil); panel.orderOut(nil); visible = false; hasKeyboardFocus = false }
    func quit() { panel.makeFirstResponder(nil); NSApp.terminate(nil) }
    func toggleVisibility() { visible ? hide() : show() }

    private func cancelEntryFocus() {
        entryFocusPending = false
        focusRequest = nil
    }

    private func updateKeyboardFocus() {
        let ready = NSApp.isActive && panel.isKeyWindow && visible
        if hasKeyboardFocus != ready { hasKeyboardFocus = ready }
        // App activation is asynchronous. Deliver only after both events arrive,
        // regardless of whether the app or the panel becomes active first.
        if ready && entryFocusPending && state.presentation == .list {
            entryFocusPending = false
            focusRequest = UUID()
        }
    }

    @objc private func applicationBecameActive() { updateKeyboardFocus() }
    @objc private func applicationResignedActive() {
        cancelEntryFocus()
        hasKeyboardFocus = false
        panel.makeFirstResponder(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { updateKeyboardFocus() }
    func windowDidResignKey(_ notification: Notification) {
        cancelEntryFocus()
        hasKeyboardFocus = false
        panel.makeFirstResponder(nil)
    }

    private func makePanelMenu() -> NSMenu {
        let menu = NSMenu()
        @discardableResult func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }
        if state.presentation == .list { add("Shrink to Pill", #selector(menuCollapse)) }
        else { add("Return to All Tasks", #selector(menuShowList)) }
        if state.focusedTaskID != nil {
            if state.presentation != .focusPill { add("Resume Focus", #selector(menuResumeFocus)) }
            add("Stop Focusing", #selector(menuStopFocus))
        }
        menu.addItem(.separator())
        add("Keep on Top", #selector(menuTogglePin)).state = preferences.pinned ? .on : .off
        add("Settings…", #selector(menuSettings))
        add("Hide Glint", #selector(menuHide))
        menu.addItem(.separator())
        add("Quit Glint", #selector(menuQuit), key: "q")
        return menu
    }
    @objc private func menuCollapse() { toggleCollapse() }
    @objc private func menuShowList() { showList() }
    @objc private func menuResumeFocus() { if let id = state.focusedTaskID { focus(on: id) } }
    @objc private func menuStopFocus() { stopFocusing() }
    @objc private func menuTogglePin() { preferences.pinned.toggle() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuHide() { hide() }
    @objc private func menuQuit() { quit() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidMove(_ notification: Notification) {
        if panel.recordDragMovement() { snapping.detach() }
        saveFrame()
    }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowWillStartLiveResize(_ notification: Notification) { prepareForManualResize() }

    private func saveFrame() {
        guard !changingFrame, snapTimer == nil else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
        state.saveSize(panel.frame.size, for: appliedPresentation)
    }

    private func restoreFrame() {
        changingFrame = true
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            let rect = NSRectFromString(saved)
            if rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 { panel.setFrame(rect, display: false) }
        } else { resetPosition() }
        appliedPresentation = state.presentation
        applySize(state.savedSize(for: state.presentation), presentation: state.presentation)
        changingFrame = false
        ensureReachable()
    }

    func toggleCollapse() {
        cancelEntryFocus()
        clearCompletionEffects()
        panel.makeFirstResponder(nil)
        transition { state.presentation == .list ? state.collapse() : state.showList() }
    }

    func showList() {
        cancelEntryFocus()
        clearCompletionEffects()
        panel.makeFirstResponder(nil)
        transition { state.showList() }
    }
    func focus(on id: UUID) {
        cancelEntryFocus()
        clearCompletionEffects()
        panel.makeFirstResponder(nil)
        transition { state.focus(on: id, activeTaskIDs: Set(store.active.map(\.id))) }
    }
    func stopFocusing() { clearCompletionEffects(); transition { state.stopFocusing() } }
    func completeFocusedTask() {
        guard let id = state.focusedTaskID, store.active.contains(where: { $0.id == id }) else { return }
        toggleTask(id)
        // Save now; the short visual handoff clears focus after its checkmark pop.
    }

    func toggleTask(_ id: UUID) {
        let wasActive = store.active.contains(where: { $0.id == id })
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fromFocus = wasActive && state.presentation == .focusPill && state.focusedTaskID == id
        if fromFocus && !reducedMotion { completingFocusID = id }
        store.toggle(id)
        guard wasActive, let record = store.snapshot().first(where: { $0.id == id && $0.completedAt != nil }) else {
            if completingFocusID == id { completingFocusID = nil }
            return
        }
        completionPulse += 1
        let effect = TaskCompletionEffect(record: record, fromFocus: fromFocus, reducedMotion: reducedMotion)
        completionTasks[id]?.cancel()
        completionEffects.removeAll { $0.id == id }
        completionEffects.append(effect)
        completionTasks[id] = Task { @MainActor [weak self] in
            do {
                if reducedMotion {
                    try await Task.sleep(for: .milliseconds(240))
                } else {
                    for step in 1...7 {
                        try await Task.sleep(for: .milliseconds(60))
                        guard let self, let index = self.completionEffects.firstIndex(where: { $0.token == effect.token }) else { return }
                        self.completionEffects[index].step = step
                        if step == 3 && self.completingFocusID == id { self.finishFocusCompletion() }
                    }
                    try await Task.sleep(for: .milliseconds(30))
                }
                self?.removeCompletionEffect(id)
            } catch { }
        }
    }

    private func finishFocusCompletion() {
        let id = completingFocusID
        completingFocusID = nil
        transition {
            // Even an immediate Undo restores the task without resuming focus.
            if let id, state.focusedTaskID == id { state.stopFocusing() }
            else { state.reconcile(activeTaskIDs: Set(store.active.map(\.id))) }
        }
    }

    private func removeCompletionEffect(_ id: UUID) {
        completionTasks.removeValue(forKey: id)?.cancel()
        completionEffects.removeAll { $0.id == id }
        if completingFocusID == id { finishFocusCompletion() }
    }

    private func clearCompletionEffects() {
        for task in completionTasks.values { task.cancel() }
        completionTasks.removeAll()
        completionEffects.removeAll()
        if completingFocusID != nil { finishFocusCompletion() }
    }

    private func transition(_ change: () -> Void) {
        guard !changingFrame else { return }
        cancelSnapAnimation(finish: true)
        state.saveSize(panel.frame.size, for: appliedPresentation)
        changingFrame = true
        change()
        if state.presentation != appliedPresentation {
            appliedPresentation = state.presentation
            applySize(state.savedSize(for: appliedPresentation), presentation: appliedPresentation)
        }
        changingFrame = false
        ensureReachable()
        saveFrame()
    }

    private func applySize(_ size: NSSize, presentation: PanelPresentation) {
        let frame = panel.frame
        // Widen constraints first so switching between compact and full sizes is valid.
        panel.maxSize = NSSize(width: 520, height: 850)
        panel.minSize = presentation.minimum
        panel.maxSize = presentation.maximum
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    func resetPosition() {
        cancelSnapAnimation(finish: false)
        snapping.detach()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 28, y: frame.maxY - panel.frame.height - 28))
        saveFrame()
    }

    @objc private func screensChanged() {
        cancelSnapAnimation(finish: false)
        ensureReachable()
    }
    @objc private func workspaceChanged() { ensureReachable() }
    @objc private func accessibilityChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            cancelSnapAnimation(finish: true)
            clearCompletionEffects()
        }
    }

    private var snapScreens: [SnapScreen] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let serial = CGDisplaySerialNumber(id)
            let identity = serial == 0 ? "display-\(id)" : "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(serial)"
            return SnapScreen(id: identity, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    func ensureReachable() {
        let corrected = snapping.reposition(panel.frame, screens: snapScreens)
        if corrected != panel.frame { panel.setFrame(corrected, display: true) }
        saveFrame()
    }

    private func prepareForManualResize() {
        cancelSnapAnimation(finish: true)
        snapping.detach()
    }

    private func finishUserDrag(bypass: Bool) {
        let screens = snapScreens
        let result = snapping.finishDrag(panel.frame, screens: screens, pointer: NSEvent.mouseLocation, bypass: bypass)
        let target = snapping.reposition(result, screens: screens)
        guard target != panel.frame else { saveFrame(); return }
        if snapping.attachment == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
            saveFrame()
            return
        }
        let origin = panel.frame
        let started = ProcessInfo.processInfo.systemUptime
        snapTarget = target
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.12)
                if progress >= 1 { self.cancelSnapAnimation(finish: true); return }
                let eased = 1 - pow(1 - progress, 3)
                self.panel.setFrameOrigin(NSPoint(x: origin.minX + (target.minX - origin.minX) * eased,
                                                 y: origin.minY + (target.minY - origin.minY) * eased))
            }
        }
        snapTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelSnapAnimation(finish: Bool) {
        snapTimer?.invalidate()
        snapTimer = nil
        let target = snapTarget
        snapTarget = nil
        if finish, let target { panel.setFrame(target, display: true) }
        if target != nil { saveFrame() }
    }

    func openSettings() {
        preferences.refreshLogin()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Glint Settings"
            window.backgroundColor = PixelPalette.paperNS
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, controller: self, snapping: snapping))
            window.center()
            settingsWindow = window
        }
        cancelEntryFocus()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Let native drag/resize regions serve the same app menu as the SwiftUI panel.
class PanelContextView: NSView {
    override func menu(for event: NSEvent) -> NSMenu? {
        (window as? GlintPanel)?.contextMenuProvider?() ?? super.menu(for: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        else { super.rightMouseDown(with: event) }
    }
    func handleControlClick(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control) else { return false }
        rightMouseDown(with: event)
        return true
    }
}

final class GlintHostingView<Content: View>: NSHostingView<Content> {
    override func menu(for event: NSEvent) -> NSMenu? {
        super.menu(for: event) ?? (window as? GlintPanel)?.contextMenuProvider?()
    }
}

struct WindowDragArea: NSViewRepresentable {
    var clicked: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.clicked = clicked; return view }
    func updateNSView(_ view: DragView, context: Context) { view.clicked = clicked }
    final class DragView: PanelContextView {
        var clicked: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            if handleControlClick(event) { return }
            guard let panel = window as? GlintPanel else { return }
            if !panel.performUserDrag(with: event) { clicked?() }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
    final class Handle: PanelContextView {
        override func mouseDown(with event: NSEvent) {
            if handleControlClick(event) { return }
            guard let window else { return }
            (window as? GlintPanel)?.onUserResizeBeginning?()
            let original = window.frame
            let start = NSEvent.mouseLocation
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let point = NSEvent.mouseLocation
                let width = min(window.maxSize.width, max(window.minSize.width, original.width + point.x - start.x))
                let height = min(window.maxSize.height, max(window.minSize.height, original.height - point.y + start.y))
                window.setFrame(NSRect(x: original.minX, y: original.maxY - height, width: width, height: height), display: true)
            }
        }
    }
}

/// Only the perimeter intercepts clicks, so the center stays available for moving,
/// expanding, and interacting with tasks. This also supports borderless panels.
struct WindowResizeBorder: NSViewRepresentable {
    func makeNSView(context: Context) -> BorderView { BorderView() }
    func updateNSView(_ view: BorderView, context: Context) { view.window?.invalidateCursorRects(for: view) }

    final class BorderView: PanelContextView {
        private let edgeWidth: CGFloat = 7
        private let cornerSize: CGFloat = 17

        private func edges(at point: NSPoint) -> PanelGeometry.Edges {
            guard bounds.contains(point) else { return [] }
            if point.x < cornerSize, point.y < cornerSize { return [.left, .bottom] }
            if point.x > bounds.width - cornerSize, point.y < cornerSize { return [.right, .bottom] }
            if point.x < cornerSize, point.y > bounds.height - cornerSize { return [.left, .top] }
            if point.x > bounds.width - cornerSize, point.y > bounds.height - cornerSize { return [.right, .top] }
            var edges: PanelGeometry.Edges = []
            let nearHorizontalEdge = point.y < edgeWidth || point.y > bounds.height - edgeWidth
            let nearVerticalEdge = point.x < edgeWidth || point.x > bounds.width - edgeWidth
            let xMargin = nearHorizontalEdge ? cornerSize : edgeWidth
            let yMargin = nearVerticalEdge ? cornerSize : edgeWidth
            if point.x < xMargin { edges.insert(.left) }
            else if point.x > bounds.width - xMargin { edges.insert(.right) }
            if point.y < yMargin { edges.insert(.bottom) }
            else if point.y > bounds.height - yMargin { edges.insert(.top) }
            return edges
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            edges(at: convert(point, from: superview)).isEmpty ? nil : self
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            let w = bounds.width, h = bounds.height, c = cornerSize, e = edgeWidth
            let regions: [(NSRect, NSCursor.FrameResizePosition)] = [
                (NSRect(x: 0, y: c, width: e, height: max(0, h - 2*c)), .left),
                (NSRect(x: w-e, y: c, width: e, height: max(0, h - 2*c)), .right),
                (NSRect(x: c, y: 0, width: max(0, w - 2*c), height: e), .bottom),
                (NSRect(x: c, y: h-e, width: max(0, w - 2*c), height: e), .top),
                (NSRect(x: 0, y: 0, width: c, height: c), .bottomLeft),
                (NSRect(x: w-c, y: 0, width: c, height: c), .bottomRight),
                (NSRect(x: 0, y: h-c, width: c, height: c), .topLeft),
                (NSRect(x: w-c, y: h-c, width: c, height: c), .topRight)
            ]
            for (rect, position) in regions { addCursorRect(rect, cursor: .frameResize(position: position, directions: .all)) }
        }

        override func mouseDown(with event: NSEvent) {
            if handleControlClick(event) { return }
            guard let window else { return }
            let selected = edges(at: convert(event.locationInWindow, from: nil))
            guard !selected.isEmpty else { return }
            (window as? GlintPanel)?.onUserResizeBeginning?()
            let original = window.frame
            let start = NSEvent.mouseLocation
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let point = NSEvent.mouseLocation
                let rect = PanelGeometry.resized(original, delta: CGSize(width: point.x - start.x, height: point.y - start.y), edges: selected, minimum: window.minSize, maximum: window.maxSize)
                window.setFrame(rect, display: true)
            }
            window.invalidateCursorRects(for: self)
        }
    }
}
