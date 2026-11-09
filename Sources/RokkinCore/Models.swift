import Foundation

/// One step of the task (e.g. one QA case). Externalises working memory at the point of performance.
public struct TaskStep: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public enum NoteKind: String, Codable, CaseIterable {
    /// "Distractibility delay" (Safren CBT): park the urge, deal with it later.
    case parking
    /// QA findings captured while watching Claude work.
    case observation
}

public struct Note: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var at: Date
    public var text: String
    public var kind: NoteKind
    public var resolved: Bool

    public init(id: UUID = UUID(), at: Date = Date(), text: String, kind: NoteKind, resolved: Bool = false) {
        self.id = id
        self.at = at
        self.text = text
        self.kind = kind
        self.resolved = resolved
    }
}

/// A self-monitoring-of-attention probe ("Was I paying attention?").
public struct CheckIn: Codable, Identifiable, Equatable {
    public var id: UUID
    public var at: Date
    /// true = on task, false = off task, nil = no answer
    public var onTask: Bool?
    public var tag: String?
    public var claudeRunning: Bool
    public var blockIndex: Int

    public init(id: UUID = UUID(), at: Date, onTask: Bool?, tag: String? = nil, claudeRunning: Bool = false, blockIndex: Int) {
        self.id = id
        self.at = at
        self.onTask = onTask
        self.tag = tag
        self.claudeRunning = claudeRunning
        self.blockIndex = blockIndex
    }
}

public struct WorkBlock: Codable, Equatable {
    public var start: Date
    public var end: Date?
    public var plannedMinutes: Int
    public var extendedMinutes: Int

    public init(start: Date, end: Date? = nil, plannedMinutes: Int, extendedMinutes: Int = 0) {
        self.start = start
        self.end = end
        self.plannedMinutes = plannedMinutes
        self.extendedMinutes = extendedMinutes
    }
}

public enum DriftChoice: String, Codable {
    case returned, noted, allowed
}

public struct DriftEvent: Codable, Equatable {
    public var at: Date
    public var target: String
    public var choice: DriftChoice

    public init(at: Date, target: String, choice: DriftChoice) {
        self.at = at
        self.target = target
        self.choice = choice
    }
}

public struct SessionRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var task: String
    public var doneCriteria: String
    public var steps: [TaskStep]
    public var ifThenPlans: [String]
    public var start: Date
    public var end: Date?
    public var blockMinutes: Int
    public var breakMinutes: Int
    public var blocks: [WorkBlock]
    public var checkIns: [CheckIn]
    public var notes: [Note]
    public var drifts: [DriftEvent]
    public var noiseOn: Bool
    public var completed: Bool?
    public var reflection: String
    /// Pomodoro mode: every N-th break is a long break. nil = no long breaks.
    public var longBreakEvery: Int?
    public var longBreakMinutes: Int?

    public init(
        id: UUID = UUID(),
        task: String,
        doneCriteria: String = "",
        steps: [TaskStep] = [],
        ifThenPlans: [String] = [],
        start: Date,
        end: Date? = nil,
        blockMinutes: Int,
        breakMinutes: Int,
        blocks: [WorkBlock] = [],
        checkIns: [CheckIn] = [],
        notes: [Note] = [],
        drifts: [DriftEvent] = [],
        noiseOn: Bool = false,
        completed: Bool? = nil,
        reflection: String = "",
        longBreakEvery: Int? = nil,
        longBreakMinutes: Int? = nil
    ) {
        self.id = id
        self.task = task
        self.doneCriteria = doneCriteria
        self.steps = steps
        self.ifThenPlans = ifThenPlans
        self.start = start
        self.end = end
        self.blockMinutes = blockMinutes
        self.breakMinutes = breakMinutes
        self.blocks = blocks
        self.checkIns = checkIns
        self.notes = notes
        self.drifts = drifts
        self.noiseOn = noiseOn
        self.completed = completed
        self.reflection = reflection
        self.longBreakEvery = longBreakEvery
        self.longBreakMinutes = longBreakMinutes
    }

    public var currentStep: TaskStep? { steps.first { !$0.done } }

    // MARK: Pomodoro

    public var isPomodoro: Bool { (longBreakEvery ?? 0) > 0 }

    /// Whether the break after `completedBlocks` finished blocks is a long one (every N-th).
    public func isLongBreak(afterBlocks completedBlocks: Int) -> Bool {
        guard let every = longBreakEvery, every > 0, completedBlocks > 0 else { return false }
        return completedBlocks % every == 0
    }

    public func breakLength(afterBlocks completedBlocks: Int) -> Int {
        isLongBreak(afterBlocks: completedBlocks) ? (longBreakMinutes ?? breakMinutes) : breakMinutes
    }

    /// Tomatoes in the current cycle, e.g. (2, 4) = two of four done before the long break.
    /// A finished cycle shows as full (4, 4) until the next block starts.
    public func pomodoroProgress(completedBlocks: Int) -> (done: Int, of: Int)? {
        guard let every = longBreakEvery, every > 0 else { return nil }
        guard completedBlocks > 0 else { return (0, every) }
        let r = completedBlocks % every
        return (r == 0 ? every : r, every)
    }
    public var doneStepCount: Int { steps.filter(\.done).count }

    /// Picks the if-then plan most relevant to a distraction tag (falls back to the first plan).
    public func plan(for tag: String?) -> String? {
        let keywords: [String: [String]] = [
            "スマホ": ["スマホ", "携帯", "phone"],
            "調べ物": ["調べ", "検索", "search"],
            "SNS・ニュース": ["SNS", "ニュース", "X", "YouTube"],
            "ぼーっと": ["ぼーっと", "待ち", "Claude"],
        ]
        if let tag, let words = keywords[tag] {
            if let hit = ifThenPlans.first(where: { plan in words.contains { plan.localizedCaseInsensitiveContains($0) } }) {
                return hit
            }
        }
        return ifThenPlans.first
    }
}

public enum TimeFormat {
    public static func mmss(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60)時間\(m % 60)分" }
        return "\(m)分"
    }
}
