import Foundation
import SwiftData
import Combine
import Observation

// Explicit SwiftData model expansion for Command Line Tools, which omit Apple's
// SwiftDataMacros plugin. Xcode builds use the standard @Model declaration below.
#if GLINT_CLI_BUILD
final class TodoItem: PersistentModel {
    var persistentBackingData: any BackingData<TodoItem> = TodoItem.createBackingData()
    private let registrar = ObservationRegistrar()

    init(backingData: any BackingData<TodoItem>) { persistentBackingData = backingData }
    var id: UUID {
        get { registrar.access(self, keyPath: \.id); return getValue(forKey: \.id) }
        set { registrar.withMutation(of: self, keyPath: \.id) { setValue(forKey: \.id, to: newValue) } }
    }
    var text: String {
        get { registrar.access(self, keyPath: \.text); return getValue(forKey: \.text) }
        set { registrar.withMutation(of: self, keyPath: \.text) { setValue(forKey: \.text, to: newValue) } }
    }
    var order: Int {
        get { registrar.access(self, keyPath: \.order); return getValue(forKey: \.order) }
        set { registrar.withMutation(of: self, keyPath: \.order) { setValue(forKey: \.order, to: newValue) } }
    }
    var createdAt: Date {
        get { registrar.access(self, keyPath: \.createdAt); return getValue(forKey: \.createdAt) }
        set { registrar.withMutation(of: self, keyPath: \.createdAt) { setValue(forKey: \.createdAt, to: newValue) } }
    }
    var completedAt: Date? {
        get { registrar.access(self, keyPath: \.completedAt); return getValue(forKey: \.completedAt) }
        set { registrar.withMutation(of: self, keyPath: \.completedAt) { setValue(forKey: \.completedAt, to: newValue) } }
    }
    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            .init(name: "id", keypath: \TodoItem.id, metadata: Schema.Attribute(.unique)),
            .init(name: "text", keypath: \TodoItem.text),
            .init(name: "order", keypath: \TodoItem.order),
            .init(name: "createdAt", keypath: \TodoItem.createdAt),
            .init(name: "completedAt", keypath: \TodoItem.completedAt),
        ]
    }
    init(id: UUID = UUID(), text: String, order: Int, createdAt: Date = .now, completedAt: Date? = nil) {
        persistentBackingData.setValue(forKey: \.id, to: id)
        persistentBackingData.setValue(forKey: \.text, to: text)
        persistentBackingData.setValue(forKey: \.order, to: order)
        persistentBackingData.setValue(forKey: \.createdAt, to: createdAt)
        persistentBackingData.setValue(forKey: \.completedAt, to: completedAt)
    }
}
#else
@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var order: Int
    var createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(), text: String, order: Int, createdAt: Date = .now, completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.order = order
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

#endif

struct TaskRecord: Equatable {
    var id: UUID
    var text: String
    var order: Int
    var createdAt: Date
    var completedAt: Date?
}

@MainActor
final class TaskStore: ObservableObject {
    let container: ModelContainer
    let context: ModelContext
    let undoManager = UndoManager()
    @Published private(set) var items: [TodoItem] = []
    @Published var errorMessage: String?
    @Published private(set) var revision = 0

    var active: [TodoItem] { items.filter { $0.completedAt == nil } }
    var completed: [TodoItem] {
        items.filter { $0.completedAt != nil }.sorted { $0.completedAt! > $1.completedAt! }
    }

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, groupContainer: .none, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: TodoItem.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        undoManager.groupsByEvent = false
        try reload()
    }

    private func reload() throws {
        items = try context.fetch(FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\TodoItem.order), SortDescriptor(\TodoItem.createdAt)]))
        revision += 1
    }

    func snapshot() -> [TaskRecord] {
        items.map { TaskRecord(id: $0.id, text: $0.text, order: $0.order, createdAt: $0.createdAt, completedAt: $0.completedAt) }
    }

    private func recordUndo(_ state: [TaskRecord], name: String) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.restore(state, name: name) } }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    private func change(_ name: String, _ operation: () -> Void) {
        let previous = snapshot()
        operation()
        do {
            try context.save()
            try reload()
            if snapshot() != previous { recordUndo(previous, name: name) }
        } catch {
            context.rollback()
            try? reload()
            errorMessage = "Your change couldn’t be saved. \(error.localizedDescription)"
        }
    }

    private func restore(_ state: [TaskRecord], name: String) {
        let previous = snapshot()
        let ids = Set(state.map(\.id))
        for item in items where !ids.contains(item.id) { context.delete(item) }
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for record in state {
            if let item = existing[record.id] {
                item.text = record.text
                item.order = record.order
                item.createdAt = record.createdAt
                item.completedAt = record.completedAt
            } else {
                context.insert(TodoItem(id: record.id, text: record.text, order: record.order, createdAt: record.createdAt, completedAt: record.completedAt))
            }
        }
        do {
            try context.save()
            try reload()
            recordUndo(previous, name: name)
        } catch {
            context.rollback()
            try? reload()
            errorMessage = "Undo couldn’t be saved. \(error.localizedDescription)"
        }
    }

    func add(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        change("Add Task") { context.insert(TodoItem(text: clean, order: (items.map(\.order).max() ?? -1) + 1)) }
    }

    func edit(_ id: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let item = items.first(where: { $0.id == id }), item.text != clean else { return }
        change("Edit Task") { item.text = clean }
    }

    func toggle(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        change(item.completedAt == nil ? "Complete Task" : "Reopen Task") {
            item.completedAt = item.completedAt == nil ? .now : nil
        }
    }

    func delete(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        change("Delete Task") { context.delete(item) }
    }

    func move(_ source: UUID, before target: UUID) {
        var ordered = active.map(\.id)
        guard source != target, let index = ordered.firstIndex(of: source), ordered.contains(target) else { return }
        ordered.remove(at: index)
        ordered.insert(source, at: ordered.firstIndex(of: target)!)
        change("Reorder Tasks") {
            for (position, id) in ordered.enumerated() { items.first { $0.id == id }?.order = position }
            for (position, item) in completed.enumerated() { item.order = ordered.count + position }
        }
    }

    func move(_ id: UUID, offset: Int) {
        let ordered = active.map(\.id)
        guard let index = ordered.firstIndex(of: id), ordered.indices.contains(index + offset) else { return }
        if offset < 0 { move(id, before: ordered[index + offset]) }
        else { move(ordered[index + offset], before: id) }
    }
}
