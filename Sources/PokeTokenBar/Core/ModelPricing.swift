import Foundation

/// 모델별 토큰 단가(USD/토큰). ccusage(--offline, LiteLLM 스냅샷)의 단가를 실측 역산해 동일하게 번들.
/// 검증: 여러 날 ccusage --breakdown 의 (토큰타입 4종, cost)로 선형 역산 → 적합오차 0.000%.
struct ModelRate: Equatable {
    let input: Double        // USD per token
    let output: Double
    let cacheWrite: Double   // cache creation
    let cacheRead: Double

    static let zero = ModelRate(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)

    /// USD per **million** tokens 로 선언(가독성) → per-token 으로 변환.
    static func perMillion(_ input: Double, _ output: Double, _ cacheWrite: Double, _ cacheRead: Double) -> ModelRate {
        ModelRate(input: input / 1_000_000, output: output / 1_000_000,
                  cacheWrite: cacheWrite / 1_000_000, cacheRead: cacheRead / 1_000_000)
    }
}

enum ModelPricing {
    /// 정확 매칭 테이블 (USD/Mtok). ccusage 와 일치(역산 0% 오차).
    static let table: [String: ModelRate] = [
        "claude-opus-4-8":            .perMillion(5, 25, 6.25, 0.5),
        "claude-opus-4-7":            .perMillion(5, 25, 6.25, 0.5),
        "claude-sonnet-4-6":          .perMillion(3, 15, 3.75, 0.3),
        "claude-haiku-4-5-20251001":  .perMillion(1, 5, 1.25, 0.1),
        "claude-fable-5":             .zero,                          // ccusage 미가격 → $0
        "gpt-5.5":                    .perMillion(5, 30, 0, 0.5),
    ]

    /// 모델명 → 단가. 정확 매칭 우선, 없으면 패밀리(opus/sonnet/haiku/gpt) 폴백(버전 드리프트 대비),
    /// 그래도 없으면 0(ccusage 가 미가격 모델을 0 으로 처리하는 것과 동일).
    static func rate(for model: String) -> ModelRate {
        if let r = table[model] { return r }
        let m = model.lowercased()
        if m.contains("opus")   { return .perMillion(5, 25, 6.25, 0.5) }
        if m.contains("sonnet") { return .perMillion(3, 15, 3.75, 0.3) }
        if m.contains("haiku")  { return .perMillion(1, 5, 1.25, 0.1) }
        if m.contains("gpt") || m.contains("codex") || m.contains("o4") || m.contains("o3") {
            return .perMillion(5, 30, 0, 0.5)
        }
        return .zero
    }

    static func cost(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let r = rate(for: model)
        return Double(input) * r.input
            + Double(output) * r.output
            + Double(cacheWrite) * r.cacheWrite
            + Double(cacheRead) * r.cacheRead
    }
}
