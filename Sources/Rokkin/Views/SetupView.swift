import RokkinCore
import SwiftUI

/// The starting ritual: one task, a concrete finish line, and if-then plans for the known traps.
struct SetupView: View {
    @EnvironmentObject var state: AppState

    @State private var task = ""
    @State private var criteria = ""
    @State private var stepsText = ""
    @State private var plansText = ""
    @State private var blockMinutes = 25
    @State private var breakMinutes = 5
    @State private var phoneAway = false
    @State private var tabsClosed = false
    @State private var noise = false
    @State private var pomodoro = false
    @State private var loaded = false

    private var canStart: Bool { !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ひとつ決めて、Lock in ⚡")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(RokkinTheme.gradient)
                    Text("やることを1つに絞って、終わりの形を決めたら、あとはロックインするだけ。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                field("今からやる、ひとつの作業") {
                    TextField("例：決済フローのQA（Claudeにブラウザ操作させて確認）", text: $task)
                        .textFieldStyle(.roundedBorder)
                }
                field("完了の定義 — どうなったら終わり？") {
                    TextField("例：QAシートのケース1〜12が全部 OK / NG 判定済み", text: $criteria)
                        .textFieldStyle(.roundedBorder)
                }
                field("手順・QAケース（1行に1つ。任意）") {
                    editor($stepsText, height: 90)
                }
                field("if-then プラン（脱線しそうな場面 → そのときやること）") {
                    editor($plansText, height: 76)
                }

                Toggle(isOn: $pomodoro) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🍅 ポモドーロモード")
                        Text("25分集中＋5分休憩。\(state.settings.longBreakEvery)回ごとに\(state.settings.longBreakMinutes)分の長い休憩。延長なしで区切りを守る")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: pomodoro) { on in
                    if on {
                        blockMinutes = 25
                        breakMinutes = 5
                    }
                }

                HStack(spacing: 24) {
                    Stepper(value: $blockMinutes, in: 5...90, step: 5) {
                        Text("作業ブロック \(blockMinutes)分")
                    }
                    Stepper(value: $breakMinutes, in: 1...20) {
                        Text("休憩 \(breakMinutes)分")
                    }
                }
                if let rec = state.recommendedBlockMinutes, rec != blockMinutes {
                    HStack {
                        Text("最近の記録では、脱線するまでの時間の中央値から \(rec)分ブロックがおすすめです")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("\(rec)分にする") { blockMinutes = rec }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("スマホを視界の外（別の部屋・カバンの中）に置いた", isOn: $phoneAway)
                        Toggle("今の作業に関係ないタブ・アプリを閉じた", isOn: $tabsClosed)
                        Toggle("背景ノイズを流す（\(state.settings.noiseColor.label)）", isOn: $noise)
                        if !state.settings.focusOnShortcut.isEmpty {
                            Text("開始時にショートカット「\(state.settings.focusOnShortcut)」を実行します")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("環境を整える", systemImage: "leaf")
                }

                HStack {
                    Text("⌃⌥M 駐車場メモ ・ ⌃⌥O 観察メモ ・ ⌃⌥Y/N 自己チェック ・ ⌃⌥H HUD")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("キャンセル") { WindowManager.shared.closeSetup() }
                        .keyboardShortcut(.cancelAction)
                    Button("Lock in ⚡") { start() }
                        .keyboardShortcut(.defaultAction)
                        .tint(RokkinTheme.pink)
                        .controlSize(.large)
                        .disabled(!canStart)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 700)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            plansText = state.settings.defaultIfThen.joined(separator: "\n")
            blockMinutes = state.settings.blockMinutes
            breakMinutes = state.settings.breakMinutes
            noise = state.settings.noiseByDefault
            pomodoro = state.settings.pomodoroMode
        }
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func start() {
        guard canStart else { return }
        state.startSession(
            task: task.trimmingCharacters(in: .whitespacesAndNewlines),
            criteria: criteria.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: lines(stepsText),
            plans: lines(plansText),
            blockMinutes: blockMinutes,
            breakMinutes: breakMinutes,
            noise: noise,
            pomodoro: pomodoro
        )
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func editor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }
}
