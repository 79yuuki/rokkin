import AppKit
import SwiftUI

/// Colours and the menu bar glyph, matching the app icon (neon pink → violet → cyan, lock with a bolt).
enum RokkinTheme {
    static let pink = Color(red: 1.0, green: 0.23, blue: 0.62)
    static let violet = Color(red: 0.48, green: 0.17, blue: 1.0)
    static let cyan = Color(red: 0.09, green: 0.78, blue: 1.0)
    static let bolt = Color(red: 1.0, green: 0.82, blue: 0.0)

    static let gradient = LinearGradient(colors: [pink, violet, cyan], startPoint: .leading, endPoint: .trailing)
    static let diagonal = LinearGradient(colors: [pink, violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Template images for the menu bar, drawn in code so they stay crisp and follow light/dark mode.
@MainActor
enum RokkinIcon {
    private static var cache: [Bool: NSImage] = [:]

    /// A slightly tilted padlock with a lightning-bolt keyhole; `rocking` adds sound waves on both sides.
    static func menuBar(rocking: Bool) -> NSImage {
        if let cached = cache[rocking] { return cached }
        let size = NSSize(width: rocking ? 24 : 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let t = NSAffineTransform()
            t.translateX(by: cx, yBy: 9)
            t.rotate(byDegrees: 8) // y-up coordinates: positive = counter-clockwise, a jaunty tilt
            t.translateX(by: -9, yBy: -9)
            t.concat()

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Shackle
            let shackle = NSBezierPath()
            shackle.lineWidth = 1.9
            shackle.lineCapStyle = .round
            shackle.move(to: NSPoint(x: 5.7, y: 9.2))
            shackle.line(to: NSPoint(x: 5.7, y: 12.2))
            shackle.appendArc(withCenter: NSPoint(x: 9, y: 12.2), radius: 3.3, startAngle: 180, endAngle: 0, clockwise: true)
            shackle.line(to: NSPoint(x: 12.3, y: 9.2))
            shackle.stroke()

            // Body with a bolt-shaped hole (even-odd fill keeps the bolt transparent)
            let body = NSBezierPath(roundedRect: NSRect(x: 3.2, y: 1.2, width: 11.6, height: 8.8), xRadius: 2.3, yRadius: 2.3)
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 9.9, y: 8.8))
            bolt.line(to: NSPoint(x: 7.1, y: 4.9))
            bolt.line(to: NSPoint(x: 8.8, y: 4.9))
            bolt.line(to: NSPoint(x: 8.0, y: 2.1))
            bolt.line(to: NSPoint(x: 10.9, y: 6.2))
            bolt.line(to: NSPoint(x: 9.2, y: 6.2))
            bolt.line(to: NSPoint(x: 10.5, y: 8.8))
            bolt.close()
            body.append(bolt)
            body.windingRule = .evenOdd
            body.fill()

            if rocking {
                for (x, dir) in [(1.2, -1.0), (16.8, 1.0)] {
                    let wave = NSBezierPath()
                    wave.lineWidth = 1.4
                    wave.lineCapStyle = .round
                    wave.move(to: NSPoint(x: x, y: 3.2))
                    wave.curve(to: NSPoint(x: x, y: 9.0),
                               controlPoint1: NSPoint(x: x + 1.6 * dir, y: 4.8),
                               controlPoint2: NSPoint(x: x + 1.6 * dir, y: 7.4))
                    wave.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        cache[rocking] = image
        return image
    }
}
