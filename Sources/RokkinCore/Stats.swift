import Foundation

public struct SessionStats: Equatable {
    public var onTaskYes: Int
    public var onTaskNo: Int
    public var missed: Int
    public var tagCounts: [TagCount]
    public var workedSeconds: TimeInterval
    public var driftCount: Int
    public var driftReturned: Int
    public var parkingCount: Int
    public var observationCount: Int
    /// On-task rate for probes answered while Claude Code was running vs. not.
    public var onTaskRateWhileClaudeRunning: Double?
    public var onTaskRateOtherwise: Double?

    public var answered: Int { onTaskYes + onTaskNo }
    public var onTaskRate: Double? {
        answered == 0 ? nil : Double(onTaskYes) / Double(answered)
    }
}

public struct TagCount: Equatable {
    public var tag: String
    public var count: Int
}

public enum Rates {
    /// Share of answered check-ins that were "on task"; nil when nothing was answered.
    public static func onTask(_ checks: [CheckIn]) -> Double? {
        let answered = checks.compactMap(\.onTask)
        guard !answered.isEmpty else { return nil }
        return Double(answered.filter { $0 }.count) / Double(answered.count)
    }

    public static func percent(_ r: Double?) -> String {
        guard let r else { return "—" }
        return "\(Int((r * 100).rounded()))%"
    }
}

private func rate(_ checks: [CheckIn]) -> Double? { Rates.onTask(checks) }

extension SessionRecord {
    public func stats(now: Date = Date()) -> SessionStats {
        let yes = checkIns.filter { $0.onTask == true }.count
        let no = checkIns.filter { $0.onTask == false }.count
        let missed = checkIns.filter { $0.onTask == nil }.count
        var tags: [String: Int] = [:]
        for c in checkIns where c.onTask == false {
            tags[c.tag ?? "未分類", default: 0] += 1
        }
        let tagCounts = tags.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
        let worked = blocks.reduce(0.0) { sum, b in
            sum + max(0, (b.end ?? now).timeIntervalSince(b.start))
        }
        return SessionStats(
            onTaskYes: yes,
            onTaskNo: no,
            missed: missed,
            tagCounts: tagCounts,
            workedSeconds: worked,
            driftCount: drifts.count,
            driftReturned: drifts.filter { $0.choice != .allowed }.count,
            parkingCount: notes.filter { $0.kind == .parking }.count,
            observationCount: notes.filter { $0.kind == .observation }.count,
            onTaskRateWhileClaudeRunning: rate(checkIns.filter { $0.claudeRunning }),
            onTaskRateOtherwise: rate(checkIns.filter { !$0.claudeRunning })
        )
    }

    /// Time from each block's start to the first "off task" answer in that block.
    /// `censored` samples are blocks that ended with no off-task answer (attention held the whole block).
    public func attentionSpanSamples(now: Date = Date()) -> (uncensored: [TimeInterval], censored: [TimeInterval]) {
        var uncensored: [TimeInterval] = []
        var censored: [TimeInterval] = []
        for (i, block) in blocks.enumerated() {
            let inBlock = checkIns.filter { $0.blockIndex == i && $0.onTask != nil }
            guard !inBlock.isEmpty else { continue }
            if let firstOff = inBlock.filter({ $0.onTask == false }).map(\.at).min() {
                uncensored.append(firstOff.timeIntervalSince(block.start))
            } else {
                censored.append((block.end ?? now).timeIntervalSince(block.start))
            }
        }
        return (uncensored, censored)
    }
}

public enum AttentionSpan {
    /// "Gauge your attention span, then set the timer to it" (Safren et al., CBT for adult ADHD).
    /// Uses the median time-to-first-drift across recent sessions, rounded down to 5 minutes, clamped to 10–50.
    public static func recommendedBlockMinutes(history: [SessionRecord], recentSessions: Int = 10, now: Date = Date()) -> Int? {
        let recent = history.sorted { $0.start > $1.start }.prefix(recentSessions)
        var uncensored: [TimeInterval] = []
        var censored: [TimeInterval] = []
        for s in recent {
            let samples = s.attentionSpanSamples(now: now)
            uncensored += samples.uncensored
            censored += samples.censored
        }
        if uncensored.count >= 3 {
            return clampRound(median(uncensored) / 60)
        }
        if censored.count >= 3 {
            // Rarely drifting: suggest stretching a little beyond the typical block.
            return clampRound(median(censored) / 60 + 5)
        }
        return nil
    }

    static func clampRound(_ minutes: Double) -> Int {
        let floored = Int(minutes / 5) * 5
        return min(50, max(10, floored))
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

public struct NoiseComparison: Equatable {
    public var withNoise: Double?
    public var withoutNoise: Double?
    public var sessionsWith: Int
    public var sessionsWithout: Int
}

public enum SelfExperiment {
    /// Mean session on-task rate with vs. without background noise.
    /// Noise effects vary between people, so this lets the user test it on themselves.
    public static func noiseComparison(history: [SessionRecord]) -> NoiseComparison {
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let with = history.filter(\.noiseOn).compactMap { $0.stats().onTaskRate }
        let without = history.filter { !$0.noiseOn }.compactMap { $0.stats().onTaskRate }
        return NoiseComparison(withNoise: mean(with), withoutNoise: mean(without), sessionsWith: with.count, sessionsWithout: without.count)
    }
}
