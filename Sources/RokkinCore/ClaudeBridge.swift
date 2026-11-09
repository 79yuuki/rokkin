import Foundation

public enum ClaudeActivity: String, Codable, Equatable {
    case idle, running, done, waiting
}

public struct ClaudeEvent: Equatable {
    public var activity: ClaudeActivity
    public var at: Date
    public var project: String?

    public init(activity: ClaudeActivity, at: Date, project: String? = nil) {
        self.activity = activity
        self.at = at
        self.project = project
    }
}

/// Parses lines written by the Claude Code hooks: `<event> <unix-seconds> [project]`.
public enum ClaudeEventParser {
    public static func parse(line raw: String) -> ClaudeEvent? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let kind = parts.first else { return nil }
        let activity: ClaudeActivity
        switch kind {
        case "running": activity = .running
        case "stop": activity = .done
        case "waiting": activity = .waiting
        case "idle", "end": activity = .idle
        default: return nil
        }
        var at = Date()
        if parts.count > 1, let ts = TimeInterval(parts[1]) { at = Date(timeIntervalSince1970: ts) }
        var project: String? = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : nil
        if project == "" || project == "." || project == "/" { project = nil }
        return ClaudeEvent(activity: activity, at: at, project: project)
    }
}

/// Tails the events file that the hooks append to. Starts at the end so stale events are ignored.
public final class ClaudeEventTailer {
    public let url: URL
    private var offset: UInt64 = 0
    private var partial = ""
    public var maxBytesBeforeTruncate: UInt64 = 512 * 1024

    public init(url: URL, startAtEnd: Bool = true) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if startAtEnd { offset = Self.size(of: url) }
    }

    static func size(of url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    public func poll() -> [ClaudeEvent] {
        let size = Self.size(of: url)
        if size < offset {
            // File was truncated or replaced.
            offset = 0
            partial = ""
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset += UInt64(data.count)

        let text = partial + (String(data: data, encoding: .utf8) ?? "")
        var lines = text.components(separatedBy: "\n")
        partial = lines.removeLast() // incomplete trailing line (empty if text ended with \n)
        let events = lines.compactMap(ClaudeEventParser.parse(line:))

        if partial.isEmpty, offset > maxBytesBeforeTruncate {
            if let h = try? FileHandle(forWritingTo: url) {
                h.truncateFile(atOffset: 0)
                try? h.close()
                offset = 0
            }
        }
        return events
    }
}

/// Adds (idempotently) the hooks that report Claude Code's state to Rokkin.
public enum ClaudeHooksInstaller {
    public static let marker = "# rokkin"

    public struct HookSpec: Equatable {
        public var hookEvent: String
        public var line: String
        public var matcher: String?
    }

    public static let specs: [HookSpec] = [
        HookSpec(hookEvent: "UserPromptSubmit", line: "running", matcher: nil),
        HookSpec(hookEvent: "PostToolUse", line: "running", matcher: "*"),
        HookSpec(hookEvent: "Notification", line: "waiting", matcher: nil),
        HookSpec(hookEvent: "Stop", line: "stop", matcher: nil),
        HookSpec(hookEvent: "SessionEnd", line: "idle", matcher: nil),
    ]

    public static func command(for line: String) -> String {
        "mkdir -p \"$HOME/.rokkin\" && echo \"\(line) $(date +%s) $(basename \"${CLAUDE_PROJECT_DIR:-$PWD}\")\" >> \"$HOME/.rokkin/claude-events\" \(marker)"
    }

    static func group(for spec: HookSpec) -> [String: Any] {
        var g: [String: Any] = [
            "hooks": [["type": "command", "command": command(for: spec.line)]],
        ]
        if let m = spec.matcher { g["matcher"] = m }
        return g
    }

    static func groupHasMarker(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let hooks = g["hooks"] as? [Any] else { return false }
        return hooks.contains { h in
            ((h as? [String: Any])?["command"] as? String)?.contains(marker) == true
        }
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return specs.allSatisfy { spec in
            ((hooks[spec.hookEvent] as? [Any]) ?? []).contains(where: groupHasMarker)
        }
    }

    public static func merge(into settings: [String: Any]) -> [String: Any] {
        var result = settings
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for spec in specs {
            var groups = (hooks[spec.hookEvent] as? [Any]) ?? []
            if !groups.contains(where: groupHasMarker) {
                groups.append(group(for: spec))
            }
            hooks[spec.hookEvent] = groups
        }
        result["hooks"] = hooks
        return result
    }

    public static func defaultSettingsURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    public static func isInstalled(at url: URL = defaultSettingsURL()) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return isInstalled(in: obj)
    }

    public enum InstallError: Error, LocalizedError {
        case unreadable(String)
        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "settings.json を読めませんでした: \(why)"
            }
        }
    }

    /// Merges the hooks into the settings file, writing a timestamped backup first. Returns the backup URL (nil if there was no file).
    @discardableResult
    public static func install(at url: URL = defaultSettingsURL(), now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if !data.isEmpty {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw InstallError.unreadable("トップレベルがオブジェクトではありません")
                }
                settings = obj
            }
            let stamp = Int(now.timeIntervalSince1970)
            let b = url.deletingLastPathComponent().appendingPathComponent("settings.json.rokkin-backup-\(stamp)")
            try data.write(to: b)
            backup = b
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let merged = merge(into: settings)
        let out = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: url, options: .atomic)
        return backup
    }

    /// The JSON to paste manually if the user prefers not to let the app edit settings.json.
    public static func snippet() -> String {
        let merged = merge(into: [:])
        guard let data = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
