import AppKit

@main struct GenerateIcons {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let iconset = root.appendingPathComponent("Recordi.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        func png(_ image: NSImage, pixels: Int, to url: URL) throws {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                try png(IconArt.application(size: CGFloat(pixels)), pixels: pixels, to: iconset.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
            }
        }
        try png(IconArt.application(size: 512), pixels: 512, to: root.appendingPathComponent("Recordi.png"))
    }
}
