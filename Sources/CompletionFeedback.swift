import SwiftUI

/// A saved-value copy, never a second live task or a delayed database change.
struct TaskCompletionEffect: Identifiable {
    let token = UUID()
    let record: TaskRecord
    let fromFocus: Bool
    let reducedMotion: Bool
    var step = 0
    var id: UUID { record.id }
    var retainsListRow: Bool { !fromFocus && !reducedMotion }
    var isCollapsing: Bool { step >= 4 }
}

struct CompletionCheckbox: View {
    let completed: Bool
    var effect: TaskCompletionEffect? = nil

    var body: some View {
        let size: CGFloat = effect.map { $0.reducedMotion ? 18 : ($0.step == 0 ? 16 : ($0.step == 1 ? 20 : 18)) } ?? 18
        PixelIcon(glyph: completed ? .checked : .checkbox, size: size,
                  color: completed ? PixelPalette.highlight : PixelPalette.edge)
            .background {
                if completed { Rectangle().fill(PixelPalette.accent).frame(width: size, height: size) }
            }
            .offset(y: effect?.step == 0 && effect?.reducedMotion == false ? 1 : 0)
            .frame(width: 32, height: 32)
    }
}

/// Deliberate sprite frames instead of scaling/rotating bitmap pixels.
struct CompletionStarburst: View {
    let step: Int
    var reducedMotion = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, bounds in
            func spark(x: CGFloat, y: CGFloat, size: CGFloat) {
                let unit = max(1 / displayScale, floor(size / 9 * displayScale) / displayScale)
                let originX = (bounds.width / 2 + x - unit * 4.5) * displayScale
                let originY = (bounds.height / 2 + y - unit * 4.5) * displayScale
                var path = Path()
                for (rowIndex, row) in PixelGlyph.spark.rows.enumerated() {
                    for (column, cell) in row.enumerated() where cell == "1" {
                        path.addRect(CGRect(x: floor(originX) / displayScale + CGFloat(column) * unit,
                                            y: floor(originY) / displayScale + CGFloat(rowIndex) * unit,
                                            width: unit, height: unit))
                    }
                }
                context.fill(path, with: .color(PixelPalette.gold), style: FillStyle(antialiased: false))
            }
            func particle(x: CGFloat, y: CGFloat, size: CGFloat, cream: Bool) {
                let rect = CGRect(x: floor((bounds.width / 2 + x) * displayScale) / displayScale,
                                  y: floor((bounds.height / 2 + y) * displayScale) / displayScale,
                                  width: size, height: size)
                context.fill(Path(rect), with: .color(cream ? PixelPalette.highlight : PixelPalette.gold),
                             style: FillStyle(antialiased: false))
            }
            if reducedMotion {
                spark(x: 9, y: -10, size: 9)
            } else if step > 0 && step < 7 {
                let sizes: [CGFloat] = [0, 9, 12, 9, 7, 5, 3]
                spark(x: CGFloat(4 + step), y: CGFloat(-6 - step * 2), size: sizes[step])
                if step < 6 {
                    let travel = CGFloat(step * 2)
                    let size: CGFloat = step < 4 ? 2 : 1
                    particle(x: -6 - travel, y: -3 - travel / 2, size: size, cream: false)
                    particle(x: 7 + travel, y: 2 + travel / 2, size: size, cream: true)
                    particle(x: -1 - travel / 2, y: -8 - travel, size: size, cream: true)
                    particle(x: 2 + travel / 2, y: 7 + travel / 2, size: size, cream: false)
                }
            }
        }
        .frame(width: 48, height: 48)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CompletionRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Only the outgoing visual closes its space; other rows remain interactive.
struct CompletionRowExit: ViewModifier {
    let collapsing: Bool
    @State private var naturalHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CompletionRowHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(CompletionRowHeightKey.self) { naturalHeight = $0 }
            .frame(height: naturalHeight > 0 ? (collapsing ? 0 : naturalHeight) : nil, alignment: .top)
            .clipped()
            .opacity(collapsing ? 0 : 1)
            .animation(.easeOut(duration: 0.18), value: collapsing)
    }
}
