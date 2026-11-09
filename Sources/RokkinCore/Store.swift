import Foundation

/// JSON persistence in ~/Library/Application Support/Rokkin. Nothing leaves the machine.
public final class Store {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("Rokkin")
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    public func loadSettings() -> AppSettings { load(AppSettings.self, "settings.json") ?? AppSettings() }
    public func saveSettings(_ s: AppSettings) { save(s, "settings.json") }

    public func loadHistory() -> [SessionRecord] { load([SessionRecord].self, "history.json") ?? [] }
    public func saveHistory(_ h: [SessionRecord]) { save(h, "history.json") }

    /// Notes captured while no session is running.
    public func loadInbox() -> [Note] { load([Note].self, "inbox.json") ?? [] }
    public func saveInbox(_ n: [Note]) { save(n, "inbox.json") }

    /// The in-progress session, for recovery after a crash or restart.
    public func loadCurrent() -> SessionRecord? { load(SessionRecord.self, "current.json") }
    public func saveCurrent(_ s: SessionRecord?) {
        if let s {
            save(s, "current.json")
        } else {
            try? FileManager.default.removeItem(at: url("current.json"))
        }
    }
}
