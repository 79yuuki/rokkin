import RokkinCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            basicTab.tabItem { Label("基本", systemImage: "timer") }
            driftTab.tabItem { Label("寄り道", systemImage: "hand.raised") }
            ClaudeSettingsTab().tabItem { Label("Claude Code", systemImage: "terminal") }
            soundTab.tabItem { Label("サウンド", systemImage: "speaker.wave.2") }
        }
        .padding(16)
        .frame(width: 600, height: 560)
    }

    private var basicTab: some View {
        Form {
            Section("ブロック") {
                Stepper(value: $state.settings.blockMinutes, in: 5...90, step: 5) {
                    Text("作業ブロック \(state.settings.blockMinutes)分")
                }
                Stepper(value: $state.settings.breakMinutes, in: 1...20) {
                    Text("休憩 \(state.settings.breakMinutes)分")
                }
                Stepper(value: $state.settings.autoBreakAfterSeconds, in: 15...300, step: 15) {
                    Text("ブロック終了後、\(Int(state.settings.autoBreakAfterSeconds))秒で自動休憩")
                }
            }
            Section("お祝い") {
                Toggle("ブロッククリアで紙吹雪を出す", isOn: $state.settings.celebrations)
                Text("終わった瞬間にだけ出ます。集中している最中には出しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("試しに出してみる") { Celebration.show(title: "ブロッククリア 🏆", subtitle: "プレビュー") }
            }
            Section("🍅 ポモドーロ") {
                Toggle("新しいセッションをポモドーロモードで始める", isOn: $state.settings.pomodoroMode)
                Stepper(value: $state.settings.longBreakEvery, in: 2...8) {
                    Text("\(state.settings.longBreakEvery)回ごとに長い休憩")
                }
                Stepper(value: $state.settings.longBreakMinutes, in: 10...40, step: 5) {
                    Text("長い休憩 \(state.settings.longBreakMinutes)分")
                }
            }
            Section("自己チェック（ランダムな間隔で「注意向いてた？」）") {
                Toggle("自己チェックを使う", isOn: $state.settings.checkInsEnabled)
                Stepper(value: $state.settings.checkInMinMinutes, in: 1...30, step: 1) {
                    Text("最短 \(Int(state.settings.checkInMinMinutes))分")
                }
                Stepper(value: $state.settings.checkInMaxMinutes, in: 2...45, step: 1) {
                    Text("最長 \(Int(state.settings.checkInMaxMinutes))分")
                }
            }
            Section("集中モード（任意・ショートカット App 経由）") {
                TextField("開始時に実行するショートカット名", text: $state.settings.focusOnShortcut)
                TextField("終了時に実行するショートカット名", text: $state.settings.focusOffShortcut)
                Text("ショートカット App で「集中モードを設定」アクションを作り、その名前を入れてください。集中モードの「デバイス間で共有」をオンにすると iPhone も静かになります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var driftTab: some View {
        Form {
            Section {
                Toggle("寄り道を検出して一呼吸はさむ", isOn: $state.settings.driftDetection)
                Toggle("ブラウザのURLも確認する（Safari / Chrome系）", isOn: $state.settings.browserURLCheck)
                Stepper(value: $state.settings.frictionSeconds, in: 0...15) {
                    Text("待ち時間 \(state.settings.frictionSeconds)秒")
                }
                Stepper(value: $state.settings.allowMinutes, in: 1...30) {
                    Text("「少しだけ使う」の長さ \(state.settings.allowMinutes)分")
                }
                Text("初回はブラウザの操作許可（オートメーション）を求められます。URLはこのMacの中だけで使い、どこにも送りません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("寄り道アプリ（名前またはバンドルID）") {
                ListEditor(items: $state.settings.distractingApps)
            }
            Section("寄り道サイト（ドメイン。サブドメインも対象）") {
                ListEditor(items: $state.settings.distractingDomains)
            }
        }
        .formStyle(.grouped)
    }

    private var soundTab: some View {
        Form {
            Section("背景ノイズ") {
                Picker("種類", selection: $state.settings.noiseColor) {
                    ForEach(NoiseColor.allCases) { Text($0.label).tag($0) }
                }
                Slider(value: $state.settings.noiseVolume, in: 0...1) { Text("音量") }
                Toggle("新しいセッションで最初からオン", isOn: $state.settings.noiseByDefault)
                Button(state.noisePlaying ? "試聴を止める" : "試聴する") { state.toggleNoise() }
                Text("ホワイト／ピンクノイズはADHD傾向のある人の課題成績を小さく改善したというメタ分析がありますが、逆に下がる人もいます。「記録」でノイズあり・なしの集中率を比べて、自分に合うか確かめてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ListEditor: View {
    @Binding var items: [String]
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .frame(height: 110)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                text = items.joined(separator: "\n")
            }
            .onChange(of: text) { newValue in
                guard loaded else { return }
                let parsed = Matching.list(from: newValue)
                if parsed != items { items = parsed }
            }
    }
}

struct ClaudeSettingsTab: View {
    @EnvironmentObject var state: AppState
    @State private var installed = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Claude Code の状態をHUDに表示する", isOn: $state.settings.claudeIntegration)
                Toggle("完了・入力待ちで音を鳴らす", isOn: $state.settings.claudeSound)
                Stepper(value: $state.settings.observationPromptSeconds, in: 30...300, step: 15) {
                    Text("観察プロンプトを \(Int(state.settings.observationPromptSeconds))秒ごとに切り替え")
                }
            }
            Section("hooks の設定") {
                HStack {
                    Button("~/.claude/settings.json に hooks を追加") { install() }
                    Text(installed ? "✓ 設定済み" : "未設定")
                        .foregroundStyle(installed ? Color.green : Color.secondary)
                }
                if let message {
                    Text(message).font(.caption).textSelection(.enabled)
                }
                Text("既存の設定は残したまま追記し、元のファイルはバックアップします。手動で入れる場合は下の hooks を settings.json にマージしてください。反映されない場合は Claude Code を再起動してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(ClaudeHooksInstaller.snippet())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
            }
        }
        .formStyle(.grouped)
        .onAppear { installed = ClaudeHooksInstaller.isInstalled() }
    }

    private func install() {
        do {
            let backup = try ClaudeHooksInstaller.install()
            installed = ClaudeHooksInstaller.isInstalled()
            if let backup {
                message = "追加しました。バックアップ：\(backup.path)"
            } else {
                message = "settings.json を作成して追加しました。"
            }
        } catch {
            message = "追加できませんでした：\(error.localizedDescription)"
        }
    }
}
