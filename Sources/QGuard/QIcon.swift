// Shared drawing for the QGuard glyph: a shield with a padlock inside and a "Q" tail.
// Used by the app (menu-bar template image) and IconTool (app icon).

import AppKit

enum QIcon {
    /// Draws the glyph filling `rect` (square) in `color`.
    static func drawGlyph(in rect: NSRect, color: NSColor, weight: CGFloat = 0.11) {
        let s = rect.width
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        color.set()

        // Shield outline
        let shield = NSBezierPath()
        shield.move(to: p(0.47, 0.93))
        shield.curve(to: p(0.15, 0.81), controlPoint1: p(0.36, 0.86), controlPoint2: p(0.25, 0.82))
        shield.line(to: p(0.15, 0.53))
        shield.curve(to: p(0.47, 0.07), controlPoint1: p(0.15, 0.29), controlPoint2: p(0.30, 0.15))
        shield.curve(to: p(0.79, 0.53), controlPoint1: p(0.64, 0.15), controlPoint2: p(0.79, 0.29))
        shield.line(to: p(0.79, 0.81))
        shield.curve(to: p(0.47, 0.93), controlPoint1: p(0.69, 0.82), controlPoint2: p(0.58, 0.86))
        shield.close()
        shield.lineWidth = weight * s
        shield.lineJoinStyle = .round
        shield.stroke()

        // Q tail crossing the shield's lower-right edge
        let tail = NSBezierPath()
        tail.move(to: p(0.585, 0.265))
        tail.line(to: p(0.86, 0.03))
        tail.lineWidth = weight * 1.15 * s
        tail.lineCapStyle = .butt
        tail.stroke()

        // Padlock shackle
        let shackle = NSBezierPath()
        shackle.move(to: p(0.385, 0.52))
        shackle.line(to: p(0.385, 0.60))
        shackle.appendArc(withCenter: p(0.47, 0.60), radius: 0.085 * s, startAngle: 180, endAngle: 0, clockwise: true)
        shackle.line(to: p(0.555, 0.52))
        shackle.lineWidth = weight * 0.55 * s
        shackle.stroke()

        // Padlock body with keyhole cut out
        let body = NSBezierPath(roundedRect: NSRect(x: rect.minX + 0.33 * s, y: rect.minY + 0.33 * s,
                                                    width: 0.28 * s, height: 0.21 * s),
                                xRadius: 0.035 * s, yRadius: 0.035 * s)
        let hole = 0.032 * s
        body.appendOval(in: NSRect(x: p(0.47, 0.45).x - hole, y: p(0.47, 0.45).y - hole, width: 2 * hole, height: 2 * hole))
        body.appendRect(NSRect(x: p(0.47, 0).x - hole * 0.45, y: rect.minY + 0.375 * s, width: hole * 0.9, height: 0.07 * s))
        body.windingRule = .evenOdd
        body.fill()
    }

    /// Template image for the menu bar.
    static func menuBarImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            drawGlyph(in: r, color: .black, weight: 0.12)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "QGuard"
        return img
    }

    /// Full-colour app icon at `px` pixels.
    static func appIcon(px: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px)

        // macOS icon grid: 824/1024 rounded square, centred.
        let inset = s * 100 / 1024
        let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        shadow.shadowBlurRadius = s * 0.025
        shadow.set()
        NSColor.black.set()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: NSColor(srgbRed: 0.42, green: 0.20, blue: 0.85, alpha: 1),
                   ending: NSColor(srgbRed: 0.10, green: 0.13, blue: 0.40, alpha: 1))!
            .draw(in: shape, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor(srgbRed: 0.55, green: 0.80, blue: 1, alpha: 0.6)
        glow.shadowBlurRadius = s * 0.03
        glow.set()
        drawGlyph(in: tile.insetBy(dx: tile.width * 0.17, dy: tile.width * 0.17), color: .white)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
