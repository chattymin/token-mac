import SwiftUI

func rarityColor(_ r: Rarity?) -> Color {
    switch r {
    case .uncommon: return .green
    case .rare: return .blue
    case .legendary: return .orange
    default: return .gray
    }
}

/// 스프라이트 1개(런타임 로드 + 캐시). 없으면 알 글리프. bob 으로 가벼운 상하 움직임.
struct SpriteView: View {
    let speciesID: Int?
    var size: CGFloat = 84
    var bob: Bool = false
    @State private var img: NSImage?
    @State private var up = false

    init(speciesID: Int?, size: CGFloat = 84, bob: Bool = false) {
        self.speciesID = speciesID
        self.size = size
        self.bob = bob
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임
        _img = State(initialValue: speciesID.flatMap { SpriteLoader.cachedImage(speciesID: $0) })
    }

    var body: some View {
        Group {
            if let img {
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: size, height: size)
            } else {
                Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
            }
        }
        .offset(y: bob && up ? -3 : 0)
        .task(id: speciesID) {
            guard let id = speciesID else { img = nil; return }
            img = await SpriteLoader.image(speciesID: id, animated: false)
        }
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// 진화 라인(초기→최종, 다음 후보 미리보기). done/cur/future.
struct EvoLineView: View {
    let nodes: [(id: Int, kind: String)]
    var thumb: CGFloat = 40
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                if i > 0 { Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                SpriteView(speciesID: node.id, size: thumb)
                    .opacity(node.kind == "future" ? 0.32 : 1)
                    .saturation(node.kind == "future" ? 0.4 : 1)
                    .overlay(alignment: .bottom) {
                        if node.kind == "cur" {
                            Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 2)
                        }
                    }
            }
        }
    }
}

/// 팝오버 상단 — 현재 포켓몬 + 진화 진행.
struct CompanionHeader: View {
    let store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                SpriteView(speciesID: store.currentSpeciesID, size: 76, bob: true)
                    .frame(width: 76, height: 76)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(store.displayName).font(.callout.weight(.semibold))
                        if let r = store.rarity {
                            Text(r.rawValue.uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(r)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if store.hasActive {
                        Text(store.stageText).font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: store.progress).controlSize(.small).tint(.orange)
                        if store.tokensToNext > 0 {
                            Text((store.isFinalStage ? "졸업까지 " : "다음 진화까지 ")
                                 + TokenFormatter.compact(store.tokensToNext))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("설치 후 첫 토큰을 기다리는 중…").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(statusLine).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if store.hasActive, !store.lineNodes.isEmpty {
                EvoLineView(nodes: store.lineNodes)
            }
            if let g = store.justGraduated {
                Text("\(g) 졸업 → 도감에 보존. 새 Token Egg가 도착했어요!")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var statusLine: String {
        switch store.displayState {
        case .egg:     return "곧 깨어나요."
        case .idle:    return "오늘은 조용히 자리를 지켜요."
        case .working: return "오늘의 작업 흔적이 쌓이고 있어요."
        case .focus:   return "지금은 집중 모드예요."
        case .tired:   return "한도에 가까워요. 잠깐 쉬어도 괜찮아요."
        case .sleep:   return "지금은 자고 있어요."
        case .levelUp: return store.justEvolvedTo.map { "\($0)(으)로 진화했어요!" } ?? "성장했어요!"
        }
    }
}

/// 도감 — 잡은 라인(초기→최종 전부) 목록.
struct CollectionView: View {
    let store: CompanionStore
    var body: some View {
        ScrollView {
            if store.dexEntries.isEmpty {
                Text("아직 졸업한 포켓몬이 없어요. 최종 진화까지 키워보세요.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.dexEntries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.rarity.rawValue.uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(rarityColor(entry.rarity)).foregroundStyle(.white)
                                    .clipShape(Capsule())
                                Spacer()
                                Text("\(entry.chainOrder.count)단계 · 완성").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            EvoLineView(nodes: entry.chainOrder.map { ($0, "done") }, thumb: 38)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }
}
