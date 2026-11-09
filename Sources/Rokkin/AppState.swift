import AppKit
import RokkinCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable { case idle, working, onBreak }

    let store: Store

    @Published var settings: AppSettings {
        didSet {
            store.saveSettings(settings)
            noise.color = settings.noiseColor
            noise.volume = Float(settings.noiseVolume)
            configureClaudeBridge()
        }
    }

    @Published private(set) var history: [SessionRecord] { didSet { store.saveHistory(history) } }
    @Published private(set) var inbox: [Note] { didSet { store.saveInbox(inbox) } }
    @Published private(set) var session: SessionRecord? { didSet { store.saveCurrent(session) } }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var now = Date()
    @Published private(set) var blockEndsAt: Date?
    @Published private(set) var breakEndsAt: Date?
    @Published private(set) var blockOver = false
    @Published private(set) var checkInPending = false
    @Published private(set) var awaitingTag = false
    @Published private(set) var flashMessage: String?
    @Published private(set) var claudeActivity: ClaudeActivity = .idle
    @Published private(set) var claudeSince = Date()
    @Published private(set) var claudeProject: String?
    @Published private(set) var claudeNeedsAttention = false
    @Published private(set) var observationPrompt = DefaultContent.observationPrompts[0]
    @Published private(set) var noisePlaying = false
    @Published private(set) var yesStreak = 0
    @Published private(set) var frictionTarget: String?
    @Published private(set) var reviewingID: UUID?
    @Published private(set) var lastBreakWasLong = false

    private var blockOverAt: Date?
    private var flashUntil: Date?
    private var checkInAskedAt: Date?
    private var nextCheckInAt: Date?
    private var breakOverNotified = false
    private var promptIndex = 0
    private var lastPromptChange = Date()
    private var tickCount = 0
    private var timer: Timer?
    private let noise = NoisePlayer()
    private var tailer: ClaudeEventTailer?
    private let watcher = AppWatcher()
    private var driftAllowedUntil: Date?
    private var lastFrictionAt: Date?
    private var lastWorkAppPID: pid_t?
    private var urlCheckInFlight = false
    private var launched = false

    private init() {
        let store = Store()
        self.store = store
        self.settings = store.loadSettings()
        self.history = store.loadHistory()
        self.inbox = store.loadInbox()
        self.session = nil
    }

    // MARK: - Launch

    func didLaunch() {
        guard !launched else { return }
        launched = true
        noise.color = settings.noiseColor
        noise.volume = Float(settings.noiseVolume)

        let t = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in AppState.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        HotKeyCenter.shared.registerDefaults()
        watcher.start()
        configureClaudeBridge()

        if let saved = store.loadCurrent() {
            restore(saved)
        } else {
            openSetup()
        }
    }

    private func restore(_ saved: SessionRecord) {
        var s = saved
        if let i = s.blocks.indices.last, s.blocks[i].end == nil {
            let planned = Double(s.blocks[i].plannedMinutes + s.blocks[i].extendedMinutes) * 60
            s.blocks[i].end = min(Date(), s.blocks[i].start.addingTimeInterval(planned))
        }
        session = s
        phase = .onBreak
        breakEndsAt = nil
        breakOverNotified = true
        WindowManager.shared.showHUD()
        flash("前回のセッションを復元しました。準備ができたら次のブロックへ", seconds: 12)
    }

    func configureClaudeBridge() {
        if settings.claudeIntegration {
            if tailer == nil {
                let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".rokkin/claude-events")
                tailer = ClaudeEventTailer(url: url)
            }
        } else {
            tailer = nil
            claudeActivity = .idle
            claudeNeedsAttention = false
        }
    }

    // MARK: - Derived

    var recommendedBlockMinutes: Int? { AttentionSpan.recommendedBlockMinutes(history: history) }

    var reviewing: SessionRecord? {
        guard let id = reviewingID else { return nil }
        return history.first { $0.id == id }
    }

    var breakIsOver: Bool {
        guard phase == .onBreak else { return false }
        guard let end = breakEndsAt else { return true }
        return now >= end
    }

    var timerText: String {
        switch phase {
        case .idle:
            return ""
        case .working:
            guard let end = blockEndsAt else { return "" }
            let r = end.timeIntervalSince(now)
            return r >= 0 ? TimeFormat.mmss(r) : "+" + TimeFormat.mmss(-r)
        case .onBreak:
            guard let end = breakEndsAt else { return "一時停止" }
            let r = end.timeIntervalSince(now)
            return r >= 0 ? TimeFormat.mmss(r) : "休憩終了"
        }
    }

    var menuBarText: String { phase == .idle ? "" : timerText }

    var menuBarImage: Image {
        if claudeNeedsAttention { return Image(systemName: "bell.badge") }
        switch phase {
        case .idle: return Image(nsImage: RokkinIcon.menuBar(rocking: false))
        case .working:
            return checkInPending ? Image(systemName: "questionmark.circle") : Image(nsImage: RokkinIcon.menuBar(rocking: true))
        case .onBreak: return Image(systemName: "cup.and.saucer")
        }
    }

    // MARK: - Tick

    func tick() {
        now = Date()
        tickCount += 1
        if let until = flashUntil, now >= until {
            flashMessage = nil
            flashUntil = nil
        }
        pollClaude()
        switch phase {
        case .idle: break
        case .working: tickWorking()
        case .onBreak: tickBreak()
        }
        if tickCount % 2 == 0 { checkFrontmostForDrift() }
    }

    private func tickWorking() {
        if !blockOver, let end = blockEndsAt, now >= end {
            blockOver = true
            blockOverAt = now
            checkInPending = false
            awaitingTag = false
            Sounds.play(.blockEnd)
            showHUD()
            if settings.celebrations, let s = session {
                let n = s.blocks.count
                let pomo = s.pomodoroProgress(completedBlocks: n).map { " 🍅\($0.done)/\($0.of)" } ?? ""
                Celebration.show(title: "ブロッククリア 🏆", subtitle: "\(n)ブロック目 完了\(pomo)")
            }
        }
        if blockOver, let at = blockOverAt, now.timeIntervalSince(at) >= settings.autoBreakAfterSeconds {
            startBreak()
            return
        }
        if checkInPending, let asked = checkInAskedAt, now.timeIntervalSince(asked) >= settings.checkInTimeoutSeconds {
            recordCheckIn(onTask: awaitingTag ? false : nil, tag: nil)
            checkInPending = false
            awaitingTag = false
            scheduleNextCheckIn()
        }
        if settings.checkInsEnabled, !checkInPending, !blockOver, let next = nextCheckInAt, now >= next {
            askCheckIn()
        }
        if claudeActivity == .running, now.timeIntervalSince(lastPromptChange) >= settings.observationPromptSeconds {
            advanceObservationPrompt()
        }
    }

    private func tickBreak() {
        if !breakOverNotified, let end = breakEndsAt, now >= end {
            breakOverNotified = true
            Sounds.play(.breakEnd)
            WindowManager.shared.showBreak()
        }
    }

    // MARK: - Session lifecycle

    func openSetup() { WindowManager.shared.showSetup() }

    func startSession(task: String, criteria: String, steps: [String], plans: [String],
                      blockMinutes: Int, breakMinutes: Int, noise noiseOn: Bool, pomodoro: Bool) {
        if session != nil { endSession() }
        var newSettings = settings
        newSettings.defaultIfThen = plans
        newSettings.blockMinutes = blockMinutes
        newSettings.breakMinutes = breakMinutes
        newSettings.pomodoroMode = pomodoro
        settings = newSettings

        session = SessionRecord(
            task: task, doneCriteria: criteria,
            steps: steps.map { TaskStep(text: $0) },
            ifThenPlans: plans, start: Date(),
            blockMinutes: blockMinutes, breakMinutes: breakMinutes,
            noiseOn: noiseOn,
            longBreakEvery: pomodoro ? max(2, settings.longBreakEvery) : nil,
            longBreakMinutes: pomodoro ? settings.longBreakMinutes : nil
        )
        if noiseOn { startNoise() }
        ShortcutRunner.run(settings.focusOnShortcut)
        WindowManager.shared.closeSetup()
        startBlock()
    }

    func startBlock() {
        guard var s = session else { return }
        now = Date()
        s.blocks.append(WorkBlock(start: now, plannedMinutes: s.blockMinutes))
        session = s
        phase = .working
        blockEndsAt = now.addingTimeInterval(Double(s.blockMinutes) * 60)
        breakEndsAt = nil
        blockOver = false
        blockOverAt = nil
        checkInPending = false
        awaitingTag = false
        scheduleNextCheckIn()
        WindowManager.shared.closeBreak()
        WindowManager.shared.showHUD()
        Sounds.play(.start)
        flash("Lock in ⚡ 今は「\(s.task)」だけ。ほかは全部あと回し", seconds: 5)
    }

    func extendBlock(minutes: Int = 5) {
        guard phase == .working, var s = session, let i = s.blocks.indices.last else { return }
        s.blocks[i].extendedMinutes += minutes
        session = s
        blockEndsAt = max(now, blockEndsAt ?? now).addingTimeInterval(Double(minutes) * 60)
        blockOver = false
        blockOverAt = nil
        scheduleNextCheckIn()
    }

    func startBreak() {
        guard var s = session else { return }
        now = Date()
        if let i = s.blocks.indices.last, s.blocks[i].end == nil { s.blocks[i].end = now }
        session = s
        phase = .onBreak
        blockEndsAt = nil
        blockOver = false
        blockOverAt = nil
        checkInPending = false
        awaitingTag = false
        lastBreakWasLong = s.isLongBreak(afterBlocks: s.blocks.count)
        breakEndsAt = now.addingTimeInterval(Double(s.breakLength(afterBlocks: s.blocks.count)) * 60)
        breakOverNotified = false
        frictionTarget = nil
        WindowManager.shared.closeFriction()
        WindowManager.shared.showBreak()
    }

    func endSession() {
        guard var s = session else { return }
        now = Date()
        if let i = s.blocks.indices.last, s.blocks[i].end == nil { s.blocks[i].end = now }
        s.end = now
        history.insert(s, at: 0)
        reviewingID = s.id
        session = nil
        phase = .idle
        blockEndsAt = nil
        breakEndsAt = nil
        blockOver = false
        checkInPending = false
        awaitingTag = false
        frictionTarget = nil
        stopNoise()
        ShortcutRunner.run(settings.focusOffShortcut)
        WindowManager.shared.closeBreak()
        WindowManager.shared.closeFriction()
        WindowManager.shared.hideHUD()
        WindowManager.shared.showReview()
    }

    func openReview(id: UUID) {
        reviewingID = id
        WindowManager.shared.showReview()
    }

    func updateReview(id: UUID, completed: Bool?, reflection: String) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].completed = completed
        history[i].reflection = reflection
    }

    func toggleHistoryNote(sessionID: UUID, noteID: UUID) {
        guard let i = history.firstIndex(where: { $0.id == sessionID }),
              let j = history[i].notes.firstIndex(where: { $0.id == noteID }) else { return }
        history[i].notes[j].resolved.toggle()
    }

    func finishReview() {
        WindowManager.shared.closeReview()
        reviewingID = nil
    }

    // MARK: - Steps

    func completeCurrentStep() {
        guard var s = session, let i = s.steps.firstIndex(where: { !$0.done }) else { return }
        s.steps[i].done = true
        session = s
        if let next = s.currentStep {
            flash("✓ クリア！ 次：\(next.text)", seconds: 5)
        } else {
            Sounds.play(.combo)
            if settings.celebrations { Celebration.show(title: "全ケースクリア 🏆", subtitle: "\(s.steps.count)/\(s.steps.count) 完了") }
            flash("全ケースクリア 🏆「完了の定義」を満たしたか確認しよう", seconds: 10)
        }
    }

    // MARK: - Self-monitoring check-ins

    private func scheduleNextCheckIn() {
        let scheduler = CheckInScheduler(minMinutes: settings.checkInMinMinutes, maxMinutes: settings.checkInMaxMinutes)
        nextCheckInAt = now.addingTimeInterval(scheduler.nextInterval())
    }

    private func askCheckIn() {
        checkInPending = true
        awaitingTag = false
        checkInAskedAt = now
        Sounds.play(.checkIn)
        showHUD()
    }

    func answerCheckIn(onTask: Bool) {
        guard checkInPending, !awaitingTag else { return }
        if onTask {
            recordCheckIn(onTask: true, tag: nil)
            checkInPending = false
            yesStreak += 1
            if yesStreak >= 3 {
                if [3, 5, 10, 20].contains(yesStreak) { Sounds.play(.combo) }
                flash("🔥 \(yesStreak)コンボ！ 集中キープ", seconds: 4)
            } else {
                flash("集中キープ ✓", seconds: 3)
            }
            scheduleNextCheckIn()
        } else {
            yesStreak = 0
            awaitingTag = true
            checkInAskedAt = now
        }
    }

    func answerTag(_ tag: String) {
        guard checkInPending, awaitingTag else { return }
        recordCheckIn(onTask: false, tag: tag)
        checkInPending = false
        awaitingTag = false
        if let plan = session?.plan(for: tag) {
            flash("気づけたら勝ち。\(plan)", seconds: 10)
        } else {
            flash("気づけたら勝ち。作業に戻ろう", seconds: 6)
        }
        scheduleNextCheckIn()
    }

    private func recordCheckIn(onTask: Bool?, tag: String?) {
        guard var s = session else { return }
        s.checkIns.append(CheckIn(at: now, onTask: onTask, tag: tag,
                                  claudeRunning: claudeActivity == .running,
                                  blockIndex: max(0, s.blocks.count - 1)))
        session = s
    }

    // MARK: - Notes

    func openCapture(_ kind: NoteKind, prefill: String = "") {
        WindowManager.shared.showCapture(kind: kind, prefill: prefill)
    }

    func addNote(_ raw: String, kind: NoteKind) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let note = Note(text: text, kind: kind)
        let count: Int
        if var s = session {
            s.notes.append(note)
            session = s
            count = s.notes.filter { $0.kind == kind }.count
        } else {
            inbox.append(note)
            count = inbox.count
        }
        flash(kind == .parking ? "駐車場に置いた（\(count)件）。続きは休憩で" : "観察メモを追加（\(count)件）", seconds: 4)
    }

    func toggleNote(_ id: UUID) {
        if var s = session, let i = s.notes.firstIndex(where: { $0.id == id }) {
            s.notes[i].resolved.toggle()
            session = s
        } else if let i = inbox.firstIndex(where: { $0.id == id }) {
            inbox[i].resolved.toggle()
        }
    }

    func clearResolvedInbox() { inbox.removeAll { $0.resolved } }

    // MARK: - Claude Code bridge

    private func pollClaude() {
        guard let tailer else { return }
        for e in tailer.poll() { apply(e) }
    }

    private func apply(_ e: ClaudeEvent) {
        if let p = e.project { claudeProject = p }
        let previous = claudeActivity
        guard e.activity != previous else { return }
        claudeActivity = e.activity
        claudeSince = now
        switch e.activity {
        case .running:
            claudeNeedsAttention = false
            advanceObservationPrompt()
        case .done, .waiting:
            claudeNeedsAttention = true
            if settings.claudeSound { Sounds.play(e.activity == .done ? .claudeDone : .claudeWaiting) }
            if session != nil { showHUD() }
        case .idle:
            claudeNeedsAttention = false
        }
    }

    func acknowledgeClaude() {
        claudeNeedsAttention = false
        if claudeActivity != .running { claudeActivity = .idle }
    }

    private func advanceObservationPrompt() {
        let prompts = DefaultContent.observationPrompts
        promptIndex = (promptIndex + 1) % prompts.count
        observationPrompt = prompts[promptIndex]
        lastPromptChange = now
    }

    // MARK: - Drift friction

    func handleActivate(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if !Matching.appMatches(name: app.localizedName, bundleID: app.bundleIdentifier, list: settings.distractingApps) {
            lastWorkAppPID = app.processIdentifier
        }
        checkFrontmostForDrift()
    }

    private func checkFrontmostForDrift() {
        guard phase == .working, settings.driftDetection, frictionTarget == nil else { return }
        if let until = driftAllowedUntil, now < until { return }
        if let last = lastFrictionAt, now.timeIntervalSince(last) < 15 { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        if Matching.appMatches(name: app.localizedName, bundleID: app.bundleIdentifier, list: settings.distractingApps) {
            showFriction(target: app.localizedName ?? "このアプリ")
            return
        }
        guard settings.browserURLCheck, AppWatcher.isBrowser(app), !urlCheckInFlight else { return }
        urlCheckInFlight = true
        let pid = app.processIdentifier
        AppWatcher.fetchURL(of: app) { url in
            AppState.shared.handleBrowserURL(url, pid: pid)
        }
    }

    private func handleBrowserURL(_ url: String?, pid: pid_t) {
        urlCheckInFlight = false
        guard phase == .working, frictionTarget == nil,
              let url, let host = Matching.host(of: url),
              let hit = Matching.matchedDomain(host: host, domains: settings.distractingDomains),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        if let until = driftAllowedUntil, now < until { return }
        showFriction(target: hit)
    }

    private func showFriction(target: String) {
        frictionTarget = target
        lastFrictionAt = now
        WindowManager.shared.showFriction()
    }

    func resolveFriction(_ choice: DriftChoice) {
        guard let target = frictionTarget else { return }
        if var s = session {
            s.drifts.append(DriftEvent(at: now, target: target, choice: choice))
            session = s
        }
        frictionTarget = nil
        lastFrictionAt = now
        WindowManager.shared.closeFriction()
        switch choice {
        case .returned:
            if returnToWorkApp() {
                flash("復帰成功 ⚡ 続きをやろう", seconds: 5)
            } else {
                flash("復帰成功 ⚡ タブを作業用に切り替えよう（⌘W で閉じるのもあり）", seconds: 8)
            }
        case .noted:
            openCapture(.parking)
        case .allowed:
            driftAllowedUntil = now.addingTimeInterval(Double(settings.allowMinutes) * 60)
            flash("\(settings.allowMinutes)分だけOK。時間が来たらまた声をかけます", seconds: 6)
        }
    }

    /// Brings back the last non-distracting app. Returns false when that app is the one in front
    /// (e.g. a distracting tab inside the same browser used for QA), so the user needs to switch tabs.
    private func returnToWorkApp() -> Bool {
        guard let pid = lastWorkAppPID,
              pid != NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let url = app.bundleURL else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return true
    }

    // MARK: - Noise

    func toggleNoise() { noisePlaying ? stopNoise() : startNoise() }

    func startNoise() {
        noise.color = settings.noiseColor
        noise.volume = Float(settings.noiseVolume)
        noise.start()
        noisePlaying = noise.isPlaying
        if noisePlaying, var s = session, !s.noiseOn {
            s.noiseOn = true
            session = s
        }
    }

    func stopNoise() {
        noise.stop()
        noisePlaying = false
    }

    // MARK: - HUD & messages

    func showHUD() {
        WindowManager.shared.showHUD()
    }

    func toggleHUD() {
        if WindowManager.shared.isHUDVisible {
            WindowManager.shared.hideHUD()
        } else {
            WindowManager.shared.showHUD()
        }
    }

    func flash(_ message: String, seconds: Double) {
        flashMessage = message
        flashUntil = Date().addingTimeInterval(seconds)
    }
}
