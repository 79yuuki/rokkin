import Foundation

extension SessionRecord {
    public func notesMarkdown(kind: NoteKind, includeResolved: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        let items = notes.filter { $0.kind == kind && (includeResolved || !$0.resolved) }
        guard !items.isEmpty else { return "" }
        return items.map { n in
            let box = kind == .parking ? (n.resolved ? "- [x] " : "- [ ] ") : "- "
            return "\(box)\(n.text)（\(f.string(from: n.at))）"
        }.joined(separator: "\n")
    }

    public func markdownReport(now: Date = Date()) -> String {
        let st = stats(now: now)
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        var out: [String] = []
        out.append("# \(task)")
        out.append("")
        out.append("- 日時: \(f.string(from: start))")
        if !doneCriteria.isEmpty { out.append("- 完了の定義: \(doneCriteria)") }
        if let completed { out.append("- 結果: \(completed ? "達成" : "未達")") }
        out.append("- 作業時間: \(TimeFormat.minutes(st.workedSeconds))（\(blocks.count)ブロック）")
        if let r = st.onTaskRate {
            out.append("- 自己チェックの集中率: \(Int((r * 100).rounded()))%（\(st.onTaskYes)/\(st.answered)）")
        }
        if !steps.isEmpty {
            out.append("")
            out.append("## 手順")
            out += steps.map { "- [\($0.done ? "x" : " ")] \($0.text)" }
        }
        let obs = notesMarkdown(kind: .observation)
        if !obs.isEmpty {
            out.append("")
            out.append("## 観察メモ（QA）")
            out.append(obs)
        }
        let parking = notesMarkdown(kind: .parking)
        if !parking.isEmpty {
            out.append("")
            out.append("## 駐車場メモ")
            out.append(parking)
        }
        if !reflection.isEmpty {
            out.append("")
            out.append("## 次回へのメモ")
            out.append(reflection)
        }
        return out.joined(separator: "\n")
    }
}
