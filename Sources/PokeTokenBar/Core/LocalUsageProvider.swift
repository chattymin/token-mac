import Foundation

/// 로컬 로그 직접 파싱 기반 Claude provider (ccusage 대체).
struct LocalClaudeProvider: UsageProvider {
    let id = "claude_code"
    let displayName = "Claude Code"

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.claudeEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: CcusageProvider.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        // 월 범위 한 번 스캔으로 블록·주·월을 모두 도출.
        let entries = await LocalUsageCache.shared.claudeEntries(modifiedSince: monthStart)
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        r.weekTotal = LocalUsageReader.period(
            entries: entries, periodKey: fmt.string(from: weekStart),
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        r.monthTotal = LocalUsageReader.period(
            entries: entries, periodKey: LocalUsageReader.monthKey(now),
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.periodsOK = true
        return r
    }
}

/// 로컬 로그 직접 파싱 기반 Codex provider. (블록 없음, 주간 = 일별 합산)
struct LocalCodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"

    // Codex 사용은 구독제라 ccusage codex 가 비용을 $0 로 보고 → 동일하게 비용 0.
    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.codexEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        guard let d = LocalUsageReader.daily(entries: entries, localDay: CcusageProvider.todayKey()) else { return nil }
        return DailyUsage(date: d.date, inputTokens: d.inputTokens, outputTokens: d.outputTokens,
                          cacheCreationTokens: d.cacheCreationTokens, cacheReadTokens: d.cacheReadTokens,
                          totalTokens: d.totalTokens, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalUsageCache.shared.codexEntries(modifiedSince: monthStart)
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        let weekStart = LocalUsageReader.startOfWeek(now)
        let week = LocalUsageReader.period(entries: entries, periodKey: fmt.string(from: weekStart),
                                           fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        let month = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.weekTotal = PeriodUsage(period: week.period, totalTokens: week.totalTokens, totalCost: 0)
        r.monthTotal = PeriodUsage(period: month.period, totalTokens: month.totalTokens, totalCost: 0)
        r.periodsOK = true
        return r
    }
}
