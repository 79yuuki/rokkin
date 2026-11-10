import AppKit
import RokkinCore
import SwiftUI

/// A panel that can take keyboard focus without activating the app (Spotlight-style),
/// so focus returns to whatever you were working in when it closes.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var hud: KeyablePanel?
    private var hudHost: NSHostingController<AnyView>?
    private var capture: KeyablePanel?
    private var friction: KeyablePanel?
    private var setup: NSWindow?
    private var breakWindow: NSWindow?
    private var review: NSWindow?
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?

    var isHUDVisible: Bool { hud?.isVisible ?? false }

    // MARK: HUD

    func showHUD() {
        if hud == nil { hud = makeHUD() }
        refreshHUDSize()
        hud?.orderFrontRegardless()
        AppState.shared.noteHUDVisibility(true)
    }

    func hideHUD() {
        hud?.orderOut(nil)
        AppState.shared.noteHUDVisibility(false)
    }

    private func makeHUD() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let host = NSHostingController(rootView: AnyView(HUDView().environmentObject(AppState.shared)))
        host.sizingOptions = []
        hudHost = host
        panel.contentViewController = host

        if !panel.setFrameUsingName("RokkinHUD"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.maxX - 340, y: f.maxY - 10))
        }
        panel.setFrameAutosaveName("RokkinHUD")
        return panel
    }

    /// Measures the HUD's SwiftUI content and fits the panel to it (top edge stays put).
    /// Called whenever the content may have changed size and once a second as a safety net,
    /// so a check-in box or a message can never be clipped.
    func refreshHUDSize() {
        guard let host = hudHost, hud != nil else { return }
        let fit = host.sizeThatFits(in: CGSize(width: 320, height: 10_000))
        resizeHUD(to: fit)
    }

    /// Resizes the HUD to its SwiftUI content while keeping the top edge in place.
    func resizeHUD(to size: CGSize) {
        guard let panel = hud, size.width > 1, size.height > 1 else { return }
        var frame = panel.frame
        let newSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        if abs(frame.width - newSize.width) < 0.5, abs(frame.height - newSize.height) < 0.5 { return }
        let top = frame.maxY
        frame.size = newSize
        frame.origin.y = top - newSize.height
        // keep it on screen if it grew past the bottom edge
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        panel.setFrame(frame, display: true)
    }

    // MARK: Floating panels

    private func makeFloatingPanel(level: NSWindow.Level) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for b in buttons { panel.standardWindowButton(b)?.isHidden = true }
        return panel
    }

    func showCapture(kind: NoteKind, prefill: String) {
        closeCapture()
        let panel = makeFloatingPanel(level: .floating)
        let view = CaptureView(
            kind: kind,
            initialText: prefill,
            onSubmit: { text in
                AppState.shared.addNote(text, kind: kind)
                WindowManager.shared.closeCapture()
            },
            onCancel: { WindowManager.shared.closeCapture() }
        )
        panel.contentViewController = NSHostingController(rootView: view)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.3))
        } else {
            panel.center()
        }
        capture = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func closeCapture() {
        capture?.orderOut(nil)
        capture = nil
    }

    func showFriction() {
        closeFriction()
        let panel = makeFloatingPanel(level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
        panel.contentViewController = NSHostingController(rootView: FrictionView().environmentObject(AppState.shared))
        panel.center()
        friction = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func closeFriction() {
        friction?.orderOut(nil)
        friction = nil
    }

    // MARK: Regular windows

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let host = NSHostingController(rootView: content.environmentObject(AppState.shared))
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        return w
    }

    private func present(_ w: NSWindow, floating: Bool = false) {
        w.level = floating ? .floating : .normal
        w.center()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        w.makeKeyAndOrderFront(nil)
    }

    func showSetup() {
        setup?.close()
        let w = makeWindow(title: "新しいセッション", content: SetupView())
        setup = w
        present(w)
    }

    func closeSetup() { setup?.close() }

    func showBreak() {
        if breakWindow == nil { breakWindow = makeWindow(title: "休憩", content: BreakView()) }
        if let w = breakWindow { present(w, floating: true) }
    }

    func closeBreak() { breakWindow?.close() }

    func showReview() {
        review?.close()
        let w = makeWindow(title: "リザルト", content: ReviewView())
        review = w
        present(w)
    }

    func closeReview() { review?.close() }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = makeWindow(title: "Rokkin 設定", content: SettingsView()) }
        if let w = settingsWindow { present(w) }
    }

    func showDashboard() {
        if dashboardWindow == nil { dashboardWindow = makeWindow(title: "Rokkin ダッシュボード", content: DashboardView()) }
        if let w = dashboardWindow { present(w) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === setup { setup = nil }
        if w === breakWindow { breakWindow = nil }
        if w === review { review = nil }
        if w === settingsWindow { settingsWindow = nil }
        if w === dashboardWindow { dashboardWindow = nil }
    }
}

// MARK: - AppKit helpers for SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Lets a borderless window be dragged from this area.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
