import Foundation

/// Codex CLI app-server의 account/rateLimits/read 응답으로 Codex 한도 %를 읽는다.
/// 모델 turn을 시작하지 않고 account snapshot만 요청한다.
struct CodexRateLimitsProvider {
    let binaryCandidates: [String]

    init(binaryCandidates: [String] = Self.defaultBinaryCandidates) {
        self.binaryCandidates = binaryCandidates
    }

    private static var defaultBinaryCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.codex/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
    }

    var resolvedBinary: String? {
        binaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch() async throws -> CodexRateLimitStatus? {
        guard let bin = resolvedBinary else { return nil }
        let lines = try Self.requestLines()
        let data = try await ProcessRunner.runJSONRPC(
            binary: bin,
            arguments: ["app-server", "--stdio"],
            inputLines: lines,
            responseID: 1,
            timeout: 20)
        return try JSONDecoder().decode(CodexRateLimitStatus.self, from: data)
    }

    private static func requestLines() throws -> [String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "token_mac",
                        "title": "TokenMac",
                        "version": version,
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                    ],
                ],
            ],
            [
                "method": "initialized",
                "params": [:],
            ],
            [
                "method": "account/rateLimits/read",
                "id": 1,
                "params": [:],
            ],
        ]
        return try messages.map { message in
            let data = try JSONSerialization.data(withJSONObject: message, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
