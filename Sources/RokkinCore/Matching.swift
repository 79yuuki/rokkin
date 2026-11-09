import Foundation

public enum Matching {
    public static func normalizeDomain(_ raw: String) -> String {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) {
            d.removeFirst(prefix.count)
        }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        return d
    }

    public static func host(of urlString: String) -> String? {
        guard let host = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))?.host, !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }

    /// Returns the matching entry when `host` is the domain itself or one of its subdomains.
    public static func matchedDomain(host: String, domains: [String]) -> String? {
        let h = host.lowercased()
        for raw in domains {
            let d = normalizeDomain(raw)
            guard !d.isEmpty else { continue }
            if h == d || h.hasSuffix("." + d) { return d }
        }
        return nil
    }

    /// Matches an app by display name (case-insensitive) or exact bundle identifier.
    public static func appMatches(name: String?, bundleID: String?, list: [String]) -> Bool {
        for raw in list {
            let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }
            if let name, name.compare(entry, options: [.caseInsensitive]) == .orderedSame { return true }
            if let bundleID, bundleID == entry { return true }
        }
        return false
    }

    /// Splits a multi-line / comma separated text field into a clean list.
    public static func list(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n,、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
