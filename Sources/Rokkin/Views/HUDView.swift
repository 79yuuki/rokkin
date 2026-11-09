import RokkinCore
import SwiftUI

struct HUDSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Always-on-top strip: the goal, the clock and the next step stay visible at the point of performance.
struct HUDView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(state.phase == .idle ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(RokkinTheme.gradient))
                .frame(height: 4)
            header
            if let s = state.session {
                if !s.doneCriteria.isEmpty {
                    Text("完了の定義：\(s.doneCriteria)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let step = s.currentStep { stepRow(step, s) }
                if state.phase == .working && state.blockOver { blockOverBox }
                if state.phase == .onBreak { breakBox }
                if state.checkInPending { checkInBox }
                if let msg = state.flashMessage { flashBox(msg) }
            } else {
                idleRow
            }
            if state.settings.claudeIntegration && state.claudeActivity != .idle { claudeBox }
            footer
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: HUDSizeKey.self, value: g.size) })
        .onPreferenceChange(HUDSizeKey.self) { _ in
            Task { @MainActor in WindowManager.shared.refreshHUDSize() }
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .idle: return .gray
        case .working: return RokkinTheme.pink
        case .onBreak: return RokkinTheme.cyan
        }
    }

    /// Blocks that have ended (the running one doesn't count yet).
    private func completedBlocks(_ s: SessionRecord) -> Int {
        s.blocks.filter { $0.end != nil }.count
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(phaseColor).frame(width: 9, height: 9)
            Text(state.session?.task ?? "Rokkin")
                .font(.headline)
                .lineLimit(2)
            if state.yesStreak >= 2 && state.phase == .working {
                Text("🔥\(state.yesStreak)")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(RokkinTheme.pink.opacity(0.25)))
                    .help("\(state.yesStreak)コンボ：自己チェックで連続して集中できています")
            }
            Spacer(minLength: 6)
            Text(state.timerText)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(state.blockOver ? Color.orange : Color.primary)
        }
        .overlay(WindowDragArea())
    }

    private var idleRow: some View {
        HStack {
            Text("セッションは始まっていません").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("始める") { state.openSetup() }
        }
    }

    private func stepRow(_ step: TaskStep, _ s: SessionRecord) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { state.completeCurrentStep() } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .help("この手順を完了にする")
            Text(step.text).font(.callout).lineLimit(3)
            Spacer(minLength: 4)
            Text("\(s.doneStepCount)/\(s.steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func box<Content: View>(_ color: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.16)))
    }

    private var blockOverBox: some View {
        box(.orange) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ブロッククリア！ 休憩しよう").font(.callout.weight(.semibold))
                Text("\(Int(state.settings.autoBreakAfterSeconds))秒で自動的に休憩に入ります")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("休憩する") { state.startBreak() }
                    if state.session?.isPomodoro != true {
                        Button("+5分 延長戦") { state.extendBlock(minutes: 5) }
                    }
                }
            }
        }
    }

    private var breakBox: some View {
        box(.blue) {
            HStack {
                Text(state.breakIsOver ? "休憩おわり。次のブロックへ ⚡" : "休憩中。画面から離れよう").font(.callout)
                Spacer()
                if state.breakIsOver {
                    Button("次のブロック") { state.startBlock() }
                } else {
                    Button("休憩画面") { WindowManager.shared.showBreak() }
                }
            }
        }
    }

    private var checkInBox: some View {
        box(.accentColor) {
            if !state.awaitingTag {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今、この作業に注意が向いてた？").font(.callout.weight(.semibold))
                    HStack {
                        Button("はい  ⌃⌥Y") { state.answerCheckIn(onTask: true) }
                        Button("いいえ  ⌃⌥N") { state.answerCheckIn(onTask: false) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("何に引っ張られた？（記録するだけ）").font(.callout.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                              alignment: .leading, spacing: 6) {
                        ForEach(DefaultContent.distractionTags, id: \.self) { tag in
                            Button(tag) { state.answerTag(tag) }
                        }
                    }
                }
            }
        }
    }

    private func flashBox(_ msg: String) -> some View {
        Text(msg)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var claudeBox: some View {
        let a = state.claudeActivity
        let attention = state.claudeNeedsAttention
        let blink = attention && Int(state.now.timeIntervalSince1970) % 2 == 0
        let color: Color = a == .running ? .purple : (a == .waiting ? .orange : .green)
        let icon = a == .running ? "gearshape.2" : (a == .waiting ? "hand.raised" : "checkmark.circle")
        let title = a == .running ? "Claude 実行中" : (a == .waiting ? "Claude が入力待ち" : "Claude 完了！結果を見よう")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.callout.weight(.semibold))
                if let p = state.claudeProject {
                    Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(TimeFormat.mmss(state.now.timeIntervalSince(state.claudeSince)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if a == .running {
                Text("👀 \(state.observationPrompt)")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("気づいたことをメモ  ⌃⌥M") { state.openCapture(.parking) }
                    .controlSize(.small)
            }
            if attention {
                Button(a == .waiting ? "Claudeに応答した" : "結果を確認した") { state.acknowledgeClaude() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(blink ? 0.35 : 0.14)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { state.openCapture(.parking) } label: {
                Label("メモ", systemImage: "tray.and.arrow.down")
            }
            .help("駐車場メモ ⌃⌥M")
            Spacer()
            if let s = state.session, let p = s.pomodoroProgress(completedBlocks: completedBlocks(s)) {
                Text(String(repeating: "🍅", count: p.done) + String(repeating: "・", count: max(0, p.of - p.done)))
                    .font(.caption)
                    .help("ポモドーロ \(p.done)/\(p.of)（\(p.of)回で長い休憩）")
            }
            if let st = state.session?.stats(now: state.now), st.answered > 0 {
                Text("集中 \(st.onTaskYes)/\(st.answered)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Menu {
                if state.phase == .working { Button("今すぐ休憩する") { state.startBreak() } }
                if state.phase == .onBreak { Button("次のブロックを始める") { state.startBlock() } }
                if state.session != nil {
                    Button("セッションを終了してリザルトへ") { state.endSession() }
                } else {
                    Button("新しいセッション…") { state.openSetup() }
                }
                Divider()
                Button(state.noisePlaying ? "ノイズを止める" : "ノイズを流す") { state.toggleNoise() }
                Button("HUDを隠す（⌃⌥H で再表示）") { state.toggleHUD() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
    }
}
