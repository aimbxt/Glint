import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: PanelController
    @ObservedObject var snapping: SnapState
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                PixelIcon(glyph: .spark, size: 36, color: PixelPalette.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glint").pixelFont(24, weight: .semibold)
                    Text("A little clarity, always nearby.").pixelFont(14).foregroundStyle(PixelPalette.secondary)
                }
            }
            HStack {
                Text("Show / hide shortcut")
                Spacer()
                Button(recording ? "Press shortcut…" : preferences.shortcutLabel) { recording.toggle() }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .modifier(PixelControlFace(selected: recording))
                    .buttonStyle(.plain)
                    .overlay {
                        if recording {
                            ShortcutRecorder { key, modifiers in
                                recording = false
                                guard let key, let modifiers else { return }
                                preferences.shortcutKey = key
                                preferences.shortcutModifiers = modifiers
                                controller.updateShortcut()
                            }.frame(width: 1, height: 1)
                        }
                    }
            }
            if recording {
                Text("Use Control or Command with a letter, number, or Space. Escape cancels.")
                    .pixelFont(14).foregroundStyle(PixelPalette.secondary)
            }
            if let error = preferences.shortcutError { Text(error).pixelFont(14).foregroundStyle(PixelPalette.danger) }
            Toggle("Readable text", isOn: $preferences.readableText)
                .help("Use the system font while keeping the pixel-art theme.")
            Toggle("Snap to screen edges", isOn: $snapping.enabled)
                .help("Snap on release near an edge or corner. Hold Option to bypass.")
            Toggle("Launch Glint at login", isOn: Binding(get: { preferences.loginEnabled }, set: { preferences.setLogin($0) }))
            if let error = preferences.loginError { Text(error).pixelFont(14).foregroundStyle(PixelPalette.secondary).fixedSize(horizontal: false, vertical: true) }
            Rectangle().fill(PixelPalette.edge).frame(height: 2)
            HStack {
                Text("Tasks stay on this Mac.").pixelFont(14).foregroundStyle(PixelPalette.secondary)
                Spacer()
                Button("Reset panel position") { controller.resetPosition(); controller.show(focus: false) }
                    .pixelFont(14).padding(.horizontal, 8).padding(.vertical, 6)
                    .buttonStyle(PixelButtonStyle())
            }
        }
        .toggleStyle(.checkbox)
        .pixelFont(16).foregroundStyle(PixelPalette.ink).tint(PixelPalette.accent)
        .padding(24).frame(width: 430)
        .background(PixelPalette.paper)
        .environment(\.readablePixelText, preferences.readableText)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in preferences.refreshLogin() }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var recorded: (UInt32?, UInt32?) -> Void
    func makeNSView(context: Context) -> Recorder {
        let view = Recorder()
        view.recorded = recorded
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: Recorder, context: Context) { view.recorded = recorded }
    final class Recorder: NSView {
        var recorded: ((UInt32?, UInt32?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self { keyDown(with: event); return true }
            return false
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { recorded?(nil, nil); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let supported: Set<UInt16> = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6,18,19,20,21,23,22,26,28,25,29,49]
            guard supported.contains(event.keyCode), flags.contains(.control) || flags.contains(.command) else { NSSound.beep(); return }
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            recorded?(UInt32(event.keyCode), modifiers)
        }
    }
}
