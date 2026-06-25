import XCTest
@testable import TokenMac

// MARK: 경제

final class PokemonBalanceTests: XCTestCase {
    func testGraduationTotalIsConstantPerRarityRegardlessOfStages() {
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let T = PokemonBalance.graduationTotal(rarity)
            for k in 1...3 {
                let sum = (0..<k).reduce(0) { $0 + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: k, stageIndex: $1) }
                // 반올림 오차 허용
                XCTAssertLessThanOrEqual(abs(sum - T), 2, "rarity=\(rarity) k=\(k) sum=\(sum) T=\(T)")
            }
        }
    }
    func testHigherStageCostsMore() {
        for k in 2...3 {
            for i in 0..<(k - 1) {
                XCTAssertLessThan(
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i),
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i + 1))
            }
        }
    }
    func testRarerCostsMore() {
        XCTAssertLessThan(PokemonBalance.graduationTotal(.common), PokemonBalance.graduationTotal(.uncommon))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.uncommon), PokemonBalance.graduationTotal(.rare))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.rare), PokemonBalance.graduationTotal(.legendary))
    }
    func testRarityDerivation() {
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Rarity.from(captureRate: 90, isLegendary: false, isMythical: false), .uncommon)
        XCTAssertEqual(Rarity.from(captureRate: 45, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Rarity.from(captureRate: 3, isLegendary: true, isMythical: false), .legendary)
    }
}

// MARK: 헬퍼

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct StubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
}

private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }
private func makeLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    var names: [Int: [String: String]] = [:]
    for id in allIDs(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
// 3단 선형: 1→2→3
private let linear3 = makeLine(base: 1, tree: node(1, [node(2, [node(3)])]))
// 분기: 10 → {11,12,13}
private let branch3 = makeLine(base: 10, tree: node(10, [node(11), node(12), node(13)]))
// 무진화: 20
private let noEvo = makeLine(base: 20, tree: node(20))
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: 스토어

@MainActor
final class CompanionStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    func testInstallBaselineExcludesPreInstallUsage() {
        let s = store(linear3)
        // 데이터 도착 전 → baseline 미설정
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet)
        // 첫 실데이터 → baseline = 그 시점 today(이전 사용량 미카운트)
        s.update(todayTokens: 48_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertTrue(s.state.installBaselineSet)
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        // 이후 증가분만 누적
        s.update(todayTokens: 148_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 100_000_000)
    }

    func testEvolvesThroughLineAndGraduatesWithFullChain() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.currentSpeciesID, 1)
        XCTAssertEqual(s.state.active?.totalForms, 3)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)) // →2
        XCTAssertEqual(s.currentSpeciesID, 2)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1)) // →3 (final)
        XCTAssertEqual(s.currentSpeciesID, 3)
        XCTAssertTrue(s.isFinalStage)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 2)) // 졸업
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])   // 라인 전체 보존
        XCTAssertEqual(s.justGraduated, "포3")
    }

    func testNoEvolutionGraduatesAtSingleThreshold() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        XCTAssertTrue(s.isFinalStage)
        s.applyUsage(PokemonBalance.graduationTotal(.common))   // 무진화: 단일 임계 = T
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [20])
    }

    func testBranchingPrefersUncollectedFinals() async {
        let s = store(branch3)
        let evo = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0)
        let grad = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 1)
        var finals: [Int] = []
        for _ in 0..<3 {
            await s.hatch(baseID: 10)
            s.applyUsage(evo)    // 분기 진화
            s.applyUsage(grad)   // 졸업
            finals.append(s.dexEntries.last!.finalID)
        }
        XCTAssertEqual(Set(finals).count, 3)   // 같은 base 재부화 시 매번 다른 분기
        XCTAssertEqual(Set(finals), [11, 12, 13])
    }

    func testPersistenceRoundTrip() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-persist-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        await s1.hatch(baseID: 1)
        s1.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s1.setLanguage(.ja)
        let s2 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.state.active?.currentID, 2)
        XCTAssertEqual(s2.state.active?.stageIndex, 1)
        XCTAssertEqual(s2.language, .ja)
    }

    func testLocalizedName() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.displayName, "포1")
        s.setLanguage(.en); XCTAssertEqual(s.displayName, "P1")
        s.setLanguage(.ja); XCTAssertEqual(s.displayName, "ポ1")
    }
}
