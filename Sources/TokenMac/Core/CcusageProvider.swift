import Foundation

/// ccusage / ccusage-codex 바이너리 기반 수집.
/// Homebrew(Apple Silicon/Intel) 설치 경로를 순서대로 탐색한다.
struct CcusageProvider: UsageProvider {
    let id: String
    let displayName: String
    let binaryCandidates: [String]
    let supportsBlocks: Bool

    static let claude = CcusageProvider(
        id: "claude_code",
        displayName: "Claude Code",
        binaryCandidates: [
            "/opt/homebrew/bin/ccusage",
            "/usr/local/bin/ccusage",
        ],
        supportsBlocks: true
    )

    static let codex = CcusageProvider(
        id: "codex",
        displayName: "Codex",
        binaryCandidates: [
            "/opt/homebrew/bin/ccusage-codex",
            "/usr/local/bin/ccusage-codex",
        ],
        supportsBlocks: false
    )

    var resolvedBinary: String? {
        binaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
                binary: bin, arguments: ["daily", "--json", "--offline", "--since", since],
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
                    binary: bin, arguments: ["blocks", "--json", "--offline", "--active"],
                    timeout: 45)
                let report = try JSONDecoder().decode(BlocksReport.self, from: data)
                result.activeBlock = report.blocks.first { $0.isActive }
                result.blocksOK = true
            } catch {
                AppLog.write("\(id) blocks FAILED: \(error)")
            }
        }

        // 주간/월간 누적 — 마지막 엔트리가 현재 기간
        do {
            let weekData = try await ProcessRunner.runJSON(
                binary: bin, arguments: ["weekly", "--json", "--offline", "--since", Self.daysAgoStamp(8)],
                timeout: 45)
            let monthData = try await ProcessRunner.runJSON(
                binary: bin, arguments: ["monthly", "--json", "--offline", "--since", Self.monthStartStamp()],
                timeout: 45)
            result.weekTotal = try JSONDecoder().decode(WeeklyReport.self, from: weekData).weekly.last
            result.monthTotal = try JSONDecoder().decode(MonthlyReport.self, from: monthData).monthly.last
            result.periodsOK = true
        } catch RunnerError.nonZeroExit(1, _) {
            // 기간 내 데이터 없음 (ccusage weekly/monthly 는 빈 결과에 exit 1) — 정상 케이스
            result.periodsOK = true
        } catch {
            AppLog.write("\(id) weekly/monthly FAILED: \(error)")
        }
        return result
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
}
