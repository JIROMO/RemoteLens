import AppKit
import SwiftUI

@main
struct RemoteLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.isActive ? "iphone" : "display")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock に表示しない（swift run 等の非バンドル実行時の保険。
        // バンドル実行時は Info.plist の LSUIElement でも制御される）
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 縦長モードのまま終了する場合はミラーを解除してから
        // 仮想ディスプレイを消す（解除しなくても OS が復旧するが、明示的に）
        try? DisplayManager.shared.exitPortraitMode()
    }
}
