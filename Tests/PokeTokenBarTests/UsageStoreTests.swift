import XCTest
@testable import PokeTokenBar

// UsageStore 의 refresh 파이프라인 + 파생 표시값을 주입 스텁으로 결정적 검증.
// (실제 ccusage/Keychain/Codex 바이너리 없이 — 위협 모델: 1인 로컬, CI 없음)

// MARK: 스텁

private enum StubError: Error { case boom }

/// 호출 후에도 동작을 바꿀 수 있는 usage provider (실패 전환 테스트용). 단일 스레드 테스트 한정.
private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    nonisolated(unsafe) var daily: DailyUsage?
    nonisolated(unsafe) var enrichment = ProviderEnrichment()
    nonisolated(unsafe) var failDaily = false

    init(id: String, displayName: String, daily: DailyUsage? = nil) {
        self.id = id
        self.displayName = displayName
        self.daily = daily
    }
    func fetchDaily() async throws -> DailyUsage? {
        if failDaily { throw StubError.boom }
        return daily
    }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct FakeClaudeLimits: ClaudeLimitsProviding {
    var status: LimitStatus?
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

private struct FakeCodexLimits: CodexLimitsProviding {
    var status: CodexRateLimitStatus?
    func fetch() async throws -> CodexRateLimitStatus? { status }
}

// MARK: 픽스처 헬퍼

private func todayDaily(_ tokens: Int, cost: Double = 0) -> DailyUsage {
    DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0,
               cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: cost)
}

private func block(tokensPerMinute tpm: Double) -> BlockUsage {
    let json = "{\"blocks\":[{\"id\":\"b\",\"startTime\":\"\",\"endTime\":\"\",\"isActive\":true," +
               "\"totalTokens\":1000,\"costUSD\":1,\"burnRate\":{\"tokensPerMinute\":\(tpm)}}]}"
    return try! JSONDecoder().decode(BlocksReport.self, from: Data(json.utf8)).blocks[0]
}

private func claudeLimits(fiveHourUtil: Double, resetsAt: String? = nil) -> LimitStatus {
    let reset = resetsAt.map { "\"\($0)\"" } ?? "null"
    let json = "{\"five_hour\":{\"utilization\":\(fiveHourUtil),\"resets_at\":\(reset)}}"
    return try! JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
}

private func codexLimits(primaryUsed: Int? = nil, secondaryUsed: Int? = nil) -> CodexRateLimitStatus {
    func win(_ p: Int, _ mins: Int) -> String { "{\"usedPercent\":\(p),\"windowDurationMins\":\(mins)}" }
    var parts: [String] = []
    if let primaryUsed { parts.append("\"primary\":\(win(primaryUsed, 300))") }
    if let secondaryUsed { parts.append("\"secondary\":\(win(secondaryUsed, 10080))") }
    let json = "{\"rateLimits\":{\(parts.joined(separator: ","))}}"
    return try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(json.utf8))
}

// MARK: 테스트

@MainActor
final class UsageStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // 기본값으로 시작하도록 관련 UserDefaults 키 정리 (테스트 간 오염 방지)
        for key in ["refreshInterval", "warnThreshold", "critThreshold",
                    "showTokensInMenu", "showCostInMenu", "showLimitInMenu",
                    "limitNotifications", "companionNotifications", "disableKeychainAccess"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        KeychainAccessGate.isDisabled = false
    }

    private func makeStore(
        providers: [any UsageProvider],
        claude: LimitStatus? = nil,
        codex: CodexRateLimitStatus? = nil
    ) -> UsageStore {
        UsageStore(providers: providers,
                   claudeLimitsProvider: FakeClaudeLimits(status: claude),
                   codexLimitsProvider: FakeCodexLimits(status: codex),
                   autoRefresh: false)
    }

    // MARK: 집계

    func testAggregatesTodayTokensAcrossProviders() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(50_000_000))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 150_000_000)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertNil(store.lastErrorDescription)
    }

    func testCodexOnlyWhenClaudeHasNoData() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: nil) // 데이터 없음
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(50_000_000))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 50_000_000)
        XCTAssertTrue(store.hasUsageData)
        XCTAssertEqual(store.snapshots.count, 1)        // claude 는 today nil → 스냅샷 미생성
        XCTAssertEqual(store.snapshots.first?.providerID, "codex")
    }

    func testStaleDatedSnapshotExcludedFromTodayTotal() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        // 어제(다른 날짜) 데이터 — 날짜 가드로 오늘 합계에서 제외돼야 함
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex",
            daily: DailyUsage(date: "2000-01-01", inputTokens: 0, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 999, totalCost: 0))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)   // codex 999 제외
    }

    func testProviderFailureKeepsPreviousTodayValue() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let store = makeStore(providers: [claude])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)

        claude.failDaily = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)    // 실패 → 이전 값 유지
        XCTAssertNotNil(store.lastErrorDescription)            // 에러는 표면화
    }

    // MARK: 메뉴바 타이틀

    func testMenuTitleReflectsToggles() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000, cost: 12.5))
        let store = makeStore(providers: [claude])
        store.showTokensInMenu = true
        store.showCostInMenu = false
        store.showLimitInMenu = false
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "100M")

        store.showCostInMenu = true
        XCTAssertEqual(store.menuTitle, "100M · $12.5")
    }

    func testMenuTitleShowsLimitPercents() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude],
                              claude: claudeLimits(fiveHourUtil: 42),
                              codex: codexLimits(primaryUsed: 73))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "Claude 42% · Codex 73%")
    }

    // MARK: 한도 경고

    func testLimitWarningWhenClaudeOverCritical() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], claude: claudeLimits(fiveHourUtil: 96))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)
        XCTAssertTrue(store.hasAnyLimits)
    }

    func testNoLimitWarningWhenUnderCritical() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], claude: claudeLimits(fiveHourUtil: 50))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.isLimitWarning)
    }

    func testLimitWarningFromCodexSecondary() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], codex: codexLimits(primaryUsed: 10, secondaryUsed: 97))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)
    }

    func testLimitWarningFromForecastAtFullUtilization() async {
        // crit 을 100 초과로 올려 임계 분기를 끄고, util 100 → 예측 분기만으로 경고가 켜지는지 확인
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude],
                              claude: claudeLimits(fiveHourUtil: 100, resetsAt: "2099-01-01T00:00:00Z"))
        store.critThreshold = 101
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)   // fiveHourForecast(beforeReset:true)
    }

    // MARK: burn tier

    func testBurnTierThresholds() async {
        func tier(_ tpm: Double) async -> BurnTier {
            let p = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
            p.enrichment = ProviderEnrichment(activeBlock: block(tokensPerMinute: tpm), blocksOK: true,
                                              weekTotal: nil, monthTotal: nil, periodsOK: false)
            let store = makeStore(providers: [p])
            await store.refresh(scheduleEmptyRetry: false)
            return store.burnTier
        }
        let idle = await tier(500)         // <=1000 → idle
        let normal = await tier(50_000)    // <100k → normal
        let fast = await tier(200_000)     // <400k → fast
        let blazing = await tier(500_000)  // >=400k → blazing
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(normal, .normal)
        XCTAssertEqual(fast, .fast)
        XCTAssertEqual(blazing, .blazing)
    }

    // MARK: stale

    func testIsStaleBeforeFirstRefreshThenFreshAfter() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude])
        XCTAssertTrue(store.isStale)   // lastUpdated nil
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.isStale)
    }

    // MARK: 주/월 누적 유지 (팝오버 깜빡임 회귀 방지)

    /// phase1 재빌드가 이전 스냅샷의 주/월 누적을 이어받지 않으면, 다음 enrichment 가
    /// 다시 채우기 전까지 nil 이 되어 팝오버 "이번 주/이번 달" 행이 사라졌다 나타난다.
    /// enrichment 가 주월을 못 채우는(periodsOK=false) 갱신에서도 이전 값이 유지돼야 한다.
    func testWeekMonthPersistAcrossRefreshWhenEnrichmentSkips() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        claude.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: false,
            weekTotal: PeriodUsage(period: "2026-06-28", totalTokens: 7_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "2026-06", totalTokens: 30_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [claude])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.weekTotalTokens, 7_000)
        XCTAssertEqual(store.monthTotalTokens, 30_000)

        // 다음 갱신: enrichment 가 주월을 채우지 못함 → 이전 값이 살아있어야 한다.
        claude.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: false, weekTotal: nil, monthTotal: nil, periodsOK: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.weekTotalTokens, 7_000, "주 누적이 재빌드에서 사라지면 안 된다")
        XCTAssertEqual(store.monthTotalTokens, 30_000, "월 누적이 재빌드에서 사라지면 안 된다")
    }

    // MARK: friendlyLimitError 매핑

    func testFriendlyLimitErrorMapping() {
        let l = L(.en)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(401), l), l.limitRefreshHTTPError(401))
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(500), l), l.limitRefreshHTTPError(500))
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.credentialFormat, l), l.limitRefreshNoCredential)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.keychainInteractionNotAllowed, l), l.limitRefreshGeneric)
        XCTAssertEqual(UsageStore.friendlyLimitError(StubError.boom, l), l.limitRefreshGeneric)   // 비 LimitsError
    }
}
