import Foundation

/// The time range the dashboard summarises.
public enum InsightPeriod: String, CaseIterable, Identifiable, Codable {
    case last7
    case last30
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .last7: return "直近7日"
        case .last30: return "直近30日"
        case .all: return "全期間"
        }
    }

    /// Number of calendar days including today; nil = everything.
    public var days: Int? {
        switch self {
        case .last7: return 7
        case .last30: return 30
        case .all: return nil
        }
    }
}

public struct RankedItem: Equatable, Identifiable {
    public var name: String
    public var count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// Self-check answers that fell in one hour of the day (0–23), across all days.
public struct HourPoint: Equatable, Identifiable {
    public var hour: Int
    public var yes: Int
    public var answered: Int
    public var id: Int { hour }
    public var rate: Double? { answered == 0 ? nil : Double(yes) / Double(answered) }

    public init(hour: Int, yes: Int, answered: Int) {
        self.hour = hour
        self.yes = yes
        self.answered = answered
    }
}

/// One calendar week (Monday start).
public struct WeekPoint: Equatable, Identifiable {
    public var start: Date
    public var sessions: Int
    public var workedSeconds: TimeInterval
    public var yes: Int
    public var answered: Int
    public var id: Date { start }
    public var rate: Double? { answered == 0 ? nil : Double(yes) / Double(answered) }

    public init(start: Date, sessions: Int = 0, workedSeconds: TimeInterval = 0, yes: Int = 0, answered: Int = 0) {
        self.start = start
        self.sessions = sessions
        self.workedSeconds = workedSeconds
        self.yes = yes
        self.answered = answered
    }
}

public struct DayPoint: Equatable, Identifiable {
    public var date: Date
    public var sessions: Int
    public var workedSeconds: TimeInterval
    public var id: Date { date }

    public init(date: Date, sessions: Int = 0, workedSeconds: TimeInterval = 0) {
        self.date = date
        self.sessions = sessions
        self.workedSeconds = workedSeconds
    }
}

/// Everything the dashboard shows. Built from the saved history only; nothing leaves the Mac.
public struct Insights: Equatable {
    public var period: InsightPeriod
    /// Below this many answers a rate is shown as "not enough data yet".
    public var minSamples: Int

    // Totals for the period
    public var sessions: Int = 0
    public var workedSeconds: TimeInterval = 0
    /// Blocks that ran their planned length.
    public var blocksCleared: Int = 0
    public var yes: Int = 0
    public var answered: Int = 0
    /// "No" answers: each one is a drift you noticed ("気づけたら勝ち").
    public var noticedOnCheck: Int = 0
    public var driftStops: Int = 0
    /// Detours where you went back or parked a note instead of continuing.
    public var driftReturned: Int = 0
    /// Longest run of consecutive "yes" answers within a session.
    public var bestCombo: Int = 0
    public var completed: Int = 0
    /// Sessions where "done?" was answered at all.
    public var judged: Int = 0

    // Breakdowns for the period
    public var triggers: [RankedItem] = []
    public var detours: [RankedItem] = []
    public var hours: [HourPoint] = (0..<24).map { HourPoint(hour: $0, yes: 0, answered: 0) }
    public var claudeYes: Int = 0
    public var claudeAnswered: Int = 0
    public var otherYes: Int = 0
    public var otherAnswered: Int = 0
    public var noise = NoiseComparison(withNoise: nil, withoutNoise: nil, sessionsWith: 0, sessionsWithout: 0)

    // Independent of the period
    public var recommendedBlockMinutes: Int?
    /// Oldest first; the last entry is the current week.
    public var weekly: [WeekPoint] = []
    /// Oldest first; the last entry is today.
    public var daily: [DayPoint] = []

    public init(period: InsightPeriod, minSamples: Int) {
        self.period = period
        self.minSamples = minSamples
    }

    public var onTaskRate: Double? { answered == 0 ? nil : Double(yes) / Double(answered) }
    public var claudeRate: Double? { claudeAnswered == 0 ? nil : Double(claudeYes) / Double(claudeAnswered) }
    public var otherRate: Double? { otherAnswered == 0 ? nil : Double(otherYes) / Double(otherAnswered) }
    /// Every moment you caught yourself: "no" answers plus detours you turned back from.
    public var noticed: Int { noticedOnCheck + driftReturned }
    public var isEmpty: Bool { sessions == 0 }

    /// The hour with the highest on-task rate among hours with enough answers.
    public var bestHour: HourPoint? {
        hours.filter { $0.answered >= minSamples }
            .max { a, b in
                let ra = a.rate ?? 0, rb = b.rate ?? 0
                return ra != rb ? ra < rb : a.answered < b.answered
            }
    }

    /// This week's on-task rate minus last week's, in percentage points (both weeks need enough answers).
    public var weekOverWeekPoints: Int? {
        guard weekly.count >= 2 else { return nil }
        let this = weekly[weekly.count - 1], last = weekly[weekly.count - 2]
        guard this.answered >= minSamples, last.answered >= minSamples,
              let a = this.rate, let b = last.rate else { return nil }
        return Int(((a - b) * 100).rounded())
    }

    public var thisWeek: WeekPoint? { weekly.last }
}

public enum InsightsBuilder {
    /// Monday-start weeks, whatever the user's locale says.
    public static func weekCalendar(_ calendar: Calendar) -> Calendar {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 1
        return cal
    }

    public static func build(
        history: [SessionRecord],
        period: InsightPeriod,
        now: Date = Date(),
        calendar: Calendar = .current,
        weeks: Int = 8,
        days: Int = 14,
        minSamples: Int = 5
    ) -> Insights {
        let cal = weekCalendar(calendar)
        var ins = Insights(period: period, minSamples: minSamples)
        let inPeriod = sessions(history: history, period: period, now: now, calendar: cal)

        var triggers: [String: Int] = [:]
        var detours: [String: Int] = [:]
        for s in inPeriod {
            let st = s.stats(now: now)
            ins.sessions += 1
            ins.workedSeconds += st.workedSeconds
            ins.blocksCleared += clearedBlocks(s, now: now)
            ins.yes += st.onTaskYes
            ins.answered += st.answered
            ins.noticedOnCheck += st.onTaskNo
            ins.driftStops += st.driftCount
            ins.driftReturned += st.driftReturned
            ins.bestCombo = max(ins.bestCombo, bestCombo(s))
            if let c = s.completed {
                ins.judged += 1
                if c { ins.completed += 1 }
            }
            for c in s.checkIns {
                guard let onTask = c.onTask else { continue }
                if !onTask {
                    triggers[c.tag ?? "未分類", default: 0] += 1
                }
                let h = cal.component(.hour, from: c.at)
                if (0..<24).contains(h) {
                    ins.hours[h].answered += 1
                    if onTask { ins.hours[h].yes += 1 }
                }
                if c.claudeRunning {
                    ins.claudeAnswered += 1
                    if onTask { ins.claudeYes += 1 }
                } else {
                    ins.otherAnswered += 1
                    if onTask { ins.otherYes += 1 }
                }
            }
            for d in s.drifts {
                detours[d.target, default: 0] += 1
            }
        }
        ins.triggers = ranked(triggers)
        ins.detours = ranked(detours)
        ins.noise = SelfExperiment.noiseComparison(history: inPeriod)
        ins.recommendedBlockMinutes = AttentionSpan.recommendedBlockMinutes(history: history, now: now)
        ins.weekly = weekly(history: history, now: now, calendar: cal, count: weeks)
        ins.daily = daily(history: history, now: now, calendar: cal, count: days)
        return ins
    }

    /// Sessions that started within the period (whole calendar days, today included).
    public static func sessions(history: [SessionRecord], period: InsightPeriod, now: Date = Date(), calendar: Calendar = .current) -> [SessionRecord] {
        guard let d = period.days else { return history }
        let from = calendar.date(byAdding: .day, value: -(d - 1), to: calendar.startOfDay(for: now)) ?? now
        return history.filter { $0.start >= from }
    }

    static func ranked(_ counts: [String: Int]) -> [RankedItem] {
        counts.map { RankedItem(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// A block counts as cleared when it ran its planned length (a few seconds of slack).
    static func clearedBlocks(_ s: SessionRecord, now: Date) -> Int {
        s.blocks.filter { b in
            guard let end = b.end else { return false }
            return end.timeIntervalSince(b.start) >= Double(b.plannedMinutes) * 60 - 5
        }.count
    }

    /// Longest run of "yes" answers; an unanswered check neither adds to nor breaks the run.
    static func bestCombo(_ s: SessionRecord) -> Int {
        var best = 0, run = 0
        for c in s.checkIns.sorted(by: { $0.at < $1.at }) {
            switch c.onTask {
            case .some(true):
                run += 1
                best = max(best, run)
            case .some(false):
                run = 0
            case .none:
                continue
            }
        }
        return best
    }

    static func weekly(history: [SessionRecord], now: Date, calendar cal: Calendar, count: Int) -> [WeekPoint] {
        guard count > 0, let current = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var points: [WeekPoint] = (0..<count).reversed().compactMap { i in
            cal.date(byAdding: .weekOfYear, value: -i, to: current).map { WeekPoint(start: $0) }
        }
        let index = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.start, $0.offset) })
        for s in history {
            guard let ws = cal.dateInterval(of: .weekOfYear, for: s.start)?.start, let i = index[ws] else { continue }
            let st = s.stats(now: now)
            points[i].sessions += 1
            points[i].workedSeconds += st.workedSeconds
            points[i].yes += st.onTaskYes
            points[i].answered += st.answered
        }
        return points
    }

    static func daily(history: [SessionRecord], now: Date, calendar cal: Calendar, count: Int) -> [DayPoint] {
        guard count > 0 else { return [] }
        let today = cal.startOfDay(for: now)
        var points: [DayPoint] = (0..<count).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).map { DayPoint(date: $0) }
        }
        let index = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.date, $0.offset) })
        for s in history {
            guard let i = index[cal.startOfDay(for: s.start)] else { continue }
            points[i].sessions += 1
            points[i].workedSeconds += s.stats(now: now).workedSeconds
        }
        return points
    }
}

extension Insights {
    /// A plain summary to paste into notes, or to hand to Claude for a closer look.
    public func markdown(calendar: Calendar = .current) -> String {
        func md(_ d: Date) -> String {
            let c = calendar.dateComponents([.month, .day], from: d)
            return "\(c.month ?? 0)/\(c.day ?? 0)"
        }
        func rateWithCount(_ r: Double?, _ n: Int) -> String {
            r == nil ? "—" : "\(Rates.percent(r))（\(n)回答）"
        }
        var out: [String] = []
        out.append("# Rokkin ダッシュボード（\(period.label)）")
        out.append("")
        if isEmpty {
            out.append("この期間の記録はまだありません。")
            return out.joined(separator: "\n") + "\n"
        }
        out.append("- セッション：\(sessions)回 ／ 作業時間：\(TimeFormat.minutes(workedSeconds)) ／ クリアしたブロック：\(blocksCleared)")
        out.append("- 集中率：\(Rates.percent(onTaskRate))（はい \(yes) ／ 回答 \(answered)）")
        out.append("- 気づけた回数：\(noticed)（自己チェックの「いいえ」\(noticedOnCheck) ＋ 寄り道から戻った \(driftReturned)）")
        out.append("- 寄り道ストップ：\(driftStops)回 ／ 最高コンボ：\(bestCombo)")
        if judged > 0 { out.append("- 完了の定義を達成：\(completed)/\(judged)") }
        if let rec = recommendedBlockMinutes { out.append("- おすすめのブロック長：\(rec)分") }

        out.append("")
        out.append("## 時間帯別の集中率")
        let active = hours.filter { $0.answered > 0 }
        if active.isEmpty {
            out.append("自己チェックの回答がまだありません。")
        } else {
            out.append("| 時間帯 | 集中率 | 回答数 |")
            out.append("|---|---|---|")
            for h in active { out.append("| \(h.hour)時台 | \(Rates.percent(h.rate)) | \(h.answered) |") }
            if let b = bestHour { out.append(""); out.append("いちばん集中できている時間帯：\(b.hour)時台（\(Rates.percent(b.rate))）") }
        }

        out.append("")
        out.append("## 脱線のきっかけ（自己チェックで「いいえ」と答えた理由）")
        if triggers.isEmpty { out.append("なし") }
        for (i, t) in triggers.prefix(10).enumerated() { out.append("\(i + 1). \(t.name)：\(t.count)回") }

        out.append("")
        out.append("## 寄り道先（ひと呼吸が出たアプリ・サイト）")
        if detours.isEmpty { out.append("なし") }
        for (i, t) in detours.prefix(10).enumerated() { out.append("\(i + 1). \(t.name)：\(t.count)回") }

        out.append("")
        out.append("## 自分で比べる")
        out.append("- Claude 実行中：\(rateWithCount(claudeRate, claudeAnswered)) ／ それ以外：\(rateWithCount(otherRate, otherAnswered))")
        out.append("- ノイズあり：\(Rates.percent(noise.withNoise))（\(noise.sessionsWith)セッション） ／ なし：\(Rates.percent(noise.withoutNoise))（\(noise.sessionsWithout)セッション）")

        out.append("")
        out.append("## 週ごとの推移（月曜はじまり）")
        out.append("| 週 | セッション | 作業時間 | 集中率 |")
        out.append("|---|---|---|---|")
        for w in weekly { out.append("| \(md(w.start))〜 | \(w.sessions) | \(TimeFormat.minutes(w.workedSeconds)) | \(Rates.percent(w.rate)) |") }
        if let d = weekOverWeekPoints { out.append(""); out.append("先週との差：\(d >= 0 ? "+" : "")\(d)ポイント") }
        return out.joined(separator: "\n") + "\n"
    }
}
