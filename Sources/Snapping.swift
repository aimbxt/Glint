import Foundation
import CoreGraphics
import Combine

struct SnapScreen: Equatable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
}

struct SnapAttachment: Codable, Equatable {
    enum Horizontal: String, Codable { case left, right }
    enum Vertical: String, Codable { case bottom, top }
    let displayID: String
    var horizontal: Horizontal?
    var vertical: Vertical?
}

enum SnapGeometry {
    static let gap: CGFloat = 16
    static let threshold: CGFloat = 18

    static func screen(for frame: CGRect, screens: [SnapScreen], pointer: CGPoint? = nil) -> SnapScreen? {
        func area(_ screen: SnapScreen) -> CGFloat {
            let overlap = screen.frame.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        let largest = screens.map(area).max() ?? 0
        let tied = screens.filter { area($0) == largest }
        if let pointer, let underPointer = tied.first(where: { $0.frame.contains(pointer) }) { return underPointer }
        if largest > 0 { return tied.first }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min {
            hypot($0.frame.midX - center.x, $0.frame.midY - center.y) < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
        }
    }

    static func snap(_ frame: CGRect, to screen: SnapScreen) -> (frame: CGRect, attachment: SnapAttachment)? {
        let bounds = screen.visibleFrame.insetBy(dx: gap, dy: gap)
        var attachment = SnapAttachment(displayID: screen.id)
        if frame.width <= bounds.width {
            let left = abs(frame.minX - bounds.minX), right = abs(frame.maxX - bounds.maxX)
            if min(left, right) <= threshold { attachment.horizontal = left <= right ? .left : .right }
        }
        if frame.height <= bounds.height {
            let bottom = abs(frame.minY - bounds.minY), top = abs(frame.maxY - bounds.maxY)
            if min(bottom, top) <= threshold { attachment.vertical = bottom <= top ? .bottom : .top }
        }
        guard attachment.horizontal != nil || attachment.vertical != nil else { return nil }
        return (anchored(frame, attachment: attachment, screen: screen), attachment)
    }

    static func anchored(_ frame: CGRect, attachment: SnapAttachment, screen: SnapScreen) -> CGRect {
        let bounds = screen.visibleFrame.insetBy(dx: gap, dy: gap)
        var target = frame
        switch attachment.horizontal {
        case .left: target.origin.x = bounds.minX
        case .right: target.origin.x = bounds.maxX - frame.width
        case nil: break
        }
        switch attachment.vertical {
        case .bottom: target.origin.y = bounds.minY
        case .top: target.origin.y = bounds.maxY - frame.height
        case nil: break
        }
        return target
    }

    static func reachable(_ frame: CGRect, on screen: SnapScreen) -> CGRect {
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        guard bounds.width > 0, bounds.height > 0 else { return frame }
        var result = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = max(bounds.minX, min(result.minX, bounds.maxX - result.width))
        result.origin.y = max(bounds.minY, min(result.minY, bounds.maxY - result.height))
        return result
    }
}

/// Remember whether a drag ever moved, even when it ends at its starting point.
struct WindowDragMovement {
    let origin: CGPoint
    private(set) var didDrag = false
    @discardableResult mutating func record(_ point: CGPoint) -> Bool {
        let crossed = !didDrag && hypot(point.x - origin.x, point.y - origin.y) >= 3
        didDrag = didDrag || crossed
        return crossed
    }
}

@MainActor
final class SnapState: ObservableObject {
    private let defaults: UserDefaults
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "snapToEdges")
            if !enabled { detach() }
        }
    }
    private(set) var attachment: SnapAttachment? {
        didSet {
            if let attachment, let data = try? JSONEncoder().encode(attachment) { defaults.set(data, forKey: "snapAttachment") }
            else { defaults.removeObject(forKey: "snapAttachment") }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "snapToEdges") as? Bool ?? true
        let saved = defaults.data(forKey: "snapAttachment").flatMap { try? JSONDecoder().decode(SnapAttachment.self, from: $0) }
        attachment = enabled && (saved?.horizontal != nil || saved?.vertical != nil) ? saved : nil
        if attachment == nil { defaults.removeObject(forKey: "snapAttachment") }
    }

    func detach() { attachment = nil }

    func finishDrag(_ frame: CGRect, screens: [SnapScreen], pointer: CGPoint, bypass: Bool) -> CGRect {
        detach()
        guard enabled, !bypass,
              let screen = SnapGeometry.screen(for: frame, screens: screens, pointer: pointer),
              let result = SnapGeometry.snap(frame, to: screen) else { return frame }
        attachment = result.attachment
        return result.frame
    }

    /// Reapply an existing attachment; this never creates a new snap.
    func reposition(_ frame: CGRect, screens: [SnapScreen]) -> CGRect {
        if enabled, let attachment {
            if let screen = screens.first(where: { $0.id == attachment.displayID }) {
                return SnapGeometry.reachable(SnapGeometry.anchored(frame, attachment: attachment, screen: screen), on: screen)
            }
            detach()
        }
        guard let screen = SnapGeometry.screen(for: frame, screens: screens) else { return frame }
        return SnapGeometry.reachable(frame, on: screen)
    }
}
