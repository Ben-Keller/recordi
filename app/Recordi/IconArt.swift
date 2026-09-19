import AppKit

/// Recordi's little tape recorder: reels as eyes, a curved tape path as its smile.
enum IconArt {
    private static let recorderGlyph: NSImage = {
        let image = Bundle.main.url(forResource: "MenuRecorder", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Recordi")!
        image.size = NSSize(width: 15.3, height: 15.3)
        image.isTemplate = true
        return image
    }()
    static func menu(recording: Bool, needsAttention: Bool) -> NSImage {
        let image = recorderGlyph
        image.accessibilityDescription = recording ? "Recordi recording" : "Recordi"
        return image
    }

    static func application(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let transform = NSAffineTransform(); transform.scale(by: size / 1024); transform.concat()
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
            let ink = color(24, 62, 65)
            let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
            NSGradient(starting: color(255, 244, 215), ending: color(241, 218, 178))!.draw(in: background, angle: -90)
            // Soft, offset shadow keeps the recorder tactile without losing the clean silhouette.
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = ink.withAlphaComponent(0.18); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.set()
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 156, y: 239, width: 712, height: 532), xRadius: 100, yRadius: 100).fill()
            NSGraphicsContext.restoreGraphicsState()
            // Coral record button peeking above the shell.
            color(239, 99, 77).setFill()
            NSBezierPath(roundedRect: NSRect(x: 637, y: 757, width: 112, height: 53), xRadius: 18, yRadius: 18).fill()
            let shell = NSBezierPath(roundedRect: NSRect(x: 170, y: 265, width: 684, height: 492), xRadius: 88, yRadius: 88)
            NSGradient(starting: color(100, 209, 192), ending: color(48, 166, 155))!.draw(in: shell, angle: -90)
            color(165, 238, 215).setStroke(); shell.lineWidth = 6; shell.stroke()
            let window = NSBezierPath(roundedRect: NSRect(x: 224, y: 410, width: 576, height: 255), xRadius: 95, yRadius: 95)
            ink.setFill(); window.fill()
            for x: CGFloat in [369, 655] {
                color(255, 243, 211).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 84, y: 450, width: 168, height: 168)).fill()
                ink.setFill(); NSBezierPath(ovalIn: NSRect(x: x - 29, y: 505, width: 58, height: 58)).fill()
                color(255, 255, 241).setFill(); NSBezierPath(ovalIn: NSRect(x: x - 39, y: 551, width: 20, height: 20)).fill()
            }
            // A short exposed tape bridge between the two reels.
            color(246, 212, 153).setFill()
            NSBezierPath(roundedRect: NSRect(x: 471, y: 522, width: 82, height: 22), xRadius: 11, yRadius: 11).fill()
            ink.setStroke()
            let smile = NSBezierPath(); smile.move(to: NSPoint(x: 432, y: 352))
            smile.curve(to: NSPoint(x: 592, y: 352), controlPoint1: NSPoint(x: 472, y: 309), controlPoint2: NSPoint(x: 552, y: 309))
            smile.lineWidth = 18; smile.lineCapStyle = .round; smile.stroke()
            color(239, 99, 77).setFill()
            for x: CGFloat in [295, 701] { NSBezierPath(roundedRect: NSRect(x: x, y: 346, width: 28, height: 12), xRadius: 6, yRadius: 6).fill() }
            return true
        }
    }
}
