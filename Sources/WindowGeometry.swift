import Foundation
import CoreGraphics

enum PanelGeometry {
    static let pillMinimum = CGSize(width: 164, height: 40)
    static let pillMaximum = CGSize(width: 520, height: 180)
    static let pillDefault = CGSize(width: 164, height: 48)

    static func pillSize(_ proposed: CGSize) -> CGSize {
        CGSize(width: proposed.width.isFinite ? min(pillMaximum.width, max(pillMinimum.width, proposed.width)) : pillDefault.width,
               height: proposed.height.isFinite ? min(pillMaximum.height, max(pillMinimum.height, proposed.height)) : pillDefault.height)
    }

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4)
        static let bottom = Edges(rawValue: 8)
    }

    // AppKit coordinates: dragging a bottom edge downward increases height.
    static func resized(_ original: CGRect, delta: CGSize, edges: Edges, minimum: CGSize, maximum: CGSize) -> CGRect {
        var rect = original
        if edges.contains(.left) || edges.contains(.right) {
            let direction: CGFloat = edges.contains(.left) ? -1 : 1
            rect.size.width = min(maximum.width, max(minimum.width, original.width + delta.width * direction))
            if edges.contains(.left) { rect.origin.x = original.maxX - rect.width }
        }
        if edges.contains(.top) || edges.contains(.bottom) {
            let direction: CGFloat = edges.contains(.bottom) ? -1 : 1
            rect.size.height = min(maximum.height, max(minimum.height, original.height + delta.height * direction))
            if edges.contains(.bottom) { rect.origin.y = original.maxY - rect.height }
        }
        return rect
    }
}
