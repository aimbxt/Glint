import Foundation
import CoreGraphics

@MainActor
func runSnappingTests() -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
    let screen = SnapScreen(id: "main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
    let safe = screen.visibleFrame.insetBy(dx: 16, dy: 16)
    let size = CGSize(width: 300, height: 380)
    func result(_ x: CGFloat, _ y: CGFloat) -> (frame: CGRect, attachment: SnapAttachment)? {
        SnapGeometry.snap(CGRect(origin: CGPoint(x: x, y: y), size: size), to: screen)
    }
    let left = result(safe.minX + 18, 250)!
    expect(left.frame.minX == safe.minX && left.frame.minY == 250, "Left snap preserves vertical position")
    expect(left.attachment.horizontal == .left && left.attachment.vertical == nil, "Left edge alone is attached")
    expect(result(safe.minX + 18.01, 250) == nil, "Outside horizontal threshold does not snap")
    expect(result(safe.minX - 18, 250)?.frame.minX == safe.minX, "Approaching from outside snaps at threshold")
    let right = result(safe.maxX - size.width - 18, 250)!
    expect(right.frame.maxX == safe.maxX && right.frame.minY == 250, "Right snap preserves vertical position")
    let top = result(400, safe.maxY - size.height + 18)!
    expect(top.frame.maxY == safe.maxY && top.frame.minX == 400, "Top snap uses menu-bar clearance")
    let bottom = result(400, safe.minY - 18)!
    expect(bottom.frame.minY == safe.minY && bottom.frame.minX == 400, "Bottom snap uses Dock clearance")
    expect(result(400, safe.minY + 18.01) == nil, "Outside vertical threshold does not snap")
    for (x, horizontal) in [(safe.minX, SnapAttachment.Horizontal.left), (safe.maxX - size.width, .right)] {
        for (y, vertical) in [(safe.minY, SnapAttachment.Vertical.bottom), (safe.maxY - size.height, .top)] {
            let corner = result(x + 5, y - 5)!
            expect(corner.attachment.horizontal == horizontal && corner.attachment.vertical == vertical, "Each corner attaches both edges")
            expect(corner.frame.size == size, "Snapping never resizes the panel")
        }
    }
    expect(result(400, 250) == nil, "Interior positions remain free")
    let negative = SnapScreen(id: "left", frame: CGRect(x: -1280, y: -160, width: 1280, height: 900), visibleFrame: CGRect(x: -1280, y: -100, width: 1280, height: 815))
    let negativeResult = SnapGeometry.snap(CGRect(x: -1260, y: -80, width: 200, height: 60), to: negative)!
    expect(negativeResult.frame.origin == CGPoint(x: -1264, y: -84), "Negative display coordinates snap correctly")
    let spanning = CGRect(x: -100, y: 200, width: 300, height: 100)
    expect(SnapGeometry.screen(for: spanning, screens: [negative, screen])?.id == screen.id, "Choose display with greatest overlap")
    let equal = CGRect(x: -100, y: 200, width: 200, height: 100)
    expect(SnapGeometry.screen(for: equal, screens: [negative, screen], pointer: CGPoint(x: 20, y: 250))?.id == screen.id, "Pointer resolves shared-boundary tie")
    expect(SnapGeometry.screen(for: equal, screens: [], pointer: .zero) == nil, "No available displays is harmless")

    let suite = "GlintTests.Snap.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SnapState(defaults: defaults)
    expect(state.enabled && state.attachment == nil, "Snapping is enabled initially without moving existing windows")
    let starting = CGRect(x: safe.maxX - 310, y: safe.minY + 8, width: 300, height: 380)
    let snapped = state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: false)
    expect(snapped.maxX == safe.maxX && snapped.minY == safe.minY, "Release snaps to bottom-right")
    let restored = SnapState(defaults: defaults)
    expect(restored.attachment == state.attachment, "Attachment and display survive relaunch")
    for mode in PanelPresentation.allCases {
        let frame = CGRect(origin: snapped.origin, size: mode.defaultSize)
        let anchored = restored.reposition(frame, screens: [screen])
        expect(anchored.maxX == safe.maxX && anchored.minY == safe.minY && anchored.size == frame.size, "All presentations preserve attached edges and their size")
    }
    let movedDock = SnapScreen(id: "main", frame: screen.frame, visibleFrame: CGRect(x: 80, y: 0, width: 1360, height: 875))
    expect(restored.reposition(snapped, screens: [movedDock]).minY == 16, "Dock changes reapply attachment to new usable area")
    let bypassed = state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: true)
    expect(bypassed == starting && state.attachment == nil, "Option bypass leaves exact position and detaches")
    _ = state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: false)
    state.enabled = false
    expect(state.attachment == nil && !SnapState(defaults: defaults).enabled, "Disabling snapping clears attachment and persists setting")
    expect(state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: false) == starting, "Disabled snapping never changes placement")
    state.enabled = true
    expect(state.attachment == nil, "Reenabling snapping does not attach automatically")
    _ = state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: false)
    state.detach()
    expect(state.attachment == nil, "Moving away or starting a resize detaches without repositioning")
    _ = state.finishDrag(starting, screens: [screen], pointer: starting.origin, bypass: false)
    let fallback = state.reposition(snapped, screens: [negative])
    expect(state.attachment == nil && negative.visibleFrame.contains(fallback), "Missing display clears attachment and keeps window reachable")
    expect(state.reposition(snapped, screens: []) == snapped, "Temporary absence of displays does not move window")
    defaults.set(Data("bad attachment".utf8), forKey: "snapAttachment")
    expect(SnapState(defaults: defaults).attachment == nil, "Malformed saved attachment is discarded")

    var click = WindowDragMovement(origin: .zero)
    click.record(CGPoint(x: 1, y: 1))
    expect(!click.didDrag, "Click jitter does not become a drag or trigger snapping")
    var drag = WindowDragMovement(origin: .zero)
    expect(drag.record(CGPoint(x: 4, y: 0)), "Genuine movement starts a drag")
    expect(!drag.record(CGPoint(x: 5, y: 0)), "Detach is triggered only once per drag")
    drag.record(.zero)
    expect(drag.didDrag, "Dragging back to origin never becomes a pill-expanding click")
    return checks
}
