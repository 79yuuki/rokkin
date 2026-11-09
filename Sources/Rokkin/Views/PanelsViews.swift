import RokkinCore
import SwiftUI

/// Quick capture for the "distractibility delay": write the urge down, go straight back.
struct CaptureView: View {
    let kind: NoteKind
    let initialText: String
    let onSubmit: @MainActor (String) -> Void
    let onCancel: @MainActor () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .parking ? "駐車場メモ — 後で見る" : "観察メモ — QAで気づいたこと",
                  systemImage: kind == .parking ? "tray.and.arrow.down" : "eye")
                .font(.headline)
            TextField(kind == .parking ? "調べたいこと・思いついたこと" : "例：ログイン後のトースト文言が仕様と違う",
                      text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onSubmit(text) }
            HStack {
                Text("Enterで保存して元の作業へ ・ Escでキャンセル")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("キャンセル") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            text = initialText
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                focused = true
            }
        }
        .onExitCommand { onCancel() }
    }
}

/// Self-nudge friction: a short pause plus a deliberate choice, with "go back" always available.
struct FrictionView: View {
    @EnvironmentObject var state: AppState
    @State private var remaining = 5

    var body: some View {
        VStack(spacing: 14) {
            Text("ひと呼吸おこう").font(.title2.bold())
            Text("「\(state.frictionTarget ?? "")」を開いています")
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("今やると決めたのは").font(.callout).foregroundStyle(.secondary)
                Text(state.session?.task ?? "")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(1, state.settings.frictionSeconds)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text(remaining > 0 ? "\(remaining)" : "…")
                    .font(.title.monospacedDigit().weight(.semibold))
            }
            .frame(width: 70, height: 70)
            Text(remaining > 0 ? "ゆっくり吸って、吐いて。これは決めた作業？" : "どうする？")
                .font(.callout)
            HStack(spacing: 10) {
                Button("作業に戻る") { state.resolveFriction(.returned) }
                    .keyboardShortcut(.defaultAction)
                Button("メモして戻る") { state.resolveFriction(.noted) }
                Button("\(state.settings.allowMinutes)分だけ使う") { state.resolveFriction(.allowed) }
                    .disabled(remaining > 0)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 440)
        .task {
            remaining = max(0, state.settings.frictionSeconds)
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let onToggle: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if note.kind == .parking {
                Button { onToggle() } label: {
                    Image(systemName: note.resolved ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "eye").foregroundStyle(.secondary)
            }
            Text(note.text)
                .strikethrough(note.resolved)
                .foregroundStyle(note.resolved ? Color.secondary : Color.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Text(note.at, style: .time).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BreakView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.breakIsOver ? "休憩おわり ⚡" : "休憩中 ☕︎").font(.largeTitle.bold())
                Spacer()
                Text(state.timerText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            }
            if let s = state.session {
                Text("作業：\(s.task)").font(.headline)
                if state.lastBreakWasLong {
                    Text("🍅 \(s.longBreakEvery ?? 4)ポモドーロ達成！ 今回は長めの休憩。しっかり離れよう")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(RokkinTheme.pink)
                }
                lastBlockSummary(s)
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(DefaultContent.breakActivities, id: \.self) { Text("・\($0)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("画面から離れて体を動かそう", systemImage: "figure.walk")
                }
                parkingBox(s)
                HStack {
                    Button("セッションを終了してリザルトへ") { state.endSession() }
                    Spacer()
                    Button("次のブロックへ Lock in（\(s.blockMinutes)分）") { state.startBlock() }
                        .keyboardShortcut(.defaultAction)
                        .tint(RokkinTheme.pink)
                        .controlSize(.large)
                }
            } else {
                Text("進行中のセッションはありません").foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func lastBlockSummary(_ s: SessionRecord) -> some View {
        let idx = s.blocks.count - 1
        let checks = s.checkIns.filter { $0.blockIndex == idx && $0.onTask != nil }
        let yes = checks.filter { $0.onTask == true }.count
        let start = s.blocks.last?.start ?? s.start
        let drifts = s.drifts.filter { $0.at >= start }.count
        let text = checks.isEmpty
            ? "このブロックは自己チェックなし。寄り道ストップ \(drifts)回"
            : "このブロック：自己チェック \(yes)/\(checks.count) で集中、寄り道ストップ \(drifts)回"
        return Text(text).font(.callout).foregroundStyle(.secondary)
    }

    private func parkingBox(_ s: SessionRecord) -> some View {
        let items = s.notes.filter { $0.kind == .parking }
        let open = items.filter { !$0.resolved }.count
        return GroupBox {
            if items.isEmpty {
                Text("駐車場メモはありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今ここで片付けるか、後に回すかを決めよう。済んだらチェック。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(items) { n in
                                NoteRow(note: n) { state.toggleNote(n.id) }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
        } label: {
            Label("駐車場メモ（未処理 \(open)件）", systemImage: "tray")
        }
    }
}
