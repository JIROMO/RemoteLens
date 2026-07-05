import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isRemoteMode: Bool   // 横長（低解像度）モード
    @Published private(set) var isPortraitMode = false  // 縦長（仮想ディスプレイ）モード
    @Published var preset: RemotePreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: "preset")
            guard oldValue != preset else { return }
            // モード適用中にプリセットを変えたら即座に反映する
            if isRemoteMode {
                enterRemote()
            } else if isPortraitMode {
                do {
                    try manager.setPortraitPreset(preset)
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published var lastError: String?

    private let manager = DisplayManager.shared

    /// 縦長モードの脱出手段（自動復元カウントダウン + 常駐「戻す」ボタン）
    private lazy var rescue: RescuePanel = {
        let panel = RescuePanel()
        panel.onRestore = { [weak self] in self?.restore() }
        return panel
    }()

    var isActive: Bool { isRemoteMode || isPortraitMode }

    init() {
        isRemoteMode = DisplayManager.shared.isRemoteMode
        preset = UserDefaults.standard.string(forKey: "preset")
            .flatMap(RemotePreset.init(rawValue:)) ?? .balanced
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var currentModeLabel: String {
        if isPortraitMode {
            let size = preset.portraitPointSize
            return "\(Int(size.width))×\(Int(size.height)) 縦長 (HiDPI)"
        }
        return manager.currentMode()?.label ?? "不明"
    }

    func enterRemote() {
        do {
            try manager.enterRemoteMode(preset: preset)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        sync()
    }

    func enterPortrait() {
        do {
            try manager.enterPortraitMode(preset: preset)
            lastError = nil
            rescue.showCountdown(seconds: 30)
        } catch {
            lastError = error.localizedDescription
        }
        sync()
    }

    func restore() {
        rescue.close()
        do {
            if manager.isPortraitMode {
                try manager.exitPortraitMode()
            }
            if manager.isRemoteMode {
                try manager.restoreOriginal()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        sync()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "ログイン項目の設定に失敗: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func sync() {
        isRemoteMode = manager.isRemoteMode
        isPortraitMode = manager.isPortraitMode
    }
}
