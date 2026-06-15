import AppKit
import SwiftUI

@main
struct TokenMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바는 AppDelegate 의 NSStatusItem 이 담당.
        // MenuBarExtra 라벨은 고빈도 갱신(코인 스핀) 시 재렌더링 폭주로 CPU/메모리 문제가
        // 있어 사용하지 않는다.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: UsageStore!
    private var spinIndex = 0
    private var spinTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = UsageStore()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarCoin.staticImage()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environment(store))
        popover.behavior = .transient

        observeStore()
        applyState()
    }

    /// Observation 기반 상태 반영 — store 의 menuTitle/isStale/spinEnabled 변경 시 재호출
    private func observeStore() {
        withObservationTracking {
            _ = store.menuTitle
            _ = store.isStale
            _ = store.spinEnabled
            _ = store.isLimitWarning
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyState()
                self.observeStore()
            }
        }
    }

    private func applyState() {
        guard let button = statusItem.button else { return }
        let title = store.menuTitle
        button.title = title.isEmpty ? "" : " " + title
        button.appearsDisabled = store.isStale

        if store.spinEnabled {
            if spinTimer == nil { advanceSpin() }
        } else {
            spinTimer?.invalidate()
            spinTimer = nil
            spinIndex = 0
            button.image = MenuBarCoin.staticImage(warning: store.isLimitWarning)
        }
    }

    /// 코인 스핀 — 프레임별 지속시간으로 이징 표현, 캐시된 NSImage 교체만 수행.
    /// burn rate 티어가 회전 속도와 프레임 시퀀스를 결정 (빠를수록 프레임 드랍 — swaps/s 상한).
    /// 한도 경고 시 레드 팔레트 프레임 사용.
    private func advanceSpin() {
        guard store.spinEnabled else { return }
        let sequence = MenuBarCoin.sequence(for: store.spinTier)
        let frame = sequence[spinIndex % sequence.count]
        statusItem.button?.image = MenuBarCoin.image(for: frame.kind, warning: store.isLimitWarning)
        spinTimer = Timer.scheduledTimer(withTimeInterval: frame.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.spinIndex = (self.spinIndex + 1) % sequence.count
                self.advanceSpin()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // LSUIElement 앱이 비활성이면 팝오버 내부 버튼 클릭이 무시됨 — show 전에 활성화 보장
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }
}
