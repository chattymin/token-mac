import Foundation

/// CLI 바이너리(ccusage, codex 등) 절대경로 탐색.
/// GUI 앱(launchd 실행)은 사용자 셸 PATH 를 상속하지 않아, Homebrew 외 버전매니저
/// (mise/nvm/fnm/asdf/volta/bun)로 설치한 도구를 하드코딩 경로만으로는 못 찾는다.
/// 전략: 수동 지정(UserDefaults "<binary>Path") → 정적 경로(빠름) → 로그인+인터랙티브 셸 PATH 해석.
/// 바이너리별로 1회 캐시(셸 호출 비용 회피).
enum BinaryLocator {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: String?] = [:]

    /// `binary` 의 절대경로(없으면 nil). 스레드 세이프, 1회 해석 후 캐시.
    /// `staticPaths`: 셸 해석 전에 먼저 확인할 알려진 설치 경로.
    static func resolve(_ binary: String, staticPaths: [String]) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[binary] { return hit }
        let result = locate(binary, staticPaths: staticPaths)
        cache[binary] = result
        AppLog.write(result.map { "\(binary) resolved: \($0)" } ?? "\(binary) NOT found on PATH")
        return result
    }

    /// 설정 변경/재탐지 시 캐시 무효화.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    /// 버전매니저 공통 shim/bin 경로 + 주어진 정적 경로. (절대경로 우선 탐색용)
    static func commonNodeToolPaths(_ binary: String) -> [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin/\(binary)",                 // Homebrew (Apple Silicon)
            "/usr/local/bin/\(binary)",                    // Homebrew (Intel) / npm prefix
            "\(home)/.local/share/mise/shims/\(binary)",   // mise (shims 모드)
            "\(home)/.asdf/shims/\(binary)",               // asdf
            "\(home)/.volta/bin/\(binary)",                // Volta
            "\(home)/.bun/bin/\(binary)",                  // Bun
            "\(home)/.npm-global/bin/\(binary)",           // npm prefix=~/.npm-global
            "\(home)/.local/bin/\(binary)",
            "/usr/bin/\(binary)",
        ]
    }

    private static func locate(_ binary: String, staticPaths: [String]) -> String? {
        let fm = FileManager.default
        // 0) 사용자 수동 지정
        if let override = UserDefaults.standard.string(forKey: "\(binary)Path"),
           !override.isEmpty, fm.isExecutableFile(atPath: override) {
            return override
        }
        // 1) 정적 경로 (서브프로세스 없이 빠르게)
        if let hit = staticPaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // 2) 로그인+인터랙티브 셸 PATH 해석 (mise activate / nvm / fnm 등은 .zshrc 에서 PATH 주입)
        return shellResolve(binary)
    }

    /// 사용자 로그인 셸을 인터랙티브+로그인으로 띄워 `command -v <binary>` 결과를 받는다.
    /// 인터랙티브 프로파일이 stdout 에 noise(neofetch 등)를 찍을 수 있어 마커로 감싸 추출한다.
    private static func shellResolve(_ binary: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '<<<BIN:%s:BIN>>>' \"$(command -v \(binary) 2>/dev/null)\""]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            AppLog.write("\(binary) shell resolve spawn failed: \(error.localizedDescription)")
            return nil
        }
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            AppLog.write("\(binary) shell resolve timed out")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8),
              let path = parseMarkedPath(raw),
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    /// `<<<BIN:/path/to/tool:BIN>>>` 에서 경로만 추출. 프로파일 noise 무시.
    static func parseMarkedPath(_ s: String) -> String? {
        guard let start = s.range(of: "<<<BIN:"),
              let end = s.range(of: ":BIN>>>", range: start.upperBound..<s.endIndex) else {
            return nil
        }
        let path = s[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
