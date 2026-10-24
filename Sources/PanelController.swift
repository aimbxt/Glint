import AppKit
import SwiftUI
import Combine

final class GlintPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    let store: TaskStore
    let preferences: Preferences
    let shortcut = GlobalShortcut()
    var panel: GlintPanel!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var changingFrame = false
    @Published var focusRequest = UUID()
    @Published var visible = true

    init(store: TaskStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        super.init()
        let window = GlintPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 380), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel = window
        window.title = "Glint"
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        window.animationBehavior = .none
        window.delegate = self
        window.contentView = NSHostingView(rootView: TodoView(store: store, preferences: preferences, controller: self))
        updatePin()
        restoreFrame()
        preferences.$pinned.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updatePin() }
        }.store(in: &subscriptions)
        shortcut.onPress = { [weak self] in self?.toggleVisibility() }
        updateShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func updatePin() { panel.level = preferences.pinned ? .floating : .normal }
    func updateShortcut() {
        preferences.shortcutError = shortcut.register(key: preferences.shortcutKey, modifiers: preferences.shortcutModifiers) ? nil : "That shortcut is already in use or unavailable. Record a different combination."
    }

    func show(focus: Bool = true) {
        visible = true
        ensureReachable()
        if focus {
            if preferences.collapsed { toggleCollapse() }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            focusRequest = UUID()
        } else { panel.orderFrontRegardless() }
    }
    func hide() { panel.makeFirstResponder(nil); panel.orderOut(nil); visible = false }
    func toggleVisibility() { visible ? hide() : show() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard !changingFrame else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: preferences.collapsed ? "pillSize" : "expandedSize")
    }

    private func restoreFrame() {
        changingFrame = true
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            let rect = NSRectFromString(saved)
            if rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 { panel.setFrame(rect, display: false) }
        } else { resetPosition() }
        if preferences.collapsed {
            panel.minSize = PanelGeometry.pillMinimum
            panel.maxSize = PanelGeometry.pillMaximum
            let saved = UserDefaults.standard.string(forKey: "pillSize").map(NSSizeFromString) ?? panel.frame.size
            let size = PanelGeometry.pillSize(saved)
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: false)
        } else {
            panel.minSize = NSSize(width: 270, height: 240)
            panel.maxSize = NSSize(width: 520, height: 850)
        }
        changingFrame = false
        ensureReachable()
    }

    func toggleCollapse() {
        panel.makeFirstResponder(nil)
        let oldFrame = panel.frame
        UserDefaults.standard.set(NSStringFromSize(oldFrame.size), forKey: preferences.collapsed ? "pillSize" : "expandedSize")
        changingFrame = true
        preferences.collapsed.toggle()
        let size: NSSize
        if preferences.collapsed {
            let saved = UserDefaults.standard.string(forKey: "pillSize").map(NSSizeFromString) ?? PanelGeometry.pillDefault
            size = PanelGeometry.pillSize(saved)
            panel.minSize = PanelGeometry.pillMinimum
            panel.maxSize = PanelGeometry.pillMaximum
        } else {
            panel.minSize = NSSize(width: 270, height: 240)
            panel.maxSize = NSSize(width: 520, height: 850)
            let saved = UserDefaults.standard.string(forKey: "expandedSize").map(NSSizeFromString) ?? NSSize(width: 300, height: 380)
            size = NSSize(width: min(520, max(270, saved.width)), height: min(850, max(240, saved.height)))
        }
        panel.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.maxY - size.height, width: size.width, height: size.height), display: true)
        changingFrame = false
        ensureReachable()
        saveFrame()
    }

    func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 28, y: frame.maxY - panel.frame.height - 28))
        saveFrame()
    }

    @objc private func screensChanged() { ensureReachable() }
    func ensureReachable() {
        guard !NSScreen.screens.isEmpty else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = lhs.visibleFrame.intersection(frame)
            let b = rhs.visibleFrame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }!
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var corrected = frame
        corrected.size.width = min(frame.width, bounds.width)
        corrected.size.height = min(frame.height, bounds.height)
        corrected.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - corrected.width))
        corrected.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - corrected.height))
        if corrected != frame { panel.setFrame(corrected, display: true) }
    }

    func openSettings() {
        preferences.refreshLogin()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Glint Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, controller: self))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

struct WindowDragArea: NSViewRepresentable {
    var clicked: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.clicked = clicked; return view }
    func updateNSView(_ view: DragView, context: Context) { view.clicked = clicked }
    final class DragView: NSView {
        var clicked: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            let origin = window?.frame.origin
            window?.performDrag(with: event)
            if origin == window?.frame.origin { clicked?() }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
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

    final class BorderView: NSView {
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
            guard let window else { return }
            let selected = edges(at: convert(event.locationInWindow, from: nil))
            guard !selected.isEmpty else { return }
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
