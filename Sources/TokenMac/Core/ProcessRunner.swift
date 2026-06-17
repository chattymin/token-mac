import Foundation

enum RunnerError: Error, CustomStringConvertible {
    case timeout(String)
    case nonZeroExit(Int32, String)
    case noJSON(String)
    case missingResponse(String)
    case rpcError(String)

    var description: String {
        switch self {
        case .timeout(let bin): return "timeout: \(bin)"
        case .nonZeroExit(let code, let bin): return "exit \(code): \(bin)"
        case .noJSON(let bin): return "no JSON output: \(bin)"
        case .missingResponse(let bin): return "missing JSON-RPC response: \(bin)"
        case .rpcError(let message): return "JSON-RPC error: \(message)"
        }
    }
}

/// Process 실행 지점은 이 파일 하나로 제한한다.
/// usage 집계는 ccusage* 파서만 호출하고, Codex CLI 는 app-server rate-limit read만 사용한다.
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

    /// newline-delimited JSON-RPC 서버에 요청을 보내고 특정 id의 `result` JSON만 반환.
    /// Codex app-server가 stdout에 로그/notification을 섞어 내보낼 수 있어 line 단위로 필터링한다.
    static func runJSONRPC(
        binary: String,
        arguments: [String],
        inputLines: [String],
        responseID: Int,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmac-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.qualityOfService = .userInitiated
        let stdoutHandle = try FileHandle(forWritingTo: outURL)
        defer { try? stdoutHandle.close() }
        let stdinPipe = Pipe()
        process.standardOutput = stdoutHandle
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdinPipe
        var stdinClosed = false
        func closeStdin() {
            guard !stdinClosed else { return }
            stdinPipe.fileHandleForWriting.closeFile()
            stdinClosed = true
        }
        defer {
            closeStdin()
            if process.isRunning { process.terminate() }
        }

        do {
            try process.run()
        } catch {
            throw error
        }

        let payload = inputLines.joined(separator: "\n") + "\n"
        stdinPipe.fileHandleForWriting.write(Data(payload.utf8))

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let raw = (try? Data(contentsOf: outURL)) ?? Data()
            if let response = try Self.jsonRPCResultData(in: raw, responseID: responseID) {
                return response
            }
            if !process.isRunning {
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            throw RunnerError.timeout(binary)
        }
        if process.terminationStatus != 0 {
            throw RunnerError.nonZeroExit(process.terminationStatus, binary)
        }
        throw RunnerError.missingResponse(binary)
    }

    private static func jsonRPCResultData(in raw: Data, responseID: Int) throws -> Data? {
        guard let text = String(data: raw, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            guard let id = object["id"] as? NSNumber, id.intValue == responseID else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "\(error)"
                throw RunnerError.rpcError(message)
            }
            guard let result = object["result"] else { continue }
            guard JSONSerialization.isValidJSONObject(result) else { return nil }
            return try JSONSerialization.data(withJSONObject: result, options: [])
        }
        return nil
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
