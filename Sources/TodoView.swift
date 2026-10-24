import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let glintAccent = Color(red: 0.22, green: 0.64, blue: 0.52)

private struct PanelShape: Shape {
    var collapsed: Bool
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: collapsed ? min(rect.width, rect.height) / 2 : 24).path(in: rect)
    }
}

struct GlassSurface: View {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .windowBackgroundColor))
        } else {
            // The source also builds with the macOS 15 SDK shipped with Command Line Tools.
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else {
                frosted
            }
            #else
            frosted
            #endif
        }
    }
    private var frosted: some View {
        VisualEffect().clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).fill(.primary.opacity(0.025)))
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct TodoView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: PanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTask = ""
    @State private var completedExpanded = false
    @FocusState private var entryFocused: Bool

    var body: some View {
        Group {
            if preferences.collapsed { pill } else { card }
        }
        .background {
            GeometryReader { proxy in
                GlassSurface(radius: preferences.collapsed ? min(proxy.size.width, proxy.size.height) / 2 : 24)
            }
        }
        .clipShape(PanelShape(collapsed: preferences.collapsed))
        .overlay(PanelShape(collapsed: preferences.collapsed).stroke(.white.opacity(0.22), lineWidth: 0.75).allowsHitTesting(false))
        .overlay(WindowResizeBorder().accessibilityHidden(true))
        .tint(glintAccent)
        .onChange(of: controller.focusRequest) { _, _ in entryFocused = true }
        .alert("Couldn’t save your task", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var pill: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle").foregroundStyle(glintAccent)
            Text("\(store.active.count) \(store.active.count == 1 ? "task" : "tasks") left").font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(WindowDragArea(clicked: { controller.toggleCollapse() }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.active.count) tasks left. Expand Glint")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.toggleCollapse() }
        .contextMenu { Button("Expand") { controller.toggleCollapse() }; Button("Hide") { controller.hide() } }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    WindowDragArea()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("To-do").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("\(store.active.count)").font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.primary.opacity(0.055), in: Capsule())
                    }.allowsHitTesting(false)
                }.frame(height: 46)
                Button { controller.toggleCollapse() } label: {
                    Image(systemName: "capsule.lefthalf.filled")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: 38, height: 36)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Shrink to pill").accessibilityLabel("Shrink to pill")
                Menu {
                    Toggle("Keep on top", isOn: $preferences.pinned)
                    Divider()
                    Button("Undo") { store.undoManager.undo() }.disabled(!store.undoManager.canUndo)
                    Button("Redo") { store.undoManager.redo() }.disabled(!store.undoManager.canRedo)
                    Divider()
                    Button("Settings…") { controller.openSettings() }
                    Button("Hide Glint") { controller.hide() }
                    Button("Quit Glint") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 23, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options").accessibilityLabel("More options")
            }.padding(.horizontal, 19).padding(.top, 10)

            Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 18).padding(.top, 4)

            ScrollView {
                VStack(spacing: 3) {
                    if store.items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sun.max").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(glintAccent.opacity(0.8))
                            Text("A little room to think.").font(.system(size: 14, weight: .medium, design: .rounded))
                            Text("Add one thing. Start there.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 58)
                    }
                    ForEach(store.active) { item in
                        TaskRow(item: item, store: store, reduceMotion: reduceMotion)
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
                        DisclosureGroup(isExpanded: $completedExpanded) {
                            VStack(spacing: 3) {
                                ForEach(store.completed) { item in TaskRow(item: item, store: store, reduceMotion: reduceMotion) }
                            }.padding(.top, 5)
                        } label: {
                            Text("Completed · \(store.completed.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 9).padding(.top, 12).padding(.bottom, 6)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 12)
            }.scrollIndicators(.hidden)

            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(glintAccent)
                TextField("Add a task…", text: $newTask)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($entryFocused)
                    .onSubmit {
                        store.add(newTask)
                        if store.errorMessage == nil { newTask = "" }
                        entryFocused = true
                    }.accessibilityLabel("Add a task")
            }
            .padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(entryFocused ? 0.12 : 0.03), lineWidth: 0.75))
            .padding(.horizontal, 16).padding(.bottom, 18).padding(.top, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 8)).rotationEffect(.degrees(-45)).foregroundStyle(.tertiary)
                .frame(width: 18, height: 18).overlay(ResizeHandle()).help("Drag to resize")
        }
    }
}

struct TaskRow: View {
    let item: TodoItem
    @ObservedObject var store: TaskStore
    let reduceMotion: Bool
    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool
    @FocusState private var optionsFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { store.toggle(item.id) }
            } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(item.completedAt == nil ? Color.primary.opacity(0.30) : glintAccent)
                    .frame(width: 22, height: 22)
            }.buttonStyle(.plain).accessibilityLabel(item.completedAt == nil ? "Complete \(item.text)" : "Reopen \(item.text)")

            Group {
                if editing {
                    TextField("Task", text: $draft, axis: .vertical).textFieldStyle(.plain).focused($editFocused)
                        .onSubmit { commit() }.onExitCommand { editing = false; editFocused = false }
                        .onChange(of: editFocused) { _, value in if !value { commit() } }
                } else {
                    Text(item.text).strikethrough(item.completedAt != nil).foregroundStyle(item.completedAt == nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .accessibilityAddTraits(.isButton).accessibilityAction(named: "Edit task") { beginEditing() }
                }
            }.font(.system(size: 13)).lineSpacing(3).padding(.top, 2)

            Menu {
                Button("Edit") { beginEditing() }
                if item.completedAt == nil {
                    Button("Move Up") { store.move(item.id, offset: -1) }.disabled(store.active.first?.id == item.id)
                    Button("Move Down") { store.move(item.id, offset: 1) }.disabled(store.active.last?.id == item.id)
                }
                Divider()
                Button("Delete", role: .destructive) { delete() }
            } label: { Image(systemName: "ellipsis").frame(width: 15, height: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .focused($optionsFocused)
                .opacity(hovered || editing || accessibilityFocused || optionsFocused ? 1 : 0.15)
                .accessibilityLabel("Options for \(item.text)")
                .accessibilityFocused($accessibilityFocused)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Edit") { beginEditing() }
            Button("Delete", role: .destructive) { delete() }
        }
        .onDisappear { if editing { commit() } }
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
