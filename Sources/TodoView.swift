import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TodoView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: PanelController
    @ObservedObject var state: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTask = ""
    @State private var completedExpanded = false
    @State private var celebrationFrame = 0
    @State private var celebrationTask: Task<Void, Never>?
    @FocusState private var entryFocused: Bool

    var body: some View {
        Group {
            switch state.presentation {
            case .list: card
            case .countPill: pill
            case .focusPill:
                if let item = store.active.first(where: { $0.id == state.focusedTaskID }) { focusPill(item) }
                else { pill }
            }
        }
        .foregroundStyle(PixelPalette.ink)
        .pixelChrome(compact: state.presentation.isCompact)
        .overlay(WindowResizeBorder().accessibilityHidden(true))
        .tint(PixelPalette.accent)
        .environment(\.readablePixelText, preferences.readableText)
        .onChange(of: controller.focusRequest) { _, _ in entryFocused = true }
        .onChange(of: controller.completionPulse) { _, _ in celebrate() }
        .onDisappear { celebrationTask?.cancel() }
        .alert("Couldn’t save your task", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var pill: some View {
        HStack(spacing: 8) {
            PixelIcon(glyph: celebrationFrame > 0 ? .checked : .spark, size: 16, color: celebrationFrame > 0 ? PixelPalette.accent : PixelPalette.gold)
            Text("\(store.active.count) \(store.active.count == 1 ? "task" : "tasks") left").pixelFont(14).lineLimit(1)
            PixelIcon(glyph: .expand, size: 12, color: PixelPalette.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(WindowDragArea(clicked: { controller.toggleCollapse() }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.active.count) tasks left. Expand Glint")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.toggleCollapse() }
        .contextMenu {
            Button("Expand") { controller.toggleCollapse() }
            Button("Hide Glint") { controller.hide() }
            Divider()
            Button("Quit Glint") { controller.quit() }
        }
    }

    private func focusPill(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Button { controller.completeFocusedTask() } label: {
                PixelIcon(glyph: .checkbox, size: 18)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PixelButtonStyle(raised: false))
            .help("Complete task")
            .accessibilityLabel("Complete \(item.text)")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    WindowDragArea()
                    Text(item.text)
                        .pixelFont(16)
                        .lineSpacing(3)
                        .lineLimit(max(1, Int(proxy.size.height / 22)))
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Focused task: \(item.text)")
                }
                .clipped()
                .help(item.text)
            }

            Button { controller.showList() } label: {
                PixelIcon(glyph: .list, size: 18)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PixelButtonStyle())
            .help("Return to all tasks")
            .accessibilityLabel("Return to all tasks")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Return to All Tasks") { controller.showList() }
            Button("Stop Focusing") { controller.stopFocusing() }
            Divider()
            Button("Hide Glint") { controller.hide() }
            Divider()
            Button("Quit Glint") { controller.quit() }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    WindowDragArea()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("To-do").pixelFont(20, weight: .semibold)
                        Text("\(store.active.count)").pixelFont(14)
                            .foregroundStyle(PixelPalette.secondary).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(PixelPalette.inset)
                            .overlay(alignment: .topTrailing) {
                                if celebrationFrame > 0 {
                                    PixelIcon(glyph: .spark, size: celebrationFrame == 1 ? 9 : 12, color: PixelPalette.gold)
                                        .offset(x: 8, y: -6)
                                }
                            }
                    }.allowsHitTesting(false)
                }.frame(height: 46)
                Button { controller.toggleCollapse() } label: {
                    PixelIcon(glyph: .collapse, size: 20, color: PixelPalette.ink)
                        .frame(width: 38, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PixelButtonStyle()).help("Shrink to pill").accessibilityLabel("Shrink to pill")
                Menu {
                    Toggle("Keep on top", isOn: $preferences.pinned)
                    if let id = state.focusedTaskID {
                        Divider()
                        Button("Resume Focus") { controller.focus(on: id) }
                        Button("Stop Focusing") { controller.stopFocusing() }
                    }
                    Divider()
                    Button("Undo") { store.undoManager.undo() }.disabled(!store.undoManager.canUndo)
                    Button("Redo") { store.undoManager.redo() }.disabled(!store.undoManager.canRedo)
                    Divider()
                    Button("Settings…") { controller.openSettings() }
                    Button("Hide Glint") { controller.hide() }
                    Button("Quit Glint") { controller.quit() }
                } label: {
                    Image(nsImage: PixelBrand.image(.more))
                        .renderingMode(.template).foregroundStyle(PixelPalette.ink)
                        .frame(width: 32, height: 36).modifier(PixelControlFace())
                }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options").accessibilityLabel("More options")
                Button { controller.quit() } label: {
                    PixelIcon(glyph: .close, size: 14, color: PixelPalette.ink)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(PixelButtonStyle()).help("Quit Glint").accessibilityLabel("Quit Glint")
            }.padding(.horizontal, 16).padding(.top, 10)

            Rectangle().fill(PixelPalette.edge).frame(height: 2).padding(.horizontal, 16).padding(.top, 4)

            ScrollView {
                VStack(spacing: 3) {
                    if store.items.isEmpty {
                        VStack(spacing: 12) {
                            PixelIcon(glyph: .spark, size: 36, color: PixelPalette.gold)
                            Text("A little room to think.").pixelFont(16)
                            Text("Add one thing. Start there.").pixelFont(14).foregroundStyle(PixelPalette.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(store.active) { item in
                        TaskRow(item: item, store: store, controller: controller, state: state)
                            .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                let target = item.id
                                _ = provider.loadObject(ofClass: String.self) { value, _ in
                                    guard let value, let id = UUID(uuidString: value) else { return }
                                    DispatchQueue.main.async { store.move(id, before: target) }
                                }
                                return true
                            }
                    }
                    if !store.completed.isEmpty {
                        VStack(spacing: 0) {
                            Button { completedExpanded.toggle() } label: {
                                HStack(spacing: 8) {
                                    PixelIcon(glyph: completedExpanded ? .down : .right, size: 12, color: PixelPalette.secondary)
                                    Text("Completed · \(store.completed.count)").pixelFont(14)
                                    Spacer()
                                }.foregroundStyle(PixelPalette.secondary).padding(.vertical, 8)
                            }
                            .buttonStyle(PixelButtonStyle(raised: false))
                            .accessibilityLabel("Completed tasks, \(store.completed.count)")
                            .accessibilityValue(completedExpanded ? "Expanded" : "Collapsed")
                            if completedExpanded {
                                VStack(spacing: 3) {
                                    ForEach(store.completed) { item in TaskRow(item: item, store: store, controller: controller, state: state) }
                                }.padding(.top, 5)
                            }
                        }.padding(.horizontal, 9).padding(.top, 12).padding(.bottom, 6)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 12)
            }.scrollIndicators(.hidden)

            HStack(spacing: 9) {
                PixelIcon(glyph: .plus, size: 16)
                TextField("Add a task…", text: $newTask)
                    .textFieldStyle(.plain).pixelFont(16).focused($entryFocused)
                    .onSubmit {
                        store.add(newTask)
                        if store.errorMessage == nil { newTask = "" }
                        entryFocused = true
                    }.accessibilityLabel("Add a task")
            }
            .padding(12).background(PixelPalette.inset)
            .overlay(Rectangle().strokeBorder(entryFocused ? PixelPalette.accent : PixelPalette.edge.opacity(0.65), lineWidth: entryFocused ? 2 : 1))
            .padding(.horizontal, 16).padding(.bottom, 18).padding(.top, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            PixelIcon(glyph: .grip, size: 12, color: PixelPalette.secondary)
                .frame(width: 18, height: 18).overlay(ResizeHandle()).help("Drag to resize")
        }
    }

    private func celebrate() {
        celebrationTask?.cancel()
        celebrationTask = Task { @MainActor in
            celebrationFrame = 1
            do {
                if !reduceMotion {
                    try await Task.sleep(for: .milliseconds(120))
                    celebrationFrame = 2
                }
                try await Task.sleep(for: .milliseconds(240))
                celebrationFrame = 0
            } catch { }
        }
    }
}

struct TaskRow: View {
    let item: TodoItem
    @ObservedObject var store: TaskStore
    let controller: PanelController
    @ObservedObject var state: PanelState
    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool
    @FocusState private var optionsFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                controller.toggleTask(item.id)
            } label: {
                PixelIcon(glyph: item.completedAt == nil ? .checkbox : .checked, size: 18,
                          color: item.completedAt == nil ? PixelPalette.edge : PixelPalette.accent)
                    .frame(width: 32, height: 32)
            }.buttonStyle(PixelButtonStyle(raised: false)).accessibilityLabel(item.completedAt == nil ? "Complete \(item.text)" : "Reopen \(item.text)")

            Group {
                if editing {
                    TextField("Task", text: $draft, axis: .vertical).textFieldStyle(.plain).focused($editFocused)
                        .onSubmit { commit() }.onExitCommand { editing = false; editFocused = false }
                        .onChange(of: editFocused) { _, value in if !value { commit() } }
                } else {
                    Text(item.text).strikethrough(item.completedAt != nil).foregroundStyle(item.completedAt == nil ? PixelPalette.ink : PixelPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .accessibilityAddTraits(.isButton).accessibilityAction(named: "Edit task") { beginEditing() }
                }
            }.pixelFont(16).lineSpacing(3).padding(.top, 4)

            if state.focusedTaskID == item.id {
                PixelIcon(glyph: .focus, size: 12, color: PixelPalette.gold).frame(height: 32)
                    .help("Focused task").accessibilityHidden(false).accessibilityLabel("Focused task")
            }

            Menu {
                Button("Edit") { beginEditing() }
                if item.completedAt == nil {
                    focusActions
                    Divider()
                    Button("Move Up") { store.move(item.id, offset: -1) }.disabled(store.active.first?.id == item.id)
                    Button("Move Down") { store.move(item.id, offset: 1) }.disabled(store.active.last?.id == item.id)
                }
                Divider()
                Button("Delete", role: .destructive) { delete() }
            } label: {
                Image(nsImage: PixelBrand.image(.more))
                    .renderingMode(.template).foregroundStyle(PixelPalette.secondary)
                    .frame(width: 24, height: 32)
            }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .focused($optionsFocused)
                .opacity(hovered || editing || accessibilityFocused || optionsFocused ? 1 : 0.65)
                .accessibilityLabel("Options for \(item.text)")
                .accessibilityFocused($accessibilityFocused)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(hovered ? PixelPalette.inset : Color.clear)
        .onHover { hovered = $0 }
        .contextMenu {
            if item.completedAt == nil { focusActions; Divider() }
            Button("Edit") { beginEditing() }
            Button("Delete", role: .destructive) { delete() }
            Divider()
            Button("Quit Glint") { controller.quit() }
        }
        .onDisappear { if editing { commit() } }
    }
    @ViewBuilder private var focusActions: some View {
        if state.focusedTaskID == item.id {
            Button("Resume Focus") { focus() }
            Button("Stop Focusing") { controller.stopFocusing() }
        } else {
            Button("Focus on This Task") { focus() }
        }
    }
    private func focus() {
        let id = item.id
        if editing { commit() }
        guard store.errorMessage == nil else { return }
        controller.focus(on: id)
    }
    private func beginEditing() { draft = item.text; editing = true; editFocused = true }
    private func delete() {
        let id = item.id
        editing = false
        editFocused = false
        store.delete(id)
    }
    private func commit() {
        guard editing else { return }
        editing = false
        store.edit(item.id, text: draft)
    }
}
