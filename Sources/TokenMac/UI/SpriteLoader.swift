import AppKit

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
actor SpriteStore {
    static let shared = SpriteStore()
    private let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    private var mem: [String: Data] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMac/sprites")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func data(speciesID: Int, animated: Bool) async -> Data? {
        let key = "\(speciesID)-\(animated ? "a" : "s")"
        if let d = mem[key] { return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { mem[key] = d; return d }
        let urlStr = animated
            ? "\(base)/versions/generation-v/black-white/animated/\(speciesID).gif"
            : "\(base)/\(speciesID).png"
        guard let url = URL(string: urlStr),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file)
        mem[key] = d
        return d
    }
}

@MainActor
enum SpriteLoader {
    static let cacheDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMac/sprites")
    }()

    /// 디스크 캐시에 이미 있으면 동기 반환(네트워크 없음). 없으면 nil.
    static func cachedImage(speciesID: Int, animated: Bool = false) -> NSImage? {
        let ext = animated ? "gif" : "png"
        let f = cacheDir.appendingPathComponent("\(speciesID)-\(animated ? "a" : "s").\(ext)")
        guard let d = try? Data(contentsOf: f) else { return nil }
        return NSImage(data: d)
    }

    /// 정적 스프라이트. animated=true 면 Gen-V 움직이는 스프라이트(없으면 정적으로 폴백).
    static func image(speciesID: Int, animated: Bool = false) async -> NSImage? {
        if animated, let d = await SpriteStore.shared.data(speciesID: speciesID, animated: true), let img = NSImage(data: d) {
            return img
        }
        guard let d = await SpriteStore.shared.data(speciesID: speciesID, animated: false) else { return nil }
        return NSImage(data: d)
    }
}
