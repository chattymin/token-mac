import Foundation
import Observation

/// 게임 상태의 출처. 설치 이후 토큰 사용량으로 포켓몬을 진화시키고, 최종체 + 추가 임계 도달 시
/// 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은 PokeProviding 으로 런타임 주입.
@MainActor
@Observable
final class CompanionStore {
    private(set) var state = CompanionState()
    private(set) var displayState: CompanionStateKind = .egg
    private(set) var currentLine: EvoLine?
    private(set) var isHatching = false
    private(set) var justEvolvedTo: String?     // 이름(연출/문구)
    private(set) var justGraduated: String?
    private var eventUntil: Date?

    private let provider: any PokeProviding
    private let clock: () -> Date
    private let fileURL: URL
    private var rng: any RandomNumberGenerator

    init(provider: any PokeProviding = PokeAPIClient.shared,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.provider = provider
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        load()
        if state.active != nil { displayState = .idle }
    }

    static func defaultURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    // MARK: 파생값 (UI)

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { state.language = lang; save() }
    /// 앱 전체 UI 문자열 — language 변경 시 자동 재렌더.
    var l: L { L(language) }

    var hasActive: Bool { state.active != nil }
    var rarity: Rarity? { state.active?.rarity }

    var displayName: String {
        guard let a = state.active, let line = currentLine else { return "Token Egg" }
        return line.localizedName(a.currentID, state.language)
    }
    var currentSpeciesID: Int? { state.active?.currentID }
    var isFinalStage: Bool {
        guard let a = state.active, let line = currentLine else { return false }
        return line.tree.node(withID: a.currentID)?.children.isEmpty ?? true
    }
    var stageText: String {
        guard let a = state.active else { return "" }
        return isFinalStage ? l.finalForm : l.stage(a.stageIndex + 1, a.totalForms)
    }
    var threshold: Int {
        guard let a = state.active else { return 1 }
        return PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
    }
    var progress: Double {
        guard let a = state.active, threshold > 0 else { return 0 }
        return min(1, max(0, Double(a.usedAtStage) / Double(threshold)))
    }
    var tokensToNext: Int { guard let a = state.active else { return 0 }; return max(0, threshold - a.usedAtStage) }

    /// 진화 라인 표시용: 현재까지 경로 + 다음 후보. (id, kind) kind: done/cur/future
    var lineNodes: [(id: Int, kind: String)] {
        guard let a = state.active, let line = currentLine else { return [] }
        var out: [(Int, String)] = []
        for (i, id) in a.pathIDs.enumerated() {
            out.append((id, i < a.stageIndex ? "done" : (i == a.stageIndex ? "cur" : "future")))
        }
        if let cur = line.tree.node(withID: a.currentID) {
            for ch in cur.children { out.append((ch.speciesID, "future")) }
        }
        return out
    }
    var dexEntries: [DexEntry] { state.dex }

    // MARK: 갱신 (AppDelegate 가 UsageStore 값으로 호출)

    func update(todayTokens: Int, todayDate: String, monthTotal: Int,
                burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool) {
        justEvolvedTo = nil
        if !state.installBaselineSet {
            // 설치 기준선 — 실제 데이터가 도착한 시점의 today 를 baseline 으로(이전 사용량 미카운트).
            // 데이터 도착 전(기동 직후 빈 새로고침)에는 잡지 않는다.
            guard hasUsageData else { displayState = .egg; return }
            state.installBaselineSet = true
            state.claimedTodayTokens = todayTokens
            state.lastDate = todayDate
            save()
        } else {
            if todayDate != state.lastDate { state.lastDate = todayDate; state.claimedTodayTokens = 0 }
            if todayTokens > state.claimedTodayTokens {
                let delta = todayTokens - state.claimedTodayTokens
                state.claimedTodayTokens = todayTokens
                state.usedSinceInstall += delta
                applyUsage(delta)
            }
        }
        // 이벤트 만료
        if let until = eventUntil, clock() > until { justGraduated = nil; eventUntil = nil }
        // 알이면 부화(첫 사용량 후 / 졸업 후)
        if state.active == nil, state.usedSinceInstall > 0, !isHatching {
            Task { await hatchIfNeeded() }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        displayState = computeState(burnTier: burnTier, limitWarning: limitWarning,
                                    hasUsageData: hasUsageData, today: todayTokens)
        save()
    }

    /// 토큰 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    func applyUsage(_ delta: Int) {
        guard state.active != nil, let line = currentLine else { return }
        state.active!.usedAtStage += delta
        var guardCount = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            let thr = PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
            guard a.usedAtStage >= thr else { break }
            guard let node = line.tree.node(withID: a.currentID) else { break }
            if node.children.isEmpty {
                graduate(); break
            } else {
                let next = pickNextChild(node, baseID: a.baseID)
                state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
                state.active!.stageIndex += 1
                state.active!.usedAtStage = a.usedAtStage - thr   // 초과분 이월
                justEvolvedTo = line.localizedName(next.speciesID, state.language)
            }
        }
        save()
    }

    private func pickNextChild(_ node: EvoNode, baseID: Int) -> EvoNode {
        let fresh = node.children.filter { ch in
            ch.finalIDs.contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? node.children : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private func graduate() {
        guard let a = state.active else { return }
        let finalID = a.currentID
        state.collectedFinals.insert("\(a.baseID):\(finalID)")
        state.dex.append(DexEntry(baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock()))
        justGraduated = currentLine?.localizedName(finalID, state.language)
        eventUntil = clock().addingTimeInterval(6)
        state.active = nil
        currentLine = nil
    }

    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, !isHatching, state.usedSinceInstall > 0 else { return }
        await hatch(baseID: chooseBase())
    }

    func hatch(baseID: Int) async {
        guard !isHatching else { return }
        isHatching = true
        defer { isHatching = false }
        guard let line = try? await provider.line(baseSpeciesID: baseID) else { return }
        currentLine = line
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], stageIndex: 0,
                                usedAtStage: 0, rarity: line.rarity, totalForms: line.totalForms)
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        save()
    }

    private func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        isHatching = true
        defer { isHatching = false }
        if let line = try? await provider.line(baseSpeciesID: a.baseID) { currentLine = line }
    }

    private func chooseBase() -> Int {
        let pool = PokemonPool.baseIDs
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private func computeState(burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool, today: Int) -> CompanionStateKind {
        if state.active == nil { return .egg }
        if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { return .levelUp }
        if limitWarning { return .tired }
        if !hasUsageData || today == 0 { return .sleep }
        switch burnTier {
        case .idle: return .idle
        case .normal: return .working
        case .fast, .blazing: return .focus
        }
    }

    // MARK: 영속
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(CompanionState.self, from: data) else { return }
        state = s
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL)
    }
}
