import XCTest
@testable import TokenMac

#if os(macOS)
import Security
#endif

final class TokenFormatterTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TokenFormatter.compact(0), "0")
        XCTAssertEqual(TokenFormatter.compact(987), "987")
        XCTAssertEqual(TokenFormatter.compact(12_345), "12.3K")
        XCTAssertEqual(TokenFormatter.compact(190_612_940), "190.6M")
        XCTAssertEqual(TokenFormatter.compact(1_240_000_000), "1.24B")
        XCTAssertEqual(TokenFormatter.compact(1_000_000), "1M")
    }
}

final class ModelDecodingTests: XCTestCase {
    // 실제 번들 ccusage 출력에서 채취한 fixture (2026-06-10)
    func testDailyReport() throws {
        let json = """
        {"daily":[{"date":"2026-06-10","inputTokens":907436,"outputTokens":1334526,
        "cacheCreationTokens":18905002,"cacheReadTokens":169465976,
        "totalTokens":190612940,"totalCost":311.30462895,
        "modelsUsed":["claude-fable-5"],"modelBreakdowns":[]}],"totals":null}
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(DailyReport.self, from: json)
        XCTAssertEqual(report.daily.count, 1)
        XCTAssertEqual(report.daily[0].totalTokens, 190_612_940)
        XCTAssertEqual(report.daily[0].date, "2026-06-10")
    }

    func testDailyReportV20Period() throws {
        // ccusage ≥20 은 "date" 대신 "period" 로 일자를 준다 (metadata/agent 필드 추가)
        let json = """
        {"daily":[{"agent":"all","period":"2026-06-15","metadata":{"agents":["claude"]},
        "inputTokens":372486,"outputTokens":167660,"cacheCreationTokens":2050363,
        "cacheReadTokens":18225182,"totalTokens":20815691,"totalCost":27.98}],"totals":null}
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(DailyReport.self, from: json)
        XCTAssertEqual(report.daily[0].date, "2026-06-15")
        XCTAssertEqual(report.daily[0].totalTokens, 20_815_691)
    }

    func testDailyReportEmpty() throws {
        // ccusage-codex 데이터 없음 케이스
        let json = #"{"daily":[],"totals":null}"#.data(using: .utf8)!
        let report = try JSONDecoder().decode(DailyReport.self, from: json)
        XCTAssertTrue(report.daily.isEmpty)
    }

    func testTotalTokensFallback() throws {
        // totalTokens 누락 시 4종 토큰(input/output/cacheCreation/cacheRead) 합으로 폴백
        let json = """
        {"daily":[{"date":"2026-06-10","inputTokens":10,"outputTokens":20,
        "cacheCreationTokens":30,"cacheReadTokens":40,"costUSD":1.5}]}
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(DailyReport.self, from: json)
        XCTAssertEqual(report.daily[0].totalTokens, 100)
        XCTAssertEqual(report.daily[0].totalCost, 1.5)
    }

    func testBlocksReport() throws {
        let json = """
        {"blocks":[{"id":"2026-06-10T06:00:00.000Z","startTime":"2026-06-10T06:00:00.000Z",
        "endTime":"2026-06-10T11:00:00.000Z","isActive":true,"isGap":false,"entries":399,
        "totalTokens":26910731,"costUSD":51.8358331}]}
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(BlocksReport.self, from: json)
        XCTAssertEqual(report.blocks.count, 1)
        XCTAssertTrue(report.blocks[0].isActive)
        XCTAssertNotNil(report.blocks[0].endDate)
    }

    func testWeeklyMonthlyReport() throws {
        // 실제 ccusage weekly/monthly 출력 fixture (2026-06-11)
        let weekly = """
        {"weekly":[{"week":"2026-05-31","inputTokens":79280,"outputTokens":634270,
        "cacheCreationTokens":4355252,"cacheReadTokens":141260644,
        "totalTokens":146329446,"totalCost":107.0425086}]}
        """.data(using: .utf8)!
        let w = try JSONDecoder().decode(WeeklyReport.self, from: weekly)
        XCTAssertEqual(w.weekly.last?.period, "2026-05-31")
        XCTAssertEqual(w.weekly.last?.totalTokens, 146_329_446)

        let monthly = """
        {"monthly":[{"month":"2026-06","totalTokens":671185849,"totalCost":589.255}]}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(MonthlyReport.self, from: monthly)
        XCTAssertEqual(m.monthly.last?.period, "2026-06")
        XCTAssertEqual(m.monthly.last?.totalTokens, 671_185_849)
    }

    func testBlockBurnRateDecoding() throws {
        let json = """
        {"blocks":[{"id":"b","startTime":"2026-06-11T01:00:00.000Z","endTime":"2026-06-11T06:00:00.000Z",
        "isActive":true,"totalTokens":26910731,"costUSD":51.8,
        "burnRate":{"tokensPerMinute":457194.05,"costPerHour":1.18}}]}
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(BlocksReport.self, from: json)
        XCTAssertEqual(report.blocks[0].tokensPerMinute ?? 0, 457_194.05, accuracy: 0.01)
    }

    func testForecastDepletion() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        // 블록 23M 토큰 = 23% → 1% ≈ 1M 토큰. 잔여 77% ≈ 77M 토큰. 분당 1M → 77분 후 도달
        let d = UsageStore.forecastDepletion(
            blockTokens: 23_000_000, tokensPerMinute: 1_000_000, utilization: 23, now: now)
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince(now) / 60, 77, accuracy: 0.5)

        // 추정 불안정 구간은 nil: 낮은 utilization / 낮은 burn / 24시간 초과
        XCTAssertNil(UsageStore.forecastDepletion(
            blockTokens: 1_000_000, tokensPerMinute: 1_000_000, utilization: 3, now: now))
        XCTAssertNil(UsageStore.forecastDepletion(
            blockTokens: 23_000_000, tokensPerMinute: 5_000, utilization: 23, now: now))
        XCTAssertNil(UsageStore.forecastDepletion(
            blockTokens: 100_000_000, tokensPerMinute: 10_000, utilization: 10, now: now))
    }

    func testLimitStatus() throws {
        // 실제 /api/oauth/usage 응답 fixture (2026-06-10, 마이크로초 정밀도 resets_at)
        let json = """
        {"five_hour":{"utilization":23.0,"resets_at":"2026-06-10T11:10:00.034464+00:00"},
        "seven_day":{"utilization":16.0,"resets_at":"2026-06-14T03:00:01.034496+00:00"},
        "seven_day_opus":null,
        "seven_day_sonnet":{"utilization":0.0,"resets_at":"2026-06-14T03:00:01.034508+00:00"},
        "seven_day_omelette":{"utilization":0.0,"resets_at":null},
        "extra_usage":{"is_enabled":false}}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(LimitStatus.self, from: json)
        XCTAssertEqual(status.fiveHour?.utilization, 23.0)
        XCTAssertNotNil(status.fiveHour?.resetDate, "마이크로초 정밀도 ISO8601 파싱 실패")
        XCTAssertNil(status.sevenDayOpus)
        XCTAssertEqual(status.sevenDay?.utilization, 16.0)
    }
}

#if os(macOS)
final class KeychainNoUIQueryTests: XCTestCase {
    func testNoUIQueryAddsAuthenticationContextAndFailPolicy() {
        var query: [String: Any] = [:]

        KeychainNoUIQuery.apply(to: &query)

        XCTAssertNotNil(query[kSecUseAuthenticationContext as String])
        XCTAssertEqual(
            query[kSecUseAuthenticationUI as String] as? String,
            KeychainNoUIQuery.uiFailPolicyForTesting())
    }
}
#endif
