import XCTest
@testable import RokkinCore

private let tokyo: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// Wednesday 2026-11-11 20:00 JST; the week started Monday 11/9.
private let now = at(11, 11, 20)

/// One-block session. `answers` are (minutes after start, answer, tag).
private func session(
    _ start: Date,
    answers: [(Int, Bool?, String?)] = [],
    claude: Bool = false,
    planned: Int = 25,
    worked: Int = 25,
    drifts: [(String, DriftChoice)] = [],
    noise: Bool = false,
    completed: Bool? = nil
) -> SessionRecord {
    let end = start.addingTimeInterval(Double(worked) * 60)
    return SessionRecord(
        task: "t",
        start: start,
        end: end,
        blockMinutes: planned,
        breakMinutes: 5,
        blocks: [WorkBlock(start: start, end: end, plannedMinutes: planned)],
        checkIns: answers.map {
            CheckIn(at: start.addingTimeInterval(Double($0.0) * 60), onTask: $0.1, tag: $0.2, claudeRunning: claude, blockIndex: 0)
        },
        drifts: drifts.map { DriftEvent(at: start, target: $0.0, choice: $0.1) },
        noiseOn: noise,
        completed: completed
    )
}

private func yesNo(yes: Int, no: Int) -> [(Int, Bool?, String?)] {
    (0..<yes).map { ($0 + 1, true, nil) } + (0..<no).map { (yes + $0 + 1, false, "スマホ") }
}

final class InsightsTests: XCTestCase {
    private var twoSessions: [SessionRecord] {
        [
            session(at(11, 11, 14), answers: [(5, false, "スマホ"), (10, false, "調べ物"), (15, false, "スマホ"), (20, true, nil)],
                    claude: true, worked: 10, drifts: [("youtube.com", .noted)], completed: false),
            session(at(11, 10, 9), answers: [(3, true, nil), (6, true, nil), (9, nil, nil), (12, true, nil), (15, false, "スマホ"), (18, true, nil)],
                    drifts: [("youtube.com", .returned), ("Slack", .allowed)], completed: true),
        ]
    }

    func testTotalsRankingsAndComparisons() {
        let ins = InsightsBuilder.build(history: twoSessions, period: .last7, now: now, calendar: tokyo)
        XCTAssertEqual(ins.sessions, 2)
        XCTAssertEqual(ins.workedSeconds, 35 * 60)
        XCTAssertEqual(ins.blocksCleared, 1, "the 10-minute block ended early")
        XCTAssertEqual(ins.yes, 5)
        XCTAssertEqual(ins.answered, 9)
        XCTAssertEqual(ins.noticedOnCheck, 4)
        XCTAssertEqual(ins.driftStops, 3)
        XCTAssertEqual(ins.driftReturned, 2, "returned and noted count, allowed does not")
        XCTAssertEqual(ins.noticed, 6)
        XCTAssertEqual(ins.bestCombo, 3, "an unanswered check neither adds to nor breaks the combo")
        XCTAssertEqual(ins.completed, 1)
        XCTAssertEqual(ins.judged, 2)
        XCTAssertEqual(ins.triggers, [RankedItem(name: "スマホ", count: 3), RankedItem(name: "調べ物", count: 1)])
        XCTAssertEqual(ins.detours, [RankedItem(name: "youtube.com", count: 2), RankedItem(name: "Slack", count: 1)])
        XCTAssertEqual(ins.claudeAnswered, 4)
        XCTAssertEqual(ins.claudeYes, 1)
        XCTAssertEqual(ins.otherAnswered, 5)
        XCTAssertEqual(ins.otherYes, 4)
        XCTAssertEqual(ins.noise.sessionsWithout, 2)
        XCTAssertEqual(ins.noise.sessionsWith, 0)
    }

    func testHourBucketsAndBestHourNeedsEnoughAnswers() {
        let history = [
            session(at(11, 10, 9), answers: yesNo(yes: 5, no: 0)),
            session(at(11, 10, 14), answers: yesNo(yes: 4, no: 1)),
            session(at(11, 10, 22), answers: yesNo(yes: 1, no: 0)),
        ]
        let ins = InsightsBuilder.build(history: history, period: .all, now: now, calendar: tokyo)
        XCTAssertEqual(ins.hours.count, 24)
        XCTAssertEqual(ins.hours[9].answered, 5)
        XCTAssertEqual(ins.hours[14].yes, 4)
        XCTAssertEqual(ins.hours[22].rate, 1.0)
        XCTAssertEqual(ins.bestHour?.hour, 9, "22時 is 100% but has only one answer")
    }

    private var spreadHistory: [SessionRecord] {
        [
            session(at(11, 10, 10), answers: yesNo(yes: 8, no: 2)),  // this week: 80%
            session(at(11, 3, 10), answers: yesNo(yes: 3, no: 3)),   // last week: 50%
            session(at(10, 20, 10), answers: yesNo(yes: 1, no: 0)),  // week of 10/19
            session(at(8, 1, 10), answers: yesNo(yes: 1, no: 0)),    // outside the 8-week window
        ]
    }

    func testWeeklyTrendIsMondayStartAndComparesWeeks() {
        let ins = InsightsBuilder.build(history: spreadHistory, period: .all, now: now, calendar: tokyo)
        XCTAssertEqual(ins.weekly.count, 8)
        XCTAssertEqual(ins.weekly[7].start, at(11, 9, 0))
        XCTAssertEqual(ins.weekly[6].start, at(11, 2, 0))
        XCTAssertEqual(ins.weekly[7].sessions, 1)
        XCTAssertEqual(ins.weekly[7].rate, 0.8)
        XCTAssertEqual(ins.weekly[6].rate, 0.5)
        XCTAssertEqual(ins.weekly[4].start, at(10, 19, 0))
        XCTAssertEqual(ins.weekly[4].sessions, 1)
        XCTAssertEqual(ins.weekly.map(\.sessions).reduce(0, +), 3)
        XCTAssertEqual(ins.weekOverWeekPoints, 30)
    }

    func testWeekOverWeekNeedsEnoughAnswers() {
        let history = [
            session(at(11, 10, 10), answers: yesNo(yes: 2, no: 0)),
            session(at(11, 3, 10), answers: yesNo(yes: 3, no: 3)),
        ]
        let ins = InsightsBuilder.build(history: history, period: .all, now: now, calendar: tokyo)
        XCTAssertNil(ins.weekOverWeekPoints)
    }

    func testPeriodFilter() {
        func count(_ p: InsightPeriod) -> Int {
            InsightsBuilder.build(history: spreadHistory, period: p, now: now, calendar: tokyo).sessions
        }
        XCTAssertEqual(count(.last7), 1, "7 days = 11/5 through today")
        XCTAssertEqual(count(.last30), 3)
        XCTAssertEqual(count(.all), 4)
    }

    func testDailyWorkTime() {
        let ins = InsightsBuilder.build(history: spreadHistory, period: .all, now: now, calendar: tokyo)
        XCTAssertEqual(ins.daily.count, 14)
        XCTAssertEqual(ins.daily.last?.date, at(11, 11, 0))
        XCTAssertEqual(ins.daily[12].date, at(11, 10, 0))
        XCTAssertEqual(ins.daily[12].workedSeconds, 25 * 60)
        XCTAssertEqual(ins.daily[13].sessions, 0)
    }

    func testMarkdownSummary() {
        let md = InsightsBuilder.build(history: twoSessions, period: .last7, now: now, calendar: tokyo).markdown(calendar: tokyo)
        XCTAssertTrue(md.hasPrefix("# Rokkin ダッシュボード（直近7日）"))
        XCTAssertTrue(md.contains("集中率：56%（はい 5 ／ 回答 9）"))
        XCTAssertTrue(md.contains("気づけた回数：6"))
        XCTAssertTrue(md.contains("1. スマホ：3回"))
        XCTAssertTrue(md.contains("1. youtube.com：2回"))
        XCTAssertTrue(md.contains("| 11/9〜 | 2 | 35分 | 56% |"))
    }

    func testEmptyHistory() {
        let ins = InsightsBuilder.build(history: [], period: .last30, now: now, calendar: tokyo)
        XCTAssertTrue(ins.isEmpty)
        XCTAssertNil(ins.onTaskRate)
        XCTAssertNil(ins.bestHour)
        XCTAssertNil(ins.weekOverWeekPoints)
        XCTAssertEqual(ins.weekly.count, 8)
        XCTAssertTrue(ins.markdown(calendar: tokyo).contains("この期間の記録はまだありません"))
    }
}
