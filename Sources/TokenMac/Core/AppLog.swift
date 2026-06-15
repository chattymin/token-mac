import Foundation

/// ~/Library/Logs/TokenMac.log 단순 append 로거 (디버깅/장애 추적용)
enum AppLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("TokenMac.log")
    }()

    private static let queue = DispatchQueue(label: "tokenmac.log")

    static func write(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
}
