import AppKit
import SwiftUI

/// 縦長モード中の脱出手段。
/// 縦長モードではミラーの表示のされ方によっては Mac 本体でメニューバーが
/// 見えなくなることがあり、メニューバーだけが復元手段だと詰む。
/// そのため切替直後に確認パネルを出し、一定時間内に「このまま使う」が
/// 押されなければ自動で元に戻す。維持後も小さな「戻す」ボタンを残す。
@MainActor
final class RescueModel: ObservableObject {
    enum Phase {
        case countdown(Int)
        case minimal
    }
    @Published var phase: Phase = .countdown(30)
}

@MainActor
final class RescuePanel {
    var onRestore: (() -> Void)?

    private var panel: NSPanel?
    private var timer: Timer?
    private let model = RescueModel()

    func showCountdown(seconds: Int = 30) {
        model.phase = .countdown(seconds)
        presentPanel()
        layout(center: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func tick() {
        guard case .countdown(let remaining) = model.phase else { return }
        if remaining <= 1 {
            timer?.invalidate()
            onRestore?()  // タイムアウト: 自動で元に戻す
        } else {
            model.phase = .countdown(remaining - 1)
        }
    }

    private func keep() {
        timer?.invalidate()
        model.phase = .minimal
        layout(center: false)
    }

    private func presentPanel() {
        guard panel == nil else { return }
        let p = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.contentViewController = NSHostingController(rootView: RescueView(
            model: model,
            onRestore: { [weak self] in self?.onRestore?() },
            onKeep: { [weak self] in self?.keep() }
        ))
        panel = p
    }

    private func layout(center: Bool) {
        guard let panel else { return }
        if let hosting = panel.contentViewController?.view {
            panel.setContentSize(hosting.fittingSize)
        }
        if let screen = NSScreen.main {
            let origin: NSPoint
            if center {
                let f = screen.visibleFrame
                origin = NSPoint(x: f.midX - panel.frame.width / 2,
                                 y: f.midY - panel.frame.height / 2)
            } else {
                origin = minimalOrigin(on: screen, panelSize: panel.frame.size)
            }
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }

    /// 維持後の「戻す」ボタンの定位置: Dock の右側。
    /// Dock の正確な矩形は権限なしに取れないため、画面下部の
    /// Dock の帯（frame と visibleFrame の差分）の右端に置く。
    /// Dock は中央寄せなので、これが「Dock の右横」に相当する。
    private func minimalOrigin(on screen: NSScreen, panelSize: NSSize) -> NSPoint {
        let f = screen.frame
        let v = screen.visibleFrame
        let dockBandHeight = v.minY - f.minY
        if dockBandHeight > 20 {
            // Dock と同じ帯の右端に、上下中央で配置
            let y = f.minY + (dockBandHeight - panelSize.height) / 2
            return NSPoint(x: f.maxX - panelSize.width - 12,
                           y: max(f.minY + 4, y))
        }
        // Dock が下にない（左右配置・自動非表示）場合は右下に退避
        return NSPoint(x: v.maxX - panelSize.width - 24, y: v.minY + 24)
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct RescueView: View {
    @ObservedObject var model: RescueModel
    var onRestore: () -> Void
    var onKeep: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .countdown(let remaining):
                VStack(spacing: 14) {
                    Text("縦長モードに切り替えました")
                        .font(.headline)
                    Text("画面が正しく表示されていない場合は、そのまま何もしないでください。\n\(remaining) 秒後に自動で元に戻ります。")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                    HStack(spacing: 12) {
                        Button("今すぐ戻す") { onRestore() }
                        Button("このまま使う") { onKeep() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(width: 340)
            case .minimal:
                Button {
                    onRestore()
                } label: {
                    Label("通常モードに戻す", systemImage: "display")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .padding(10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}
