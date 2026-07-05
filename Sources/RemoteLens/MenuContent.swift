import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.isActive {
            Button("🖥 通常モードに戻す") {
                state.restore()
            }
        } else {
            Button("📱 リモートモード（縦長・スマホ縦持ち）") {
                state.enterPortrait()
            }
            Button("📱 リモートモード（横長）") {
                state.enterRemote()
            }
        }

        Text("現在: \(state.currentModeLabel)")

        Picker("プリセット", selection: $state.preset) {
            ForEach(RemotePreset.allCases) { preset in
                Text(preset.title).tag(preset)
            }
        }

        if let error = state.lastError {
            Divider()
            Text("⚠️ \(error)")
        }

        Divider()

        Toggle("ログイン時に起動", isOn: Binding(
            get: { state.launchAtLogin },
            set: { state.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("RemoteLens を終了") {
            NSApplication.shared.terminate(nil)
        }
    }
}
