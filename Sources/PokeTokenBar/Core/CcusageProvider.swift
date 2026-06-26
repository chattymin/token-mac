import Foundation

/// ccusage 바이너리 기반 수집. 바이너리 경로는 CcusageLocator 가 해석한다
/// (Homebrew 외 mise/nvm/asdf 등 버전매니저 설치도 셸 PATH 로 탐색).
struct CcusageProvider: UsageProvider {
    let id: String
    let displayName: String
    let commandPrefix: [String]
    let supportsBlocks: Bool
    let supportsWeekly: Bool
    let supportsMonthly: Bool

    static let claude = CcusageProvider(
        id: "claude_code",
        displayName: "Claude Code",
        commandPrefix: ["claude"],
        supportsBlocks: true,
        supportsWeekly: true,
        supportsMonthly: true
    )

    static let codex = CcusageProvider(
        id: "codex",
        displayName: "Codex",
        commandPrefix: ["codex"],
        supportsBlocks: false,
        supportsWeekly: false,
        supportsMonthly: true
    )

    var resolvedBinary: String? {
        BinaryLocator.resolve("ccusage", staticPaths: BinaryLocator.commonNodeToolPaths("ccusage"))
    }

    // MARK: critical path — 오늘 합계

    func fetchDaily() async throws -> DailyUsage? {
        guard let bin = resolvedBinary else { return nil }
        let since = Self.todayStamp()
        let todayKey = Self.todayKey()
        let dailyData: Data
        do {
            // --offline: 모델 가격을 네트워크 대신 번들 캐시에서 — totalTokens 무영향
            dailyData = try await ProcessRunner.runJSON(
                binary: bin, arguments: commandPrefix + ["daily", "--json", "--offline", "--since", since],
                timeout: 120)
        } catch {
            AppLog.write("\(id) daily FAILED bin=\(bin) since=\(since): \(error)")
            throw error
        }
        let daily = try JSONDecoder().decode(DailyReport.self, from: dailyData)
        let today = daily.daily.first { $0.date == todayKey }
        AppLog.write("\(id) daily ok since=\(since) entries=\(daily.daily.count) todayKey=\(todayKey) today=\(today?.totalTokens.description ?? "nil")")
        return today
    }

    // MARK: best effort — 블록/주월 누적 상세

    func fetchEnrichment() async -> ProviderEnrichment {
        guard let bin = resolvedBinary else { return ProviderEnrichment() }
        var result = ProviderEnrichment()

        if supportsBlocks {
            do {
                let data = try await ProcessRunner.runJSON(
                    binary: bin, arguments: commandPrefix + ["blocks", "--json", "--offline", "--active"],
                    timeout: 45)
                let report = try JSONDecoder().decode(BlocksReport.self, from: data)
                result.activeBlock = report.blocks.first { $0.isActive }
                result.blocksOK = true
            } catch {
                AppLog.write("\(id) blocks FAILED: \(error)")
            }
        }

        result.weekTotal = await fetchWeekTotal(binary: bin)
        result.monthTotal = await fetchMonthTotal(binary: bin)
        result.periodsOK = result.weekTotal != nil || result.monthTotal != nil
        return result
    }

    private func fetchWeekTotal(binary bin: String) async -> PeriodUsage? {
        if supportsWeekly {
            do {
                let data = try await ProcessRunner.runJSON(
                    binary: bin,
                    arguments: commandPrefix + ["weekly", "--json", "--offline", "--since", Self.daysAgoStamp(8)],
                    timeout: 45)
                return try JSONDecoder().decode(WeeklyReport.self, from: data).weekly.last
            } catch RunnerError.nonZeroExit(1, _) {
                return nil
            } catch {
                AppLog.write("\(id) weekly FAILED: \(error)")
                return nil
            }
        }

        do {
            let data = try await ProcessRunner.runJSON(
                binary: bin,
                arguments: commandPrefix + ["daily", "--json", "--offline", "--since", Self.weekStartStamp()],
                timeout: 45)
            let report = try JSONDecoder().decode(DailyReport.self, from: data)
            return PeriodUsage(period: Self.weekStartKey(), daily: report.daily)
        } catch RunnerError.nonZeroExit(1, _) {
            return nil
        } catch {
            AppLog.write("\(id) weekly fallback FAILED: \(error)")
            return nil
        }
    }

    private func fetchMonthTotal(binary bin: String) async -> PeriodUsage? {
        guard supportsMonthly else { return nil }
        do {
            let data = try await ProcessRunner.runJSON(
                binary: bin,
                arguments: commandPrefix + ["monthly", "--json", "--offline", "--since", Self.monthStartStamp()],
                timeout: 45)
            return try JSONDecoder().decode(MonthlyReport.self, from: data).monthly.last
        } catch RunnerError.nonZeroExit(1, _) {
            return nil
        } catch {
            AppLog.write("\(id) monthly FAILED: \(error)")
            return nil
        }
    }

    static func daysAgoStamp(_ days: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = .current
        return f.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
    }

    static func monthStartStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMM01"
        f.timeZone = .current
        return f.string(from: Date())
    }

    static func weekStartStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = .current
        return f.string(from: weekStartDate())
    }

    static func weekStartKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: weekStartDate())
    }

    static func todayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    private static func weekStartDate() -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }
}
