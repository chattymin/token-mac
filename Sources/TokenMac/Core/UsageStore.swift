import AppKit
import Foundation
import Observation
import UserNotifications

/// burn rate 단계 — companion 표시 상태(작업/집중) 판정에 사용.
enum BurnTier: Sendable {
    case idle, normal, fast, blazing
}

@MainActor
@Observable
final class UsageStore {
    // MARK: 상태

    private(set) var snapshots: [ProviderSnapshot] = []
    private(set) var limits: LimitStatus?
    private(set) var codexLimits: CodexRateLimitStatus?
    private(set) var limitsAvailable = true
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var isRefreshingLimitToken = false
    private(set) var lastErrorDescription: String?
    private(set) var limitTokenRefreshError: String?

    // MARK: 설정 (UserDefaults)

    /// 0 = manual
    var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            reschedule()
        }
    }
    var warnThreshold: Double {
        didSet { UserDefaults.standard.set(warnThreshold, forKey: "warnThreshold") }
    }
    var critThreshold: Double {
        didSet { UserDefaults.standard.set(critThreshold, forKey: "critThreshold") }
    }
    // 메뉴바 표시 항목 (복수 선택 가능)
    var showTokensInMenu: Bool {
        didSet { UserDefaults.standard.set(showTokensInMenu, forKey: "showTokensInMenu") }
    }
    var showCostInMenu: Bool {
        didSet { UserDefaults.standard.set(showCostInMenu, forKey: "showCostInMenu") }
    }
    var showLimitInMenu: Bool {
        didSet { UserDefaults.standard.set(showLimitInMenu, forKey: "showLimitInMenu") }
    }
    var disableKeychainAccess: Bool {
        didSet {
            KeychainAccessGate.isDisabled = disableKeychainAccess
            if disableKeychainAccess {
                limits = nil
                limitsAvailable = false
            } else {
                Task { await refresh() }
            }
        }
    }

    static let intervalPresets: [(label: String, value: TimeInterval)] = [
        ("수동", 0), ("1분", 60), ("2분", 120), ("5분", 300), ("15분", 900),
    ]

    /// 앱 언어 미러(알림 현지화용). 단일 소스는 CompanionStore.language —
    /// 설정 변경/기동 시 동기화한다.
    var localizationLanguage: AppLanguage = .ko

    private let providers: [any UsageProvider]
    private let limitsProvider = OAuthLimitsProvider()
    private let codexLimitsProvider = CodexRateLimitsProvider()
    private var timer: Timer?
    private var emptyUsageRetryTask: Task<Void, Never>?
    /// 같은 한도 블록(resets_at 기준)에 대해 알림 1회만 발화
    private var notifiedKeys: Set<String> = []

    // MARK: 파생값

    var todayTotalTokens: Int {
        // 날짜 가드: 스냅샷의 일자가 현재 로컬 날짜와 다르면 (자정 직후 등) 합계에서 제외
        let todayKey = CcusageProvider.todayKey()
        return snapshots.reduce(0) { $0 + ($1.today?.date == todayKey ? $1.todayTotalTokens : 0) }
    }

    var hasAnyLimits: Bool {
        limits != nil || codexLimits?.hasVisibleLimit == true
    }

    /// 사용량 데이터(스냅샷)가 하나라도 있는가 — companion sleep 판정용
    var hasUsageData: Bool { !snapshots.isEmpty }

    var menuTitle: String {
        guard lastUpdated != nil else { return "—" }
        var parts: [String] = []
        if showTokensInMenu { parts.append(TokenFormatter.compact(todayTotalTokens)) }
        if showCostInMenu { parts.append(TokenFormatter.costCompact(todayCostTotal)) }
        if showLimitInMenu {
            if let utilization = limits?.fiveHour?.utilization {
                parts.append("Claude \(TokenFormatter.percent(utilization))")
            }
            if let usedPercent = codexLimits?.codex.primary?.usedPercent {
                parts.append("Codex \(TokenFormatter.percent(Double(usedPercent)))")
            }
        }
        return parts.joined(separator: " · ")   // 전부 끄면 아이콘만
    }

    var todayCostTotal: Double {
        let todayKey = CcusageProvider.todayKey()
        return snapshots.reduce(0) { $0 + ($1.today?.date == todayKey ? ($1.today?.totalCost ?? 0) : 0) }
    }

    var weekTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.weekTotal?.totalTokens ?? 0) } }
    var weekCostTotal: Double { snapshots.reduce(0) { $0 + ($1.weekTotal?.totalCost ?? 0) } }
    var monthTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.monthTotal?.totalTokens ?? 0) } }
    var monthCostTotal: Double { snapshots.reduce(0) { $0 + ($1.monthTotal?.totalCost ?? 0) } }

    private var claudeActiveBlock: BlockUsage? {
        snapshots.first { $0.activeBlock != nil }?.activeBlock
    }

    // MARK: 한도 소진 예측

    struct FiveHourForecast {
        var depletionDate: Date
        var beforeReset: Bool
    }

    var fiveHourForecast: FiveHourForecast? {
        guard let window = limits?.fiveHour, let utilization = window.utilization,
              let reset = window.resetDate else { return nil }
        if utilization >= 100 { return FiveHourForecast(depletionDate: Date(), beforeReset: true) }
        guard let block = claudeActiveBlock, let burn = block.tokensPerMinute,
              let depletion = Self.forecastDepletion(
                  blockTokens: block.totalTokens, tokensPerMinute: burn,
                  utilization: utilization, now: Date())
        else { return nil }
        return FiveHourForecast(depletionDate: depletion, beforeReset: depletion < reset)
    }

    /// 5h 한도의 토큰량을 (현재 블록 토큰 ÷ 공식 utilization%) 로 추정하고 100% 도달 시각을 외삽.
    /// utilization 5% 미만이거나 burn 1만 토큰/분 미만이면 추정이 불안정해 nil.
    nonisolated static func forecastDepletion(
        blockTokens: Int, tokensPerMinute: Double, utilization: Double, now: Date
    ) -> Date? {
        guard utilization >= 5, utilization < 100, blockTokens > 0,
              tokensPerMinute >= 10_000 else { return nil }
        let tokensPerPercent = Double(blockTokens) / utilization
        let minutesLeft = (100 - utilization) * tokensPerPercent / tokensPerMinute
        guard minutesLeft.isFinite, minutesLeft < 60 * 24 else { return nil }
        return now.addingTimeInterval(minutesLeft * 60)
    }

    /// 메뉴바 경고 상태 — 임계 초과 또는 리셋 전 한도 도달 예측
    var isLimitWarning: Bool {
        if let utilization = limits?.fiveHour?.utilization, utilization >= critThreshold { return true }
        if let utilization = codexLimits?.codex.primary?.usedPercent,
           Double(utilization) >= critThreshold { return true }
        if let utilization = codexLimits?.codex.secondary?.usedPercent,
           Double(utilization) >= critThreshold { return true }
        if let utilization = codexLimits?.codex.individualLimit?.usedPercent,
           Double(utilization) >= critThreshold { return true }
        if let forecast = fiveHourForecast, forecast.beforeReset { return true }
        return false
    }

    /// burn rate 티어 — companion 표시 상태(idle/working/focus) 판정에 사용.
    var burnTier: BurnTier {
        guard let burn = claudeActiveBlock?.tokensPerMinute, burn > 1_000 else { return .idle }
        if burn < 100_000 { return .normal }
        if burn < 400_000 { return .fast }
        return .blazing
    }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        let allowance = refreshInterval > 0 ? refreshInterval * 2 : 1800
        return Date().timeIntervalSince(lastUpdated) > allowance
    }

    // MARK: 생명주기

    init(providers: [any UsageProvider] = [CcusageProvider.claude, CcusageProvider.codex]) {
        self.providers = providers
        let d = UserDefaults.standard
        refreshInterval = d.object(forKey: "refreshInterval") as? TimeInterval ?? 120
        warnThreshold = d.object(forKey: "warnThreshold") as? Double ?? 80
        critThreshold = d.object(forKey: "critThreshold") as? Double ?? 95
        showTokensInMenu = d.object(forKey: "showTokensInMenu") as? Bool ?? true
        showCostInMenu = d.object(forKey: "showCostInMenu") as? Bool ?? false
        showLimitInMenu = d.object(forKey: "showLimitInMenu") as? Bool ?? false
        disableKeychainAccess = d.object(forKey: "disableKeychainAccess") as? Bool ?? false

        reschedule()

        // 자정 경계: 날짜가 바뀌면 "오늘" 버킷 즉시 갱신
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // 슬립 복귀 시 즉시 갱신
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        requestNotificationAuthorization()
        Task { await refresh() }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard refreshInterval > 0 else { return }
        let t = Timer(timeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        t.tolerance = refreshInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: 갱신

    func refresh(scheduleEmptyRetry: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        // App Nap 방지 — 백그라운드 스로틀로 ccusage 가 타임아웃되는 것을 막는다 (시스템 슬립은 허용)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "TokenMac usage refresh")
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            isRefreshing = false
        }

        let todayKey = CcusageProvider.todayKey()

        // ── Phase 1: daily (critical) — 메뉴바 숫자와 stale 판정은 여기서 확정.
        // 블록/주월 상세가 느리거나 멈춰도 메뉴바 숫자는 영향받지 않는다.
        var dailyByID: [String: DailyUsage] = [:]
        var failedIDs: Set<String> = []
        var errors: [String] = []

        // NOTE: (String, Result<DailyUsage?, any Error>) 튜플을 child task 결과로 쓰면
        // release 빌드에서 for-await 가 0건을 수신하는 문제가 있어, 평탄한 Sendable 구조체로 반환한다.
        struct DailyOutcome: Sendable {
            let id: String
            let today: DailyUsage?
            let errorDescription: String?
        }
        await withTaskGroup(of: DailyOutcome.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let today = try await provider.fetchDaily()
                        return DailyOutcome(id: provider.id, today: today, errorDescription: nil)
                    } catch {
                        return DailyOutcome(id: provider.id, today: nil, errorDescription: "\(error)")
                    }
                }
            }
            for await outcome in group {
                AppLog.write("phase1 recv id=\(outcome.id) today=\(outcome.today?.totalTokens.description ?? "nil") err=\(outcome.errorDescription ?? "none")")
                if let today = outcome.today { dailyByID[outcome.id] = today }
                if let err = outcome.errorDescription {
                    failedIDs.insert(outcome.id)
                    errors.append("\(outcome.id): \(err)")
                }
            }
        }

        var newSnapshots: [ProviderSnapshot] = []
        for provider in providers {
            // 날짜 가드: 이전 스냅샷의 어제 데이터는 유지하지 않는다 (자정 동결 방지)
            var prevToday: DailyUsage?
            var prevBlock: BlockUsage?
            if let previous = snapshots.first(where: { $0.providerID == provider.id }) {
                if previous.today?.date == todayKey { prevToday = previous.today }
                prevBlock = previous.activeBlock
            }

            let today: DailyUsage?
            if let fetched = dailyByID[provider.id] {
                today = fetched
            } else if failedIDs.contains(provider.id) {
                today = prevToday   // 실패 → 오늘자 이전 값 유지
            } else {
                today = nil         // 성공했지만 오늘 데이터 없음 (예: Codex 미사용)
            }

            if today != nil {
                newSnapshots.append(ProviderSnapshot(
                    providerID: provider.id,
                    displayName: provider.displayName,
                    today: today,
                    activeBlock: prevBlock,
                    fetchedAt: Date()))
            }
        }
        snapshots = newSnapshots

        if errors.isEmpty {
            lastUpdated = Date()
            lastErrorDescription = nil
        } else {
            lastErrorDescription = errors.joined(separator: " / ")
            if lastUpdated == nil && !snapshots.isEmpty { lastUpdated = Date() }
        }
        writeParitySnapshot()
        AppLog.write("phase1 done total=\(todayTotalTokens) errors=\(errors.isEmpty ? "none" : errors.joined(separator: " | "))")
        handleEmptyUsageRetry(schedule: scheduleEmptyRetry, hasErrors: !errors.isEmpty)

        // ── Phase 2: 블록/주월 누적 상세 (best effort) — 실패 시 이전 값 유지
        await withTaskGroup(of: (String, ProviderEnrichment).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.fetchEnrichment()) }
            }
            for await (id, enrichment) in group {
                guard let index = snapshots.firstIndex(where: { $0.providerID == id }) else { continue }
                if enrichment.blocksOK { snapshots[index].activeBlock = enrichment.activeBlock }
                if enrichment.periodsOK {
                    snapshots[index].weekTotal = enrichment.weekTotal
                    snapshots[index].monthTotal = enrichment.monthTotal
                }
            }
        }

        // ── 한도 조회 (Keychain 프롬프트로 블로킹될 수 있어 마지막)
        if disableKeychainAccess {
            limits = nil
            limitsAvailable = false
            AppLog.write("claude limits skipped: keychain access disabled")
        } else {
            do {
                limits = try await limitsProvider.fetch(allowKeychainPrompt: false)
                limitsAvailable = true
                AppLog.write("limits refreshed fiveHour=\(limits?.fiveHour?.utilization?.description ?? "nil") sevenDay=\(limits?.sevenDay?.utilization?.description ?? "nil")")
            } catch {
                // 비공식 endpoint 실패 → 섹션 숨김, 토큰 표시는 무영향
                if limits == nil { limitsAvailable = false }
                AppLog.write("limits unavailable: \(error)")
            }
        }
        await refreshCodexLimits()

        checkLimitNotifications()
        writeParitySnapshot()
        let summary = snapshots.map { "\($0.providerID):\($0.today?.date ?? "nil")=\($0.todayTotalTokens)" }
            .joined(separator: ", ")
        AppLog.write("refresh done [\(summary)]")
    }

    private func handleEmptyUsageRetry(schedule: Bool, hasErrors: Bool) {
        emptyUsageRetryTask?.cancel()
        emptyUsageRetryTask = nil
        guard schedule, !hasErrors, snapshots.isEmpty else { return }

        AppLog.write("empty usage retry scheduled")
        emptyUsageRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            self?.emptyUsageRetryTask = nil
            await self?.refresh(scheduleEmptyRetry: false)
        }
    }

    func refreshLimitTokenFromKeychain() async {
        guard !isRefreshingLimitToken else { return }
        isRefreshingLimitToken = true
        defer { isRefreshingLimitToken = false }

        do {
            limits = try await limitsProvider.fetch(allowKeychainPrompt: true)
            limitsAvailable = true
            limitTokenRefreshError = nil
            AppLog.write("limits refreshed by user action fiveHour=\(limits?.fiveHour?.utilization?.description ?? "nil") sevenDay=\(limits?.sevenDay?.utilization?.description ?? "nil")")
            AppLog.write("limits refreshed from keychain by user action")
        } catch {
            limitTokenRefreshError = "\(error)"
            if limits == nil { limitsAvailable = false }
            AppLog.write("limits user refresh failed: \(error)")
        }
    }

    private func refreshCodexLimits() async {
        do {
            codexLimits = try await codexLimitsProvider.fetch()
            if let codex = codexLimits?.codex {
                AppLog.write("codex limits refreshed primary=\(codex.primary?.usedPercent.description ?? "nil") secondary=\(codex.secondary?.usedPercent.description ?? "nil") plan=\(codex.planType ?? "nil")")
            } else {
                AppLog.write("codex limits skipped: codex binary not found")
            }
        } catch {
            AppLog.write("codex limits unavailable: \(error)")
        }
    }

    // MARK: 한도 알림 (ClaudeBar 임계값 패턴)

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkLimitNotifications() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let l = L(localizationLanguage)
        var windows: [(name: String, utilization: Double, resetKey: String)] = []
        if let limits {
            if let utilization = limits.fiveHour?.utilization {
                windows.append((
                    l.claudeFiveHour,
                    utilization,
                    limits.fiveHour?.resetsAt ?? "none"))
            }
            if let utilization = limits.sevenDay?.utilization {
                windows.append((
                    l.claudeWeekly,
                    utilization,
                    limits.sevenDay?.resetsAt ?? "none"))
            }
        }
        if let codex = codexLimits?.codex {
            if let primary = codex.primary {
                windows.append((
                    "Codex \(l.codexWindow(primary.windowDurationMins))",
                    Double(primary.usedPercent),
                    primary.resetsAt.map(String.init) ?? "none"))
            }
            if let secondary = codex.secondary {
                windows.append((
                    "Codex \(l.codexWindow(secondary.windowDurationMins))",
                    Double(secondary.usedPercent),
                    secondary.resetsAt.map(String.init) ?? "none"))
            }
            if let individual = codex.individualLimit {
                windows.append((
                    l.codexPersonalLimit,
                    Double(individual.usedPercent),
                    String(individual.resetsAt)))
            }
        }
        for (name, utilization, resetKey) in windows {
            for (level, threshold) in [("critical", critThreshold), ("warning", warnThreshold)] {
                guard utilization >= threshold else { continue }
                let key = "\(name)-\(resetKey)-\(level)"
                guard !notifiedKeys.contains(key) else { break }
                notifiedKeys.insert(key)
                let content = UNMutableNotificationContent()
                content.title = level == "critical" ? l.notifCritical : l.notifWarning
                content.body = l.notifBody(name, TokenFormatter.percent(utilization))
                content.sound = level == "critical" ? .default : nil
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: key, content: content, trigger: nil))
                break // 같은 윈도우에 critical 발화 시 warning 은 생략
            }
        }
        if notifiedKeys.count > 64 { notifiedKeys.removeAll() }
    }

    // MARK: parity-check.sh 용 스냅샷 파일

    private func writeParitySnapshot() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var providerEntries: [[String: Any]] = []
        for snapshot in snapshots {
            providerEntries.append([
                "id": snapshot.providerID,
                "date": snapshot.today?.date ?? "",
                "totalTokens": snapshot.todayTotalTokens,
            ])
        }
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "todayTotalTokens": todayTotalTokens,
            "menuTitle": menuTitle,
            "providers": providerEntries,
            "lastError": lastErrorDescription ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("last-snapshot.json"))
        }
    }
}
