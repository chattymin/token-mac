import Foundation

/// 파일별 증분 캐시 — `(path, mtime, size)` 가 같으면 재파싱하지 않는다. 디스크에 영속화한다.
///
/// 사용자가 매일 코딩하면 사실상 모든 세션 파일이 "이번 달 수정"(수백 MB)이라 mtime 필터만으론
/// 매 새로고침마다 전수 파싱을 피할 수 없다. 변경된 파일만 다시 읽도록 캐시하고(정상 상태 ~0.1s),
/// 캐시를 디스크에 저장해 **콜드 스타트(전체 파싱 ~수십초)를 최초 1회로** 제한한다(배터리).
actor LocalUsageCache {
    static let shared = LocalUsageCache()

    private struct Blob: Codable { let mtime: Date; let size: Int; let entries: [LocalUsageReader.Entry] }
    private struct Snapshot: Codable { var claude: [String: Blob]; var codex: [String: Blob] }

    private var claudeCache: [String: Blob] = [:]
    private var codexCache: [String: Blob] = [:]
    private var loaded = false
    private var dirty = false
    private var lastSave: Date?

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    func claudeEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        let all = collect(root: LocalUsageReader.claudeProjectsDir, since: modifiedSince, cache: &claudeCache) {
            LocalUsageReader.parseClaudeFile($0, fmt: fmt)
        }
        saveIfNeeded()
        return LocalUsageReader.dedupKeepMax(all)
    }

    func codexEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        let r = collect(root: LocalUsageReader.codexSessionsDir, since: modifiedSince, cache: &codexCache) {
            LocalUsageReader.parseCodexFile($0, fmt: fmt)
        }
        saveIfNeeded()
        return r
    }

    private func collect(root: URL, since: Date, cache: inout [String: Blob],
                         parse: (URL) -> [LocalUsageReader.Entry]) -> [LocalUsageReader.Entry] {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [LocalUsageReader.Entry] = []
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = v.contentModificationDate, mtime >= since else { continue }
            let size = v.fileSize ?? 0
            let key = url.path
            if let blob = cache[key], blob.mtime == mtime, blob.size == size {
                result.append(contentsOf: blob.entries)            // 변경 없음 → 재파싱 안 함
            } else {
                let entries = parse(url)
                cache[key] = Blob(mtime: mtime, size: size, entries: entries)
                dirty = true
                result.append(contentsOf: entries)
            }
        }
        return result
    }

    // MARK: 영속화

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        claudeCache = snap.claude
        codexCache = snap.codex
    }

    /// 어떤 조회 윈도우(오늘/주/월)에도 들지 않는 오래된 파일 blob 을 제거해 캐시 무한 증가를 막는다.
    /// (가장 넓은 윈도우는 월·주 시작이라 40일이면 충분한 여유. 삭제된 세션 파일 blob 도 함께 정리.)
    private func prune() {
        let cutoff = Date().addingTimeInterval(-40 * 86400)
        claudeCache = claudeCache.filter { $0.value.mtime >= cutoff }
        codexCache = codexCache.filter { $0.value.mtime >= cutoff }
    }

    /// 변경이 있으면 디스크에 저장(최소 60초 간격으로 throttle — 잦은 쓰기 방지).
    private func saveIfNeeded() {
        guard dirty else { return }
        if let last = lastSave, Date().timeIntervalSince(last) < 60 { return }
        prune()
        let snap = Snapshot(claude: claudeCache, codex: codexCache)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: Self.fileURL)
            dirty = false
            lastSave = Date()
        }
    }
}
