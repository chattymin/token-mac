import AppKit
import SwiftUI

@main
struct TokenMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바는 AppDelegate 의 NSStatusItem 이 담당.
        // MenuBarExtra 라벨은 고빈도 갱신 시 재렌더링 폭주로 CPU/메모리 문제가 있어 사용하지 않는다.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: UsageStore!
    private var companion: CompanionStore!
    private var companionTimer: Timer?
    private var menuSprite: NSImage?
    private var menuSpriteID: Int?
    private var companionBobUp = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = UsageStore()
        companion = CompanionStore()
        store.localizationLanguage = companion.language   // 알림 현지화용 미러 시드

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.eggImage(up: false)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environment(store).environment(companion))
        popover.behavior = .transient

        observeStore()
        applyState()
    }

    /// Observation 기반 상태 반영 — store 의 menuTitle/isStale 변경 시 재호출
    private func observeStore() {
        withObservationTracking {
            _ = store.menuTitle
            _ = store.isStale
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

        updateCompanion()

        // 메뉴바는 항상 캐릭터(스프라이트/알) — 프레임 타이머로 가벼운 bob 애니메이션.
        if companionTimer == nil {
            renderCompanionFrame()
            let t = Timer(timeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.renderCompanionFrame() }
            }
            RunLoop.main.add(t, forMode: .common)
            companionTimer = t
        }
    }

    /// UsageStore 값 → CompanionStore (사용량 적립 + 표시 상태). 매 관찰 변경 시 호출.
    private func updateCompanion() {
        companion.update(
            todayTokens: store.todayTotalTokens,
            todayDate: CcusageProvider.todayKey(),
            monthTotal: store.monthTotalTokens,
            burnTier: store.burnTier,
            limitWarning: store.isLimitWarning,
            hasUsageData: store.hasUsageData)
    }

    /// 메뉴바: 현재 포켓몬 스프라이트 + 가벼운 상하 bob. 알/로딩 중엔 알 글리프 폴백.
    private func renderCompanionFrame() {
        let id = companion.currentSpeciesID
        if id != menuSpriteID {
            menuSpriteID = id
            menuSprite = nil
            if let id {
                Task { @MainActor [weak self] in
                    self?.menuSprite = await SpriteLoader.image(speciesID: id, animated: false)
                }
            }
        }
        companionBobUp.toggle()
        if let sprite = menuSprite {
            statusItem.button?.image = Self.menuBarImage(from: sprite, up: companionBobUp)
        } else {
            statusItem.button?.image = Self.eggImage(up: companionBobUp)
        }
    }

    private static func menuBarImage(from sprite: NSImage, up: Bool) -> NSImage {
        let h: CGFloat = 22
        let img = NSImage(size: NSSize(width: h, height: h))
        img.lockFocus()
        let off: CGFloat = up ? 1 : 0
        sprite.draw(in: NSRect(x: 1, y: off, width: h - 2, height: h - 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        return img
    }

    /// 스프라이트가 아직 없을 때(부화 전/로딩 중) 메뉴바에 표시하는 알 글리프.
    private static func eggImage(up: Bool) -> NSImage {
        let h: CGFloat = 22
        let img = NSImage(size: NSSize(width: h, height: h))
        img.lockFocus()
        let off: CGFloat = up ? 1 : 0
        let s = "🥚" as NSString
        s.draw(in: NSRect(x: 2, y: off, width: h - 2, height: h - 2),
               withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
        img.unlockFocus()
        return img
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
