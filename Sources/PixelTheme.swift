import SwiftUI
import AppKit
import CoreText

enum PixelPalette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        }
    }
    static let paperNS = adaptive(0xF2EBD8, 0x252E25)
    static let paper = Color(nsColor: paperNS)
    static let ink = Color(nsColor: adaptive(0x283B30, 0xF0EBD7))
    static let secondary = Color(nsColor: adaptive(0x515C48, 0xB6C3A6))
    static let edge = Color(nsColor: adaptive(0x52674E, 0x8DA37D))
    static let accent = Color(nsColor: adaptive(0x3E684D, 0xB0CD98))
    static let gold = Color(nsColor: adaptive(0x8B651F, 0xE0BF76))
    static let inset = Color(nsColor: adaptive(0xE4DCC6, 0x1D261D))
    static let raised = Color(nsColor: adaptive(0xEDE2C7, 0x35432F))
    static let highlight = Color(nsColor: adaptive(0xFFF9E9, 0x566B47))
    static let shadow = Color(nsColor: adaptive(0x718065, 0x10180F))
    static let danger = Color(nsColor: adaptive(0x963E31, 0xF1A28A))
}

enum PixelFonts {
    static let postscriptName = "PixelifySans-Regular"

    @discardableResult static func register(in bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: "PixelifySans", withExtension: "ttf", subdirectory: "Fonts") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, readable: Bool, weight: Font.Weight = .regular) -> Font {
        if readable { return .system(size: size, weight: weight) }
        return .custom(postscriptName, size: size).weight(weight)
    }
}

private struct ReadablePixelTextKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var readablePixelText: Bool {
        get { self[ReadablePixelTextKey.self] }
        set { self[ReadablePixelTextKey.self] = newValue }
    }
}

private struct PixelTypography: ViewModifier {
    @Environment(\.readablePixelText) private var readable
    let size: CGFloat
    let weight: Font.Weight
    func body(content: Content) -> some View { content.font(PixelFonts.font(size, readable: readable, weight: weight)) }
}

extension View {
    func pixelFont(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> some View {
        modifier(PixelTypography(size: size, weight: weight))
    }
    func pixelChrome(compact: Bool = false) -> some View { modifier(PixelChrome(compact: compact)) }
}

/// Integer-point steps render cleanly on both standard and Retina displays.
struct PixelPanelShape: InsettableShape {
    var compact = false
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> PixelPanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        let s = min(compact ? 3.0 : 4.0, r.width / 6, r.height / 6)
        let x = r.minX, y = r.minY, X = r.maxX, Y = r.maxY
        var path = Path()
        path.addLines([
            CGPoint(x:x+2*s,y:y), CGPoint(x:X-2*s,y:y), CGPoint(x:X-2*s,y:y+s), CGPoint(x:X-s,y:y+s),
            CGPoint(x:X-s,y:y+2*s), CGPoint(x:X,y:y+2*s), CGPoint(x:X,y:Y-2*s), CGPoint(x:X-s,y:Y-2*s),
            CGPoint(x:X-s,y:Y-s), CGPoint(x:X-2*s,y:Y-s), CGPoint(x:X-2*s,y:Y), CGPoint(x:x+2*s,y:Y),
            CGPoint(x:x+2*s,y:Y-s), CGPoint(x:x+s,y:Y-s), CGPoint(x:x+s,y:Y-2*s), CGPoint(x:x,y:Y-2*s),
            CGPoint(x:x,y:y+2*s), CGPoint(x:x+s,y:y+2*s), CGPoint(x:x+s,y:y+s), CGPoint(x:x+2*s,y:y+s)
        ])
        path.closeSubpath()
        return path
    }
}

struct PixelVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PixelSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { PixelVisualEffect() }
            PixelPalette.paper.opacity(reduceTransparency ? 1 : 0.88)
        }
    }
}

private struct PixelChrome: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        let shape = PixelPanelShape(compact: compact)
        content
            .background(PixelSurface())
            .clipShape(shape)
            .overlay(shape.strokeBorder(PixelPalette.edge, lineWidth: 2).allowsHitTesting(false))
            .overlay(shape.inset(by: 2).strokeBorder(PixelPalette.highlight, lineWidth: 1).allowsHitTesting(false))
            .padding(.trailing, 3).padding(.bottom, 3)
            .background(shape.fill(PixelPalette.shadow).padding(.leading, 3).padding(.top, 3))
    }
}

enum PixelGlyph: String, CaseIterable {
    case checkbox, checked, collapse, list, more, focus, expand, plus, spark, grip, right, down, close
    var rows: [String] {
        switch self {
        case .checkbox: return ["111111111","100000001","100000001","100000001","100000001","100000001","100000001","100000001","111111111"]
        case .checked: return ["111111111","100000001","100000101","100001101","101011001","101110001","100100001","100000001","111111111"]
        case .collapse: return ["000000000","000000000","001111100","010000010","100000001","010000010","001111100","000000000","000000000"]
        case .list: return ["000000000","110111111","110111111","000000000","110111111","110111111","000000000","110111111","110111111"]
        case .more: return ["000000000","000000000","000000000","110110110","110110110","000000000","000000000","000000000","000000000"]
        case .focus: return ["111000111","100000001","100010001","000111000","001111100","000111000","100010001","100000001","111000111"]
        case .expand: return ["111100000","100000000","101000000","100100000","000010000","000001001","000000101","000000001","000001111"]
        case .plus: return ["000000000","000110000","000110000","000110000","111111110","111111110","000110000","000110000","000000000"]
        case .spark: return ["000010000","000010000","000111000","001111100","111111111","001111100","000111000","000010000","000010000"]
        case .grip: return ["000000000","000000000","000000001","000000001","000001001","000001001","001001001","001001001","000000000"]
        case .right: return ["001000000","001100000","000110000","000011000","000001100","000011000","000110000","001100000","001000000"]
        case .down: return ["000000000","000000000","100000001","110000011","011000110","001101100","000111000","000010000","000000000"]
        case .close: return ["110000011","111000111","011101110","001111100","000111000","001111100","011101110","111000111","110000011"]
        }
    }
}

struct PixelIcon: View {
    let glyph: PixelGlyph
    var size: CGFloat = 18
    var color: Color = PixelPalette.accent
    @Environment(\.displayScale) private var scale
    var body: some View {
        Canvas { context, bounds in
            let rows = glyph.rows
            let unit = max(1 / scale, floor(min(bounds.width, bounds.height) / 9 * scale) / scale)
            let dx = (floor((bounds.width - unit * 9) / 2 * scale) / scale)
            let dy = (floor((bounds.height - unit * 9) / 2 * scale) / scale)
            var path = Path()
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "1" {
                    path.addRect(CGRect(x: dx + CGFloat(x) * unit, y: dy + CGFloat(y) * unit, width: unit, height: unit))
                }
            }
            context.fill(path, with: .color(color), style: FillStyle(antialiased: false))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PixelControlFace: ViewModifier {
    var selected = false
    func body(content: Content) -> some View {
        content
            .background(selected ? PixelPalette.inset : PixelPalette.raised)
            .clipShape(PixelPanelShape(compact: true))
            .overlay(PixelPanelShape(compact: true).strokeBorder(PixelPalette.edge, lineWidth: 1).allowsHitTesting(false))
            .overlay(PixelPanelShape(compact: true).inset(by: 1).strokeBorder(PixelPalette.highlight, lineWidth: 1).allowsHitTesting(false))
            .contentShape(Rectangle())
    }
}

struct PixelButtonStyle: ButtonStyle {
    var raised = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(raised ? (configuration.isPressed ? PixelPalette.inset : PixelPalette.raised) : Color.clear)
            .clipShape(PixelPanelShape(compact: true))
            .overlay {
                if raised { PixelPanelShape(compact: true).strokeBorder(PixelPalette.edge, lineWidth: 1).allowsHitTesting(false) }
            }
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(enabled ? 1 : 0.5)
    }
}

enum PixelBrand {
    /// Native macOS menu buttons can display an NSImage label, but not Canvas.
    static func image(_ glyph: PixelGlyph, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let unit = size / 9
            NSColor.black.setFill()
            NSGraphicsContext.current?.shouldAntialias = false
            for (y, row) in glyph.rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "1" {
                    NSBezierPath(rect: NSRect(x: CGFloat(x) * unit, y: CGFloat(8 - y) * unit, width: unit, height: unit)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    static func menuBarImage() -> NSImage { image(.spark) }
}
