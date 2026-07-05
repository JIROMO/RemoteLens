import CoreGraphics
import Foundation
import VirtualDisplayBridge

/// 切替前のモードを保存・復元するための、CGDisplayMode のスナップショット。
/// ioModeID は再起動で変わる可能性があるため、プロパティ一致を優先して照合する。
struct DisplayModeInfo: Codable, Equatable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioModeID: Int32

    init(mode: CGDisplayMode) {
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        ioModeID = mode.ioDisplayModeID
    }

    var isHiDPI: Bool { pixelWidth > width }
    var label: String { "\(width)×\(height)" + (isHiDPI ? " (HiDPI)" : "") }
}

enum RemotePreset: String, CaseIterable, Codable, Identifiable {
    case maxText
    case balanced
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxText: return "文字最大"
        case .balanced: return "バランス"
        case .wide: return "作業領域広め"
        }
    }

    /// このポイント幅に最も近い HiDPI モードを選ぶ（横長モード用）
    var targetWidth: Int {
        switch self {
        case .maxText: return 960
        case .balanced: return 1024
        case .wide: return 1280
        }
    }

    /// 縦長モード用のポイント解像度（実ピクセルはこの2倍）
    var portraitPointSize: CGSize {
        switch self {
        case .maxText: return CGSize(width: 600, height: 960)
        case .balanced: return CGSize(width: 640, height: 1024)
        case .wide: return CGSize(width: 800, height: 1280)
        }
    }
}

enum DisplayManagerError: LocalizedError {
    case modeListUnavailable
    case noSuitableMode
    case switchFailed(CGError)
    case verificationFailed
    case noSavedMode
    case virtualDisplayFailed
    case virtualDisplayTimeout
    case mirrorFailed(CGError)

    var errorDescription: String? {
        switch self {
        case .modeListUnavailable: return "ディスプレイモード一覧を取得できません"
        case .noSuitableMode: return "適合するディスプレイモードが見つかりません"
        case .switchFailed(let err): return "解像度の切替に失敗しました (CGError \(err.rawValue))"
        case .verificationFailed: return "切替後の状態確認に失敗したため、元に戻しました"
        case .noSavedMode: return "復元する元のモードが保存されていません"
        case .virtualDisplayFailed: return "縦長仮想ディスプレイを作成できません"
        case .virtualDisplayTimeout: return "縦長仮想ディスプレイがオンラインになりません"
        case .mirrorFailed(let err): return "ミラーリング設定に失敗しました (CGError \(err.rawValue))"
        }
    }
}

final class DisplayManager {
    static let shared = DisplayManager()

    private let defaults = UserDefaults.standard
    private let originalKey = "originalDisplayMode"

    /// 内蔵ディスプレイの ID。縦長モード中はミラーの主画面が仮想ディスプレイに
    /// なるため、CGMainDisplayID ではなく内蔵を明示的に探す。
    private var displayID: CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetOnlineDisplayList(16, &ids, &count)
        for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
            return id
        }
        return CGMainDisplayID()
    }

    // MARK: - 元モードの永続化（F-04）

    /// リモートモード中のみ非 nil。アプリ・Mac 再起動後も残る。
    private(set) var savedOriginal: DisplayModeInfo? {
        get {
            defaults.data(forKey: originalKey)
                .flatMap { try? JSONDecoder().decode(DisplayModeInfo.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: originalKey)
            } else {
                defaults.removeObject(forKey: originalKey)
            }
        }
    }

    var isRemoteMode: Bool { savedOriginal != nil }

    // MARK: - モード取得

    func currentMode() -> DisplayModeInfo? {
        CGDisplayCopyDisplayMode(displayID).map(DisplayModeInfo.init)
    }

    private func rawModes(of id: CGDirectDisplayID? = nil) throws -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id ?? displayID, options) as? [CGDisplayMode] else {
            throw DisplayManagerError.modeListUnavailable
        }
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    /// プリセットの目標幅に最も近い HiDPI モードを返す
    func remoteMode(for preset: RemotePreset) throws -> CGDisplayMode {
        let hidpi = try rawModes().filter { $0.pixelWidth > $0.width }
        guard let best = hidpi.min(by: {
            abs($0.width - preset.targetWidth) < abs($1.width - preset.targetWidth)
        }) else {
            throw DisplayManagerError.noSuitableMode
        }
        return best
    }

    // MARK: - 切替（F-01, F-05）

    func enterRemoteMode(preset: RemotePreset) throws {
        let target = try remoteMode(for: preset)
        let before = currentMode()
        let wasRemote = isRemoteMode

        // 元モードは最初のリモートモード入りでのみ記録する
        // （リモートモード中のプリセット変更では上書きしない）
        if !wasRemote {
            savedOriginal = before
        }

        do {
            try setModeVerified(target)
        } catch {
            // 失敗時: 直前のモードへ戻し、初回だった場合は保存も破棄（F-05）
            if let before, let rollback = try? cgMode(matching: before) {
                _ = CGDisplaySetDisplayMode(displayID, rollback, nil)
            }
            if !wasRemote {
                savedOriginal = nil
            }
            throw error
        }
    }

    // MARK: - 縦長モード（F-22: 仮想ディスプレイ + ミラーリング）

    /// 生存している間だけ仮想ディスプレイが存在する。
    /// アプリが（クラッシュ含め）終了すると仮想ディスプレイは自動消滅し、
    /// macOS がミラーを解除して元の構成に戻るため、詰み状態にはならない。
    private var virtualDisplay: PCTVirtualDisplay?

    var isPortraitMode: Bool { virtualDisplay != nil }

    func enterPortraitMode(preset: RemotePreset) throws {
        // 横長リモートモード中なら先に解像度を戻す
        if isRemoteMode {
            try restoreOriginal()
        }
        if isPortraitMode {
            try setPortraitPreset(preset)
            return
        }

        let pixelModes = RemotePreset.allCases.map {
            NSValue(size: NSSize(width: $0.portraitPointSize.width * 2,
                                 height: $0.portraitPointSize.height * 2))
        }
        guard let vd = PCTVirtualDisplay(name: "RemoteLens 縦長ディスプレイ", pixelModes: pixelModes) else {
            throw DisplayManagerError.virtualDisplayFailed
        }
        NSLog("RemoteLens: 仮想ディスプレイ作成 displayID=%u", vd.displayID)
        try waitUntilOnline(vd.displayID)
        virtualDisplay = vd

        do {
            try applyPortraitMode(on: vd.displayID, preset: preset)
            // 内蔵を仮想（縦長）のミラーにする。主画面が縦長になり、
            // 内蔵パネルには縦長デスクトップがレターボックス表示される
            try setMirror(of: displayID, to: vd.displayID)
        } catch {
            virtualDisplay = nil  // 破棄すれば構成は自動で元に戻る
            throw error
        }
    }

    func exitPortraitMode() throws {
        guard let vd = virtualDisplay else { return }
        try setMirror(of: displayID, to: kCGNullDirectDisplay)
        _ = vd  // ミラー解除後に破棄
        virtualDisplay = nil
    }

    func setPortraitPreset(_ preset: RemotePreset) throws {
        guard let vd = virtualDisplay else { return }
        try applyPortraitMode(on: vd.displayID, preset: preset)
    }

    private func applyPortraitMode(on id: CGDirectDisplayID, preset: RemotePreset) throws {
        // 仮想ディスプレイは指定モード以外の派生モードも公開するため、
        // 目標幅への近さを最優先し、同率なら HiDPI を選ぶ
        let portrait = try rawModes(of: id).filter { $0.height > $0.width }
        let target = Int(preset.portraitPointSize.width)
        guard let best = portrait.min(by: {
            let d0 = abs($0.width - target)
            let d1 = abs($1.width - target)
            if d0 != d1 { return d0 < d1 }
            return ($0.pixelWidth > $0.width) && !($1.pixelWidth > $1.width)
        }) else {
            throw DisplayManagerError.noSuitableMode
        }
        let err = CGDisplaySetDisplayMode(id, best, nil)
        guard err == .success else {
            throw DisplayManagerError.switchFailed(err)
        }
    }

    private func waitUntilOnline(_ id: CGDirectDisplayID, timeout: TimeInterval = 5.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var count: UInt32 = 0
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            CGGetOnlineDisplayList(16, &ids, &count)
            if ids.prefix(Int(count)).contains(id) {
                NSLog("RemoteLens: 仮想ディスプレイ %u がオンラインになりました", id)
                return
            }
            // メニューアクション直後はメニューの後片付けや WindowServer の
            // ディスプレイ再構成処理がメインスレッドに乗るため、
            // Thread.sleep でブロックせず RunLoop を回して待つ
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        NSLog("RemoteLens: 仮想ディスプレイ %u がオンラインになりません(timeout)", id)
        throw DisplayManagerError.virtualDisplayTimeout
    }

    private func setMirror(of display: CGDirectDisplayID, to master: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw DisplayManagerError.mirrorFailed(.failure)
        }
        let err = CGConfigureDisplayMirrorOfDisplay(config, display, master)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayManagerError.mirrorFailed(err)
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else {
            throw DisplayManagerError.mirrorFailed(complete)
        }
    }

    // MARK: - 復元（F-02）

    func restoreOriginal() throws {
        guard let original = savedOriginal else {
            throw DisplayManagerError.noSavedMode
        }
        let mode = try cgMode(matching: original)
        try setModeVerified(mode)
        savedOriginal = nil
    }

    // MARK: - 内部処理

    private func setModeVerified(_ mode: CGDisplayMode) throws {
        let err = CGDisplaySetDisplayMode(displayID, mode, nil)
        guard err == .success else {
            throw DisplayManagerError.switchFailed(err)
        }
        // 切替後の実状態を確認する
        guard let now = currentMode(),
              now.width == mode.width, now.height == mode.height,
              now.pixelWidth == mode.pixelWidth else {
            throw DisplayManagerError.verificationFailed
        }
    }

    /// 保存済みスナップショットに合致する CGDisplayMode を探す。
    /// 完全一致 → ioModeID 一致 → サイズ一致 の順でフォールバック。
    private func cgMode(matching info: DisplayModeInfo) throws -> CGDisplayMode {
        let modes = try rawModes()
        if let exact = modes.first(where: { DisplayModeInfo(mode: $0) == info }) {
            return exact
        }
        if let byID = modes.first(where: { $0.ioDisplayModeID == info.ioModeID }) {
            return byID
        }
        if let bySize = modes.first(where: {
            $0.width == info.width && $0.height == info.height && $0.pixelWidth == info.pixelWidth
        }) {
            return bySize
        }
        throw DisplayManagerError.noSuitableMode
    }
}
