import RokkinCore
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @State private var outcome = 0 // 0 = unset, 1 = achieved, 2 = not yet
    @State private var reflection = ""
    @State private var sessionID: UUID?
    @State private var copied: String?

    var body: some View {
        Group {
            if let s = state.reviewing {
                content(s)
            } else {
                Text("表示するリザルトがありません").padding(40)
            }
        }
        .frame(width: 580, height: 680)
        .onDisappear { save() }
    }

    private var completedValue: Bool? { outcome == 0 ? nil : outcome == 1 }

    private func save() {
        guard let id = sessionID else { return }
        state.updateReview(id: id, completed: completedValue, reflection: reflection)
    }

    private func content(_ s: SessionRecord) -> some View {
        let st = s.stats()
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("リザルト").font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(RokkinTheme.gradient)
                Text(s.task).font(.title3.weight(.semibold))

                if !s.doneCriteria.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.doneCriteria)
                            Picker("", selection: $outcome) {
                                Text("未記入").tag(0)
                                Text("達成した").tag(1)
                                Text("まだ").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Text("完了の定義") }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        statRow("作業時間", "\(TimeFormat.minutes(st.workedSeconds))（\(s.blocks.count)ブロック）")
                        statRow("自己チェックの集中率", "\(Rates.percent(st.onTaskRate))（\(st.onTaskYes)/\(st.answered)、無回答 \(st.missed)）")
                        if st.onTaskRateWhileClaudeRunning != nil || st.onTaskRateOtherwise != nil {
                            statRow("Claude実行中 / それ以外", "\(Rates.percent(st.onTaskRateWhileClaudeRunning)) / \(Rates.percent(st.onTaskRateOtherwise))")
                        }
                        if !st.tagCounts.isEmpty {
                            statRow("脱線のきっかけ", st.tagCounts.prefix(3).map { "\($0.tag) \($0.count)" }.joined(separator: "、"))
                        }
                        statRow("寄り道ストップ", "\(st.driftCount)回（そのまま戻った/メモ \(st.driftReturned)回）")
                        if !s.steps.isEmpty {
                            statRow("手順", "\(s.doneStepCount)/\(s.steps.count) 完了")
                        }
                        if let rec = state.recommendedBlockMinutes {
                            statRow("次回のおすすめブロック", "\(rec)分")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { Text("記録") }

                notesBox(s, kind: .observation, title: "観察メモ（QA）")
                notesBox(s, kind: .parking, title: "駐車場メモ")

                GroupBox {
                    TextEditor(text: $reflection)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(height: 70)
                } label: { Text("ひとことメモ（次回うまくやるには？）") }

                HStack {
                    Button("レポート全体をコピー") {
                        save()
                        Clipboard.copy((state.reviewing ?? s).markdownReport())
                        copied = "Markdownでコピーしました"
                    }
                    if let copied { Text(copied).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("保存して閉じる") {
                        save()
                        state.finishReview()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .onAppear {
            guard sessionID != s.id else { return }
            sessionID = s.id
            outcome = s.completed.map { $0 ? 1 : 2 } ?? 0
            reflection = s.reflection
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }

    private func notesBox(_ s: SessionRecord, kind: NoteKind, title: String) -> some View {
        let items = s.notes.filter { $0.kind == kind }
        return GroupBox {
            if items.isEmpty {
                Text("なし").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { n in
                        NoteRow(note: n) { state.toggleHistoryNote(sessionID: s.id, noteID: n.id) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            HStack {
                Text("\(title)（\(items.count)件）")
                Spacer()
                if !items.isEmpty {
                    Button("Markdownでコピー") {
                        Clipboard.copy(s.notesMarkdown(kind: kind))
                        copied = "\(title)をコピーしました"
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E) HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("記録").font(.largeTitle.bold())
            insights
            List {
                ForEach(state.history) { s in row(s) }
            }
            .frame(minHeight: 240)
            if !state.inbox.isEmpty { inboxBox }
        }
        .padding(20)
        .frame(width: 660, height: 620)
    }

    private var insights: some View {
        let all = state.history.flatMap(\.checkIns)
        let claude = Rates.onTask(all.filter(\.claudeRunning))
        let other = Rates.onTask(all.filter { !$0.claudeRunning })
        let noise = SelfExperiment.noiseComparison(history: state.history)
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let rec = state.recommendedBlockMinutes {
                    Text("あなたの集中持続（脱線までの中央値）から、おすすめブロックは \(rec)分")
                } else {
                    Text("自己チェックの記録が3ブロック分たまると、あなたに合うブロック長を提案します")
                        .foregroundStyle(.secondary)
                }
                if claude != nil || other != nil {
                    Text("集中率：Claude実行中 \(Rates.percent(claude)) ／ それ以外 \(Rates.percent(other))")
                }
                if noise.sessionsWith > 0 && noise.sessionsWithout > 0 {
                    Text("ノイズあり \(Rates.percent(noise.withNoise))（\(noise.sessionsWith)回） ／ なし \(Rates.percent(noise.withoutNoise))（\(noise.sessionsWithout)回）")
                } else {
                    Text("ノイズあり・なし両方のセッションがたまると、自分に効くか比べられます")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text("あなたのデータ") }
    }

    private func row(_ s: SessionRecord) -> some View {
        let st = s.stats()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.task).lineLimit(1)
                Text(Self.dateFormat.string(from: s.start)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeFormat.minutes(st.workedSeconds)).font(.callout.monospacedDigit())
            Text(Rates.percent(st.onTaskRate)).font(.callout.monospacedDigit()).frame(width: 48, alignment: .trailing)
            Image(systemName: s.completed == true ? "checkmark.seal.fill" : "circle.dotted")
                .foregroundStyle(s.completed == true ? Color.green : Color.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("リザルトを開く") { state.openReview(id: s.id) }
            Button("レポートをコピー") { Clipboard.copy(s.markdownReport()) }
        }
        .onTapGesture(count: 2) { state.openReview(id: s.id) }
    }

    private var inboxBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.inbox) { n in
                    NoteRow(note: n) { state.toggleNote(n.id) }
                }
                Button("済みを削除") { state.clearResolvedInbox() }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text("セッション外のメモ") }
    }
}
