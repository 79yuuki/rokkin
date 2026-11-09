import XCTest
@testable import RokkinCore

final class MatchingTests: XCTestCase {
    func testDomainMatchesSubdomainsOnly() {
        let list = ["youtube.com", "https://www.X.com/", "news.yahoo.co.jp"]
        XCTAssertEqual(Matching.matchedDomain(host: "www.youtube.com", domains: list), "youtube.com")
        XCTAssertEqual(Matching.matchedDomain(host: "m.youtube.com", domains: list), "youtube.com")
        XCTAssertEqual(Matching.matchedDomain(host: "x.com", domains: list), "x.com")
        XCTAssertNil(Matching.matchedDomain(host: "notyoutube.com", domains: list))
        XCTAssertNil(Matching.matchedDomain(host: "yahoo.co.jp", domains: list))
        XCTAssertEqual(Matching.matchedDomain(host: "news.yahoo.co.jp", domains: list), "news.yahoo.co.jp")
    }

    func testHostParsing() {
        XCTAssertEqual(Matching.host(of: "https://WWW.YouTube.com/watch?v=1"), "www.youtube.com")
        XCTAssertNil(Matching.host(of: "about:blank"))
    }

    func testAppMatching() {
        XCTAssertTrue(Matching.appMatches(name: "messages", bundleID: nil, list: ["Messages"]))
        XCTAssertTrue(Matching.appMatches(name: "Foo", bundleID: "jp.naver.line.mac", list: ["jp.naver.line.mac"]))
        XCTAssertFalse(Matching.appMatches(name: "Xcode", bundleID: "com.apple.dt.Xcode", list: DefaultContent.distractingApps))
    }

    func testListParsing() {
        XCTAssertEqual(Matching.list(from: "a.com\n b.com ,c.com、\n\n"), ["a.com", "b.com", "c.com"])
    }
}

final class ClaudeBridgeTests: XCTestCase {
    func testParser() {
        let e = ClaudeEventParser.parse(line: "stop 1700000000 my-app\n")
        XCTAssertEqual(e?.activity, .done)
        XCTAssertEqual(e?.project, "my-app")
        XCTAssertEqual(e?.at, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(ClaudeEventParser.parse(line: "running 1700000000")?.activity, .running)
        XCTAssertNil(ClaudeEventParser.parse(line: "running 1700000000 .")?.project)
        XCTAssertNil(ClaudeEventParser.parse(line: "bogus 1"))
        XCTAssertNil(ClaudeEventParser.parse(line: "   "))
    }

    func testTailerIgnoresOldEventsAndHandlesPartialLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("claude-events")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "stop 1 old\n".write(to: url, atomically: true, encoding: .utf8)

        let tailer = ClaudeEventTailer(url: url)
        XCTAssertEqual(tailer.poll(), [])

        let h = try FileHandle(forWritingTo: url)
        h.seekToEndOfFile()
        h.write("running 2 p\nwait".data(using: .utf8)!)
        XCTAssertEqual(tailer.poll().map(\.activity), [.running])
        h.write("ing 3 p\n".data(using: .utf8)!)
        try h.close()
        XCTAssertEqual(tailer.poll().map(\.activity), [.waiting])

        // Truncation is detected.
        try "stop 4 p\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(tailer.poll().map(\.activity), [.done])
    }

    func testHooksMergeIsIdempotentAndPreservesExisting() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
            ],
        ]
        XCTAssertFalse(ClaudeHooksInstaller.isInstalled(in: existing))
        let once = ClaudeHooksInstaller.merge(into: existing)
        XCTAssertTrue(ClaudeHooksInstaller.isInstalled(in: once))
        let twice = ClaudeHooksInstaller.merge(into: once)
        let stop = (twice["hooks"] as! [String: Any])["Stop"] as! [Any]
        XCTAssertEqual(stop.count, 2, "existing hook kept, ours added once")
        XCTAssertEqual(twice["model"] as? String, "opus")
        let post = (twice["hooks"] as! [String: Any])["PostToolUse"] as! [[String: Any]]
        XCTAssertEqual(post.first?["matcher"] as? String, "*")
    }

    func testInstallWritesBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try #"{"theme":"dark"}"#.write(to: url, atomically: true, encoding: .utf8)
        let backup = try ClaudeHooksInstaller.install(at: url, now: Date(timeIntervalSince1970: 42))
        XCTAssertEqual(backup?.lastPathComponent, "settings.json.rokkin-backup-42")
        XCTAssertTrue(ClaudeHooksInstaller.isInstalled(at: url))
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(obj["theme"] as? String, "dark")
    }

    func testHookCommandRunsInShell() throws {
        #if os(Linux) || os(macOS)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", ClaudeHooksInstaller.command(for: "stop")]
        p.environment = ["HOME": home.path, "CLAUDE_PROJECT_DIR": "/tmp/my-proj", "PATH": "/usr/bin:/bin"]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        let text = try String(contentsOf: home.appendingPathComponent(".rokkin/claude-events"), encoding: .utf8)
        let e = ClaudeEventParser.parse(line: text)
        XCTAssertEqual(e?.activity, .done)
        XCTAssertEqual(e?.project, "my-proj")
        #endif
    }
}

final class StatsTests: XCTestCase {
    private func session(start: Date, blockMinutes: Int, firstOffAfterMinutes: [Double?]) -> SessionRecord {
        var s = SessionRecord(task: "QA", start: start, blockMinutes: blockMinutes, breakMinutes: 5)
        var t = start
        for (i, off) in firstOffAfterMinutes.enumerated() {
            let block = WorkBlock(start: t, end: t.addingTimeInterval(Double(blockMinutes) * 60), plannedMinutes: blockMinutes)
            s.blocks.append(block)
            s.checkIns.append(CheckIn(at: t.addingTimeInterval(120), onTask: true, blockIndex: i))
            if let off {
                s.checkIns.append(CheckIn(at: t.addingTimeInterval(off * 60), onTask: false, tag: "スマホ", claudeRunning: true, blockIndex: i))
            }
            t = t.addingTimeInterval(Double(blockMinutes + 5) * 60)
        }
        return s
    }

    func testStats() {
        let s = session(start: Date(timeIntervalSince1970: 0), blockMinutes: 25, firstOffAfterMinutes: [12, nil])
        let st = s.stats()
        XCTAssertEqual(st.onTaskYes, 2)
        XCTAssertEqual(st.onTaskNo, 1)
        XCTAssertEqual(st.onTaskRate!, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(st.tagCounts, [TagCount(tag: "スマホ", count: 1)])
        XCTAssertEqual(st.workedSeconds, 50 * 60, accuracy: 0.001)
        XCTAssertEqual(st.onTaskRateWhileClaudeRunning, 0)
        XCTAssertEqual(st.onTaskRateOtherwise, 1)
    }

    func testRecommendedBlockFromDriftTimes() {
        let s1 = session(start: Date(timeIntervalSince1970: 0), blockMinutes: 25, firstOffAfterMinutes: [12, 18])
        let s2 = session(start: Date(timeIntervalSince1970: 10_000), blockMinutes: 25, firstOffAfterMinutes: [16])
        // median of 12, 16, 18 = 16 -> floor to 15
        XCTAssertEqual(AttentionSpan.recommendedBlockMinutes(history: [s1, s2]), 15)
    }

    func testRecommendationWhenRarelyDrifting() {
        let s = session(start: Date(timeIntervalSince1970: 0), blockMinutes: 25, firstOffAfterMinutes: [nil, nil, nil])
        XCTAssertEqual(AttentionSpan.recommendedBlockMinutes(history: [s]), 30)
    }

    func testNoRecommendationWithoutData() {
        XCTAssertNil(AttentionSpan.recommendedBlockMinutes(history: []))
    }

    func testPlanForTag() {
        var s = SessionRecord(task: "x", start: Date(), blockMinutes: 25, breakMinutes: 5)
        s.ifThenPlans = DefaultContent.ifThenPlans
        XCTAssertEqual(s.plan(for: "スマホ"), DefaultContent.ifThenPlans[1])
        XCTAssertEqual(s.plan(for: "調べ物"), DefaultContent.ifThenPlans[0])
        XCTAssertEqual(s.plan(for: "ぼーっと"), DefaultContent.ifThenPlans[2])
        XCTAssertEqual(s.plan(for: "その他"), DefaultContent.ifThenPlans[0])
    }

    func testScheduler() {
        var g = SystemRandomNumberGenerator()
        let sch = CheckInScheduler(minMinutes: 8, maxMinutes: 3) // reversed on purpose
        for _ in 0..<200 {
            let v = sch.nextInterval(using: &g)
            XCTAssertGreaterThanOrEqual(v, 180)
            XCTAssertLessThanOrEqual(v, 480)
        }
    }

    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.mmss(65), "1:05")
        XCTAssertEqual(TimeFormat.mmss(-3), "0:00")
        XCTAssertEqual(TimeFormat.mmss(59.2), "1:00")
    }
}

final class PersistenceTests: XCTestCase {
    func testSettingsDecodeWithMissingKeys() throws {
        let json = #"{"blockMinutes": 15, "noiseColor": "brown"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.blockMinutes, 15)
        XCTAssertEqual(s.noiseColor, .brown)
        XCTAssertEqual(s.breakMinutes, 5)
        XCTAssertEqual(s.distractingDomains, DefaultContent.distractingDomains)
    }

    func testStoreRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = Store(directory: dir)
        var s = SessionRecord(task: "QA", start: Date(timeIntervalSince1970: 1000), blockMinutes: 25, breakMinutes: 5)
        s.notes.append(Note(at: Date(timeIntervalSince1970: 1100), text: "文言違い", kind: .observation))
        store.saveHistory([s])
        XCTAssertEqual(store.loadHistory(), [s])
        store.saveCurrent(s)
        XCTAssertEqual(store.loadCurrent(), s)
        store.saveCurrent(nil)
        XCTAssertNil(store.loadCurrent())
    }

    func testReport() {
        var s = SessionRecord(task: "決済QA", doneCriteria: "12ケース判定", start: Date(), blockMinutes: 25, breakMinutes: 5)
        s.notes = [Note(text: "トースト文言", kind: .observation), Note(text: "Vitest調べる", kind: .parking)]
        let md = s.markdownReport()
        XCTAssertTrue(md.contains("# 決済QA"))
        XCTAssertTrue(md.contains("## 観察メモ"))
        XCTAssertTrue(md.contains("## メモ"))
        XCTAssertTrue(md.contains("- [ ] Vitest調べる"))
    }
}

final class PomodoroTests: XCTestCase {
    func testLongBreakEveryFourth() {
        let s = SessionRecord(task: "QA", start: Date(), blockMinutes: 25, breakMinutes: 5,
                              longBreakEvery: 4, longBreakMinutes: 15)
        XCTAssertTrue(s.isPomodoro)
        XCTAssertEqual((1...8).map { s.breakLength(afterBlocks: $0) }, [5, 5, 5, 15, 5, 5, 5, 15])
        XCTAssertFalse(s.isLongBreak(afterBlocks: 0))
    }

    func testProgress() {
        let s = SessionRecord(task: "QA", start: Date(), blockMinutes: 25, breakMinutes: 5,
                              longBreakEvery: 4, longBreakMinutes: 15)
        XCTAssertEqual(s.pomodoroProgress(completedBlocks: 0)?.done, 0)
        XCTAssertEqual(s.pomodoroProgress(completedBlocks: 3)?.done, 3)
        XCTAssertEqual(s.pomodoroProgress(completedBlocks: 4)?.done, 4)
        XCTAssertEqual(s.pomodoroProgress(completedBlocks: 5)?.done, 1)
        XCTAssertEqual(s.pomodoroProgress(completedBlocks: 5)?.of, 4)
    }

    func testFreeModeHasNoLongBreaks() {
        let s = SessionRecord(task: "QA", start: Date(), blockMinutes: 30, breakMinutes: 7)
        XCTAssertFalse(s.isPomodoro)
        XCTAssertNil(s.pomodoroProgress(completedBlocks: 4))
        XCTAssertEqual(s.breakLength(afterBlocks: 4), 7)
    }

    func testOldSessionJSONStillDecodes() throws {
        // A session saved before the pomodoro fields existed.
        var old = SessionRecord(task: "x", start: Date(timeIntervalSince1970: 0), blockMinutes: 25, breakMinutes: 5)
        let enc = JSONEncoder()
        var obj = try JSONSerialization.jsonObject(with: enc.encode(old)) as! [String: Any]
        obj.removeValue(forKey: "longBreakEvery")
        obj.removeValue(forKey: "longBreakMinutes")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        old.longBreakEvery = nil
        XCTAssertEqual(decoded, old)
    }
}
