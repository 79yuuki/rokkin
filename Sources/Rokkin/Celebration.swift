import AppKit
import SwiftUI

/// A short confetti burst with a big title. Shown only at "finish" moments (block cleared, all steps
/// cleared), never in the middle of focused work, and it ignores the mouse so it can't get in the way.
struct CelebrationView: View {
    let title: String
    let subtitle: String
    let duration: Double
    private let start = Date()
    private let particles: [Particle] = (0..<160).map { _ in Particle.random() }

    struct Particle {
        var vx: Double, vy: Double, spin: Double, size: CGSize, color: Color, delay: Double, side: Double

        static func random() -> Particle {
            let colors: [Color] = [RokkinTheme.pink, RokkinTheme.violet, RokkinTheme.cyan, RokkinTheme.bolt, .white]
            return Particle(
                vx: Double.random(in: 120...780),
                vy: Double.random(in: 900...1650),
                spin: Double.random(in: -9...9),
                size: CGSize(width: Double.random(in: 7...12), height: Double.random(in: 12...20)),
                color: colors.randomElement() ?? .white,
                delay: Double.random(in: 0...0.25),
                side: Bool.random() ? -1 : 1
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            ZStack {
                Canvas { gc, size in
                    let gravity = 1900.0
                    for p in particles {
                        let lt = t - p.delay
                        guard lt > 0 else { continue }
                        // two cannons in the bottom corners, firing up and inward
                        let x0 = p.side < 0 ? size.width * 0.08 : size.width * 0.92
                        let x = x0 - p.side * p.vx * lt
                        let y = size.height + 20 - (p.vy * lt - 0.5 * gravity * lt * lt)
                        let fade = max(0, min(1, (duration - t) / 0.5))
                        var g = gc
                        g.opacity = fade
                        g.translateBy(x: x, y: y)
                        g.rotate(by: .radians(p.spin * lt))
                        let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        g.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                    }
                }
                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .foregroundStyle(RokkinTheme.gradient)
                        .shadow(color: RokkinTheme.pink.opacity(0.6), radius: 24)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                }
                .scaleEffect(titleScale(t))
                .opacity(max(0, min(1, (duration - 0.3 - t) / 0.4)))
            }
        }
        .allowsHitTesting(false)
    }

    private func titleScale(_ t: Double) -> Double {
        // quick overshoot pop
        let p = min(1, t / 0.35)
        let c1 = 1.70158, c3 = c1 + 1
        let back = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
        return 0.4 + 0.6 * back
    }
}

@MainActor
enum Celebration {
    private static var panel: NSPanel?

    static func show(title: String, subtitle: String = "", duration: Double = 2.4) {
        guard let screen = NSScreen.main else { return }
        panel?.orderOut(nil)
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: CelebrationView(title: title, subtitle: subtitle, duration: duration))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        p.contentView = host
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            if panel === p {
                p.orderOut(nil)
                panel = nil
            }
        }
    }
}
