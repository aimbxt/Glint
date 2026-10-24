import Foundation
import CoreGraphics
import Combine

enum PanelPresentation: CaseIterable {
    case list, countPill, focusPill

    var isCompact: Bool { self != .list }
    var sizeKey: String {
        switch self {
        case .list: return "expandedSize"
        case .countPill: return "pillSize"
        case .focusPill: return "focusPillSize"
        }
    }
    var minimum: CGSize {
        switch self {
        case .list: return CGSize(width: 270, height: 240)
        case .countPill: return PanelGeometry.pillMinimum
        case .focusPill: return CGSize(width: 240, height: 48)
        }
    }
    var maximum: CGSize {
        self == .list ? CGSize(width: 520, height: 850) : CGSize(width: 520, height: 180)
    }
    var defaultSize: CGSize {
        switch self {
        case .list: return CGSize(width: 300, height: 380)
        case .countPill: return PanelGeometry.pillDefault
        case .focusPill: return CGSize(width: 320, height: 64)
        }
    }
    func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.isFinite ? min(maximum.width, max(minimum.width, size.width)) : defaultSize.width,
               height: size.height.isFinite ? min(maximum.height, max(minimum.height, size.height)) : defaultSize.height)
    }
}

/// Focus is a presentation preference, independent of the task undo history.
@MainActor
final class PanelState: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var presentation: PanelPresentation {
        didSet { defaults.set(presentation.isCompact, forKey: "collapsed") }
    }
    @Published private(set) var focusedTaskID: UUID? {
        didSet {
            if let focusedTaskID { defaults.set(focusedTaskID.uuidString, forKey: "focusedTaskID") }
            else { defaults.removeObject(forKey: "focusedTaskID") }
        }
    }

    init(defaults: UserDefaults = .standard, activeTaskIDs: Set<UUID>) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "focusedTaskID").flatMap(UUID.init(uuidString:))
        let selected = saved.flatMap { activeTaskIDs.contains($0) ? $0 : nil }
        focusedTaskID = selected
        presentation = defaults.bool(forKey: "collapsed") ? (selected == nil ? .countPill : .focusPill) : .list
        if focusedTaskID == nil { defaults.removeObject(forKey: "focusedTaskID") }
    }

    func focus(on id: UUID, activeTaskIDs: Set<UUID>) {
        guard activeTaskIDs.contains(id) else { return }
        focusedTaskID = id
        presentation = .focusPill
    }
    func showList() { presentation = .list }
    func collapse() { presentation = focusedTaskID == nil ? .countPill : .focusPill }
    func stopFocusing() {
        focusedTaskID = nil
        if presentation == .focusPill { presentation = .countPill }
    }
    func reconcile(activeTaskIDs: Set<UUID>) {
        if let focusedTaskID, !activeTaskIDs.contains(focusedTaskID) { stopFocusing() }
    }

    func saveSize(_ size: CGSize, for presentation: PanelPresentation) {
        defaults.set(NSStringFromSize(presentation.clamped(size)), forKey: presentation.sizeKey)
    }
    func savedSize(for presentation: PanelPresentation) -> CGSize {
        presentation.clamped(defaults.string(forKey: presentation.sizeKey).map(NSSizeFromString) ?? presentation.defaultSize)
    }
}
