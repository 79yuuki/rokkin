import AppKit
import RokkinCore
import SwiftUI

@main
@MainActor
struct RokkinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in AppState.shared.didLaunch() }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.menuBarText.isEmpty {
            state.menuBarImage
        } else {
            Text("\(state.menuBarImage) \(state.menuBarText)").monospacedDigit()
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let s = state.session {
            Text("\(state.phase == .onBreak ? "休憩中" : "作業中")：\(s.task)")
            if state.phase == .working {
                Button("今すぐ休憩する") { state.startBreak() }
            } else {
                Button("次のブロックを始める") { state.startBlock() }
            }
            Button("セッションを終了してリザルトへ") { state.endSession() }
        } else {
            Button("新しいセッションを始める…  ⌃⌥L") { state.openSetup() }
        }
        Divider()
        Button("駐車場メモ  ⌃⌥M") { state.openCapture(.parking) }
        Button("HUDの表示切替  ⌃⌥H") { state.toggleHUD() }
        Button(state.noisePlaying ? "ノイズを止める" : "ノイズを流す") { state.toggleNoise() }
        Divider()
        Button("記録…") { WindowManager.shared.showHistory() }
        Button("設定…") { WindowManager.shared.showSettings() }
        Divider()
        Button("Rokkin を終了") { NSApp.terminate(nil) }
    }
}
