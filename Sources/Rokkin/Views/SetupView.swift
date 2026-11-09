import RokkinCore
import SwiftUI

/// Quick start: one line and Enter. Everything else is optional and tucked away,
/// because the hardest part for ADHD is getting started at all.
struct SetupView: View {
    @EnvironmentObject var state: AppState

    enum Length: Hashable {
        case minutes(Int)
        case pomodoro
    }

    @State private var task = ""
    @State private var length: Length = .minutes(25)
    @State private var showMore = false
    @State private var criteria = ""
    @State private var plansText = ""
    @State private var breakMinutes = 5
    @State private var noise = false
    @State private var phoneAway = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var options: [Length] {
        var mins = [15, 25, 45]
        if let rec = state.recommendedBlockMinutes { mins.append(rec) }
        mins.append(state.settings.blockMinutes)
        return Array(Set(mins)).sorted().map { .minutes($0) } + [.pomodoro]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("何に Lock in する？")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(RokkinTheme.gradient)

            TextField("例：週次レポートを書き上げる（空欄でもOK）", text: $task)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focused)
                .onSubmit { start() }

            Picker("", selection: $length) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let rec = state.recommendedBlockMinutes {
                Text("あなたの記録からのおすすめは \(rec)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if state.session != nil {
                Text("始めると、いまのセッションは終了してリザルトに記録されます")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(showMore ? "設定を閉じる" : "もっと設定する（任意）") { showMore.toggle() }
                    .buttonStyle(.link)
                Spacer()
                Button("キャンセル") { WindowManager.shared.closeSetup() }
                    .keyboardShortcut(.cancelAction)
                Button("Lock in ⚡") { start() }
                    .keyboardShortcut(.defaultAction)
                    .tint(RokkinTheme.pink)
                    .controlSize(.large)
            }

            if showMore { moreSettings }

            Text("Enter でスタート ・ ⌃⌥L でいつでもこの画面")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if !loaded {
                loaded = true
                plansText = state.settings.defaultIfThen.joined(separator: "\n")
                breakMinutes = state.settings.breakMinutes
                noise = state.settings.noiseByDefault
                length = state.settings.pomodoroMode ? .pomodoro : .minutes(state.settings.blockMinutes)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                focused = true
            }
        }
    }

    private var moreSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("完了の定義（どうなったら終わり？）") {
                TextField("例：全セクションが埋まって、送信できる状態", text: $criteria)
                    .textFieldStyle(.roundedBorder)
            }
            field("if-then プラン（最初から入っています。書き換えもOK）") {
                TextEditor(text: $plansText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 76)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            if length != .pomodoro {
                Stepper(value: $breakMinutes, in: 1...20) { Text("休憩 \(breakMinutes)分") }
            }
            Toggle("背景ノイズを流す（\(state.settings.noiseColor.label)）", isOn: $noise)
            Toggle("スマホを視界の外に置いた", isOn: $phoneAway)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func label(_ option: Length) -> String {
        switch option {
        case .minutes(let m):
            return state.recommendedBlockMinutes == m ? "\(m)分 ★" : "\(m)分"
        case .pomodoro:
            return "🍅 ポモドーロ"
        }
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func start() {
        let name = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let pomodoro = length == .pomodoro
        var block = 25
        if case .minutes(let m) = length { block = m }
        state.startSession(
            task: name.isEmpty ? "いまの作業" : name,
            criteria: criteria.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: [],
            plans: lines(plansText),
            blockMinutes: block,
            breakMinutes: pomodoro ? 5 : breakMinutes,
            noise: noise,
            pomodoro: pomodoro
        )
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.semibold))
            content()
        }
    }
}
