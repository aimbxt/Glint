// Regenerate the app icon with:
// swiftc -parse-as-library Sources/PixelTheme.swift Tools/MakeIcon.swift -o build/MakeIcon
// build/MakeIcon Resources/Glint.icns
import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let output = CommandLine.arguments[1]
        var body = Data()
        for (code, size) in [("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.setShouldAntialias(false)
            context.scaleBy(x: CGFloat(size) / 128, y: CGFloat(size) / 128)
            func color(_ value: UInt32) -> CGColor {
                CGColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
            }
            func panel(_ rect: CGRect, _ step: CGFloat, _ fill: UInt32) {
                let x = rect.minX, y = rect.minY, X = rect.maxX, Y = rect.maxY, s = step
                let path = CGMutablePath()
                path.addLines(between: [CGPoint(x:x+2*s,y:y),CGPoint(x:X-2*s,y:y),CGPoint(x:X-2*s,y:y+s),CGPoint(x:X-s,y:y+s),CGPoint(x:X-s,y:y+2*s),CGPoint(x:X,y:y+2*s),CGPoint(x:X,y:Y-2*s),CGPoint(x:X-s,y:Y-2*s),CGPoint(x:X-s,y:Y-s),CGPoint(x:X-2*s,y:Y-s),CGPoint(x:X-2*s,y:Y),CGPoint(x:x+2*s,y:Y),CGPoint(x:x+2*s,y:Y-s),CGPoint(x:x+s,y:Y-s),CGPoint(x:x+s,y:Y-2*s),CGPoint(x:x,y:Y-2*s),CGPoint(x:x,y:y+2*s),CGPoint(x:x+s,y:y+2*s),CGPoint(x:x+s,y:y+s),CGPoint(x:x+2*s,y:y+s)])
                path.closeSubpath()
                context.setFillColor(color(fill)); context.addPath(path); context.fillPath()
            }
            panel(CGRect(x: 6, y: 2, width: 120, height: 120), 5, 0x718065)
            panel(CGRect(x: 2, y: 6, width: 120, height: 120), 5, 0x3E684D)
            panel(CGRect(x: 10, y: 14, width: 104, height: 104), 4, 0xFFF9E9)
            panel(CGRect(x: 14, y: 18, width: 96, height: 96), 3, 0xF2EBD8)
            context.setFillColor(color(0x8B651F))
            for (y, row) in PixelGlyph.spark.rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "1" {
                    context.fill(CGRect(x: 35 + x*6, y: 41 + (8-y)*6, width: 6, height: 6))
                }
            }
            context.setFillColor(color(0x52674E))
            for x in [43, 59, 75] { context.fill(CGRect(x: x, y: 29, width: 8, height: 4)) }
            let png = rep.representation(using: .png, properties: [:])!
            body.append(code.data(using: .ascii)!)
            var length = UInt32(png.count + 8).bigEndian
            withUnsafeBytes(of: &length) { body.append(contentsOf: $0) }
            body.append(png)
        }
        var result = Data("icns".utf8)
        var length = UInt32(body.count + 8).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(body)
        try result.write(to: URL(fileURLWithPath: output))
    }
}
