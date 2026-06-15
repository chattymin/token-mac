import Foundation

enum RunnerError: Error, CustomStringConvertible {
    case timeout(String)
    case nonZeroExit(Int32, String)
    case noJSON(String)

    var description: String {
        switch self {
        case .timeout(let bin): return "timeout: \(bin)"
        case .nonZeroExit(let code, let bin): return "exit \(code): \(bin)"
        case .noJSON(let bin): return "no JSON output: \(bin)"
        }
    }
}

/// AI CLI(claude/codex) 스폰 금지 원칙 (CodexBar #874 교훈):
/// 이 앱에서 Process 를 실행하는 곳은 이 파일이 유일하며, 호출 대상은 ccusage* 파서 바이너리뿐이다.
enum ProcessRunner {
    /// 바이너리를 실행하고 stdout 의 JSON 부분(Data)을 반환.
    /// stdout 은 pipe buffer 잘림 방지를 위해 temp file 로 캡처한다.
    ///
    /// timeout 기본 180초 — 메뉴바 앱은 백그라운드 QoS 스로틀 + 콜드 파일캐시에서 ccusage 가
    /// warm 대비 크게 느려질 수 있어 넉넉히 잡는다.
    static func runJSON(binary: String, arguments: [String], timeout: TimeInterval = 180) async throws -> Data {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmac-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        // App Nap 중인 부모로부터 background QoS 를 상속받아 스로틀되는 것을 방지
        process.qualityOfService = .userInitiated
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = FileHandle.nullDevice
        // GUI 앱의 stdin 을 상속하면 자식이 입력 대기로 영구 블록될 수 있어 명시적으로 차단
        process.standardInput = FileHandle.nullDevice

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let timedOut = OSAllocatedUnfairLockBox(false)
            process.terminationHandler = { p in
                if timedOut.value {
                    continuation.resume(throwing: RunnerError.timeout(binary))
                } else {
                    continuation.resume(returning: p.terminationStatus)
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    timedOut.value = true
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }

        guard status == 0 else { throw RunnerError.nonZeroExit(status, binary) }

        let raw = try Data(contentsOf: outURL)
        // 첫 '{' 또는 '[' 이전의 비-JSON 프리픽스(경고 라인 등) 제거
        guard let start = raw.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) else {
            throw RunnerError.noJSON(binary)
        }
        return raw.subdata(in: start..<raw.endIndex)
    }
}

/// Swift 6 Sendable 제약 하에서 terminationHandler/asyncAfter 간 플래그 공유용 잠금 박스
final class OSAllocatedUnfairLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
