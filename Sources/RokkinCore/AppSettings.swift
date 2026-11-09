import Foundation

public enum NoiseColor: String, Codable, CaseIterable, Identifiable {
    case pink, white, brown
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .pink: return "ピンク（研究あり）"
        case .white: return "ホワイト（研究あり）"
        case .brown: return "ブラウン（研究なし）"
        }
    }
}

public struct AppSettings: Codable, Equatable {
    // Blocks & breaks
    public var blockMinutes: Int = 25
    public var breakMinutes: Int = 5
    public var autoBreakAfterSeconds: Double = 60

    // Pomodoro technique (25 min work / 5 min break, long break every 4)
    public var pomodoroMode: Bool = false
    public var longBreakMinutes: Int = 15
    public var longBreakEvery: Int = 4
    /// Confetti at finish moments (block cleared / all steps cleared). Never shown mid-focus.
    public var celebrations: Bool = true

    // Self-monitoring check-ins
    public var checkInsEnabled: Bool = true
    public var checkInMinMinutes: Double = 3
    public var checkInMaxMinutes: Double = 8
    public var checkInTimeoutSeconds: Double = 60

    // Drift friction
    public var driftDetection: Bool = true
    public var browserURLCheck: Bool = true
    public var distractingApps: [String] = DefaultContent.distractingApps
    public var distractingDomains: [String] = DefaultContent.distractingDomains
    public var frictionSeconds: Int = 5
    public var allowMinutes: Int = 5

    // macOS Focus via Shortcuts (Focus can be shared to iPhone)
    public var focusOnShortcut: String = ""
    public var focusOffShortcut: String = ""

    // Background noise
    public var noiseColor: NoiseColor = .pink
    public var noiseVolume: Double = 0.2
    public var noiseByDefault: Bool = false

    // Claude Code
    public var claudeIntegration: Bool = true
    public var claudeSound: Bool = true
    public var observationPromptSeconds: Double = 75

    public var defaultIfThen: [String] = DefaultContent.ifThenPlans

    public init() {}

    /// Tolerant decoding: missing keys (e.g. after an update) fall back to defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        blockMinutes = value(.blockMinutes, blockMinutes)
        breakMinutes = value(.breakMinutes, breakMinutes)
        autoBreakAfterSeconds = value(.autoBreakAfterSeconds, autoBreakAfterSeconds)
        pomodoroMode = value(.pomodoroMode, pomodoroMode)
        longBreakMinutes = value(.longBreakMinutes, longBreakMinutes)
        longBreakEvery = value(.longBreakEvery, longBreakEvery)
        celebrations = value(.celebrations, celebrations)
        checkInsEnabled = value(.checkInsEnabled, checkInsEnabled)
        checkInMinMinutes = value(.checkInMinMinutes, checkInMinMinutes)
        checkInMaxMinutes = value(.checkInMaxMinutes, checkInMaxMinutes)
        checkInTimeoutSeconds = value(.checkInTimeoutSeconds, checkInTimeoutSeconds)
        driftDetection = value(.driftDetection, driftDetection)
        browserURLCheck = value(.browserURLCheck, browserURLCheck)
        distractingApps = value(.distractingApps, distractingApps)
        distractingDomains = value(.distractingDomains, distractingDomains)
        frictionSeconds = value(.frictionSeconds, frictionSeconds)
        allowMinutes = value(.allowMinutes, allowMinutes)
        focusOnShortcut = value(.focusOnShortcut, focusOnShortcut)
        focusOffShortcut = value(.focusOffShortcut, focusOffShortcut)
        noiseColor = value(.noiseColor, noiseColor)
        noiseVolume = value(.noiseVolume, noiseVolume)
        noiseByDefault = value(.noiseByDefault, noiseByDefault)
        claudeIntegration = value(.claudeIntegration, claudeIntegration)
        claudeSound = value(.claudeSound, claudeSound)
        observationPromptSeconds = value(.observationPromptSeconds, observationPromptSeconds)
        defaultIfThen = value(.defaultIfThen, defaultIfThen)
    }
}

/// Randomised check-in intervals. Variable intervals keep the probe unpredictable,
/// as in self-monitoring-of-attention protocols that use tones at irregular times.
public struct CheckInScheduler {
    public var minMinutes: Double
    public var maxMinutes: Double

    public init(minMinutes: Double, maxMinutes: Double) {
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
    }

    public func nextInterval<G: RandomNumberGenerator>(using generator: inout G) -> TimeInterval {
        let lo = max(0.5, min(minMinutes, maxMinutes))
        let hi = max(lo, max(minMinutes, maxMinutes))
        return Double.random(in: lo...hi, using: &generator) * 60
    }

    public func nextInterval() -> TimeInterval {
        var g = SystemRandomNumberGenerator()
        return nextInterval(using: &g)
    }
}
