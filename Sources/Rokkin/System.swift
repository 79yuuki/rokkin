import AppKit
import AVFoundation
import Carbon.HIToolbox
import RokkinCore

// MARK: - Global hotkeys (Carbon; needs no Accessibility permission)

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register(keyCode: Int, modifiers: Int, id: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4854_4B59), id: id) // 'HTKY'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        } else {
            NSLog("Rokkin: hotkey \(id) could not be registered (\(status))")
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            if status == noErr { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    fileprivate func fire(_ id: UInt32) {
        guard let handler = handlers[id] else { return }
        DispatchQueue.main.async { handler() }
    }

    func registerDefaults() {
        let mods = controlKey | optionKey
        register(keyCode: kVK_ANSI_M, modifiers: mods, id: 1) { Task { @MainActor in AppState.shared.openCapture(.parking) } }
        register(keyCode: kVK_ANSI_Y, modifiers: mods, id: 3) { Task { @MainActor in AppState.shared.answerCheckIn(onTask: true) } }
        register(keyCode: kVK_ANSI_N, modifiers: mods, id: 4) { Task { @MainActor in AppState.shared.answerCheckIn(onTask: false) } }
        register(keyCode: kVK_ANSI_H, modifiers: mods, id: 5) { Task { @MainActor in AppState.shared.toggleHUD() } }
        register(keyCode: kVK_ANSI_L, modifiers: mods, id: 6) { Task { @MainActor in AppState.shared.openSetup() } }
    }
}

// MARK: - Frontmost app & browser URL

@MainActor
final class AppWatcher {
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                guard let running = NSRunningApplication(processIdentifier: pid) else { return }
                AppState.shared.handleActivate(running)
            }
        }
    }

    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return safari.contains(id) || chromium.contains(id)
    }

    private static func script(for app: NSRunningApplication) -> String? {
        guard let id = app.bundleIdentifier else { return nil }
        let body: String
        if safari.contains(id) {
            body = "tell application id \"\(id)\" to return URL of front document"
        } else if chromium.contains(id) {
            body = "tell application id \"\(id)\" to return URL of active tab of front window"
        } else {
            return nil
        }
        return "with timeout of 2 seconds\n\(body)\nend timeout"
    }

    private static let queue = DispatchQueue(label: "rokkin.applescript", qos: .utility)

    /// Asks the browser for its current URL (needs the one-time Automation permission). Runs off the main thread.
    static func fetchURL(of app: NSRunningApplication, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        guard let source = script(for: app) else {
            completion(nil)
            return
        }
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let url = error == nil ? result?.stringValue : nil
            Task { @MainActor in completion(url) }
        }
    }
}

// MARK: - Sounds & Shortcuts

@MainActor
enum Sounds {
    enum Cue { case start, combo, checkIn, blockEnd, breakEnd, claudeDone, claudeWaiting }

    static func play(_ cue: Cue) {
        let name: String
        switch cue {
        case .start: name = "Funk"
        case .combo: name = "Pop"
        case .checkIn: name = "Tink"
        case .blockEnd: name = "Glass"
        case .breakEnd: name = "Hero"
        case .claudeDone: name = "Ping"
        case .claudeWaiting: name = "Purr"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Runs a user's Shortcut (e.g. one that turns a Focus on). Focus modes can sync to iPhone.
enum ShortcutRunner {
    static func run(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", trimmed]
            do {
                try p.run()
                p.waitUntilExit()
            } catch {
                NSLog("Rokkin: could not run shortcut \(trimmed): \(error)")
            }
        }
    }
}

// MARK: - Background noise

final class NoisePlayer {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let generator = NoiseGenerator()
    private(set) var isPlaying = false

    var color: NoiseColor {
        get { generator.color }
        set { generator.color = newValue }
    }

    var volume: Float = 0.2 {
        didSet { if isPlaying { engine.mainMixerNode.outputVolume = volume } }
    }

    func start() {
        guard !isPlaying else { return }
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 44_100, channels: 1) else { return }
        let gen = generator
        let node = AVAudioSourceNode(format: format) { (_, _, frameCount, audioBufferList) -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = gen.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            source = node
            isPlaying = true
        } catch {
            engine.detach(node)
            NSLog("Rokkin: audio engine failed: \(error)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isPlaying = false
    }
}

final class NoiseGenerator {
    var color: NoiseColor = .pink
    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0

    private func white() -> Float {
        // xorshift64* — cheap and allocation-free for the audio thread.
        rng ^= rng >> 12
        rng ^= rng << 25
        rng ^= rng >> 27
        let r = rng &* 2_685_821_657_736_338_717
        return Float(r >> 40) / 16_777_216 * 2 - 1
    }

    func next() -> Float {
        let w = white()
        switch color {
        case .white:
            return w * 0.3
        case .pink:
            // Paul Kellet's refined pink-noise filter.
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
            b6 = w * 0.115926
            return pink * 0.11
        case .brown:
            brown = (brown + 0.02 * w) / 1.02
            return brown * 1.05
        }
    }
}
