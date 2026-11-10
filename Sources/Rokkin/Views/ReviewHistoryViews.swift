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

                if s.notes.contains(where: { $0.kind == .observation }) {
                    // sessions recorded before the memos were merged
                    notesBox(s, kind: .observation, title: "観察メモ")
                }
                notesBox(s, kind: .parking, title: "メモ")

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
