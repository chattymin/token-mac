import Foundation

// MARK: - ccusage daily

struct DailyUsage: Decodable, Sendable {
    var date: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var totalTokens: Int
    var totalCost: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // ccusage ≤18 은 "date", ≥20 은 "period" 로 일자를 준다
        date = try c.decodeIfPresent(String.self, forKey: .date)
            ?? c.decodeIfPresent(String.self, forKey: .period) ?? ""
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
            ?? c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        // totalTokens 없으면 4종 토큰 합으로 폴백
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? (inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens)
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
    }

    init(date: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int, totalTokens: Int, totalCost: Double) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
    }

    private enum CodingKeys: String, CodingKey {
        case date, period, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case cachedInputTokens, totalTokens, totalCost, costUSD
    }
}

struct DailyReport: Decodable, Sendable {
    var daily: [DailyUsage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent([DailyUsage].self, forKey: .daily) ?? []
    }

    private enum CodingKeys: String, CodingKey { case daily }
}

// MARK: - ccusage blocks

struct BlockUsage: Decodable, Sendable {
    var id: String
    var startTime: String
    var endTime: String
    var isActive: Bool
    var totalTokens: Int
    var costUSD: Double
    /// ccusage blocks 의 burnRate.tokensPerMinute — 한도 소진 예측과 companion 표시 상태에 사용
    var tokensPerMinute: Double?

    var endDate: Date? { ISO8601Parser.date(from: endTime) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        if let burn = try? c.decodeIfPresent(BurnRate.self, forKey: .burnRate) {
            tokensPerMinute = burn.tokensPerMinute
        }
    }

    private struct BurnRate: Decodable {
        var tokensPerMinute: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, isActive, totalTokens, costUSD, burnRate
    }
}

struct BlocksReport: Decodable, Sendable {
    var blocks: [BlockUsage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([BlockUsage].self, forKey: .blocks) ?? []
    }

    private enum CodingKeys: String, CodingKey { case blocks }
}

// MARK: - ccusage weekly / monthly

struct PeriodUsage: Decodable, Sendable {
    /// 주 시작일("2026-05-31") 또는 월("2026-06")
    var period: String
    var totalTokens: Int
    var totalCost: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decodeIfPresent(String.self, forKey: .week)
            ?? c.decodeIfPresent(String.self, forKey: .month)
            ?? c.decodeIfPresent(String.self, forKey: .period) ?? ""
        let input = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        let output = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let cacheW = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        let cacheR = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
            ?? c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? (input + output + cacheW + cacheR)
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
    }

    init(period: String, totalTokens: Int, totalCost: Double) {
        self.period = period
        self.totalTokens = totalTokens
        self.totalCost = totalCost
    }

    init(period: String, daily: [DailyUsage]) {
        self.period = period
        totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        totalCost = daily.reduce(0) { $0 + $1.totalCost }
    }

    private enum CodingKeys: String, CodingKey {
        case week, month, period, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case cachedInputTokens, totalTokens, totalCost, costUSD
    }
}

struct WeeklyReport: Decodable, Sendable {
    var weekly: [PeriodUsage]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekly = try c.decodeIfPresent([PeriodUsage].self, forKey: .weekly) ?? []
    }
    private enum CodingKeys: String, CodingKey { case weekly }
}

struct MonthlyReport: Decodable, Sendable {
    var monthly: [PeriodUsage]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthly = try c.decodeIfPresent([PeriodUsage].self, forKey: .monthly) ?? []
    }
    private enum CodingKeys: String, CodingKey { case monthly }
}

// MARK: - OAuth limits (api.anthropic.com/api/oauth/usage)

struct LimitWindow: Decodable, Sendable {
    var utilization: Double?
    var resetsAt: String?

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return ISO8601Parser.date(from: resetsAt)
    }

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct LimitStatus: Decodable, Sendable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var sevenDayOpus: LimitWindow?
    var sevenDaySonnet: LimitWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

// MARK: - Codex app-server rate limits

struct CodexRateLimitWindow: Decodable, Sendable {
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Int?

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }

    var displayName: String {
        switch windowDurationMins {
        case 300: return "5시간 세션"
        case 10_080: return "주간"
        case let mins? where mins >= 60 && mins % 60 == 0: return "\(mins / 60)시간"
        case let mins?: return "\(mins)분"
        case nil: return "한도"
        }
    }
}

struct CodexCreditsSnapshot: Decodable, Sendable {
    var balance: String?
    var hasCredits: Bool
    var unlimited: Bool
}

struct CodexSpendControlLimit: Decodable, Sendable {
    var limit: String
    var remainingPercent: Int
    var resetsAt: Int
    var used: String

    var usedPercent: Int { max(0, min(100, 100 - remainingPercent)) }
    var resetDate: Date { Date(timeIntervalSince1970: TimeInterval(resetsAt)) }
}

struct CodexRateLimitSnapshot: Decodable, Sendable {
    var limitId: String?
    var limitName: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var credits: CodexCreditsSnapshot?
    var individualLimit: CodexSpendControlLimit?
    var planType: String?
    var rateLimitReachedType: String?

    var hasVisibleLimit: Bool {
        primary != nil || secondary != nil || individualLimit != nil
    }
}

struct CodexRateLimitStatus: Decodable, Sendable {
    var rateLimits: CodexRateLimitSnapshot
    var rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?

    var codex: CodexRateLimitSnapshot {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }

    var hasVisibleLimit: Bool { codex.hasVisibleLimit }
}

// MARK: - Provider snapshot

struct ProviderSnapshot: Sendable, Identifiable {
    var providerID: String
    var displayName: String
    var today: DailyUsage?
    var activeBlock: BlockUsage?
    var weekTotal: PeriodUsage?
    var monthTotal: PeriodUsage?
    var fetchedAt: Date

    var id: String { providerID }
    var todayTotalTokens: Int { today?.totalTokens ?? 0 }
}

// MARK: - ISO8601 with fractional seconds

enum ISO8601Parser {
    /// resets_at 은 마이크로초("...034464+00:00") 또는 밀리초("....303Z") 형태 — 둘 다 처리.
    /// ISO8601DateFormatter 는 non-Sendable 이라 호출마다 생성 (파싱 빈도 낮음).
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        // 소수점 자릿수가 3자리가 아니면 3자리로 절단 후 재시도
        if let dotIndex = string.firstIndex(of: ".") {
            let afterDot = string.index(after: dotIndex)
            if let tzIndex = string[afterDot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                let frac = String(string[afterDot..<tzIndex]).prefix(3)
                let padded = String(frac).padding(toLength: 3, withPad: "0", startingAt: 0)
                let rebuilt = String(string[..<dotIndex]) + "." + padded + String(string[tzIndex...])
                if let d = fractional.date(from: rebuilt) { return d }
            }
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
