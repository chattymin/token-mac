import Foundation
import Security

enum LimitsError: Error {
    case keychainAccessDisabled
    case keychainUnavailable(OSStatus)
    case keychainInteractionNotAllowed
    case credentialFormat
    case httpStatus(Int)
}

/// Claude 한도 조회 추상화 — 실 구현(OAuthLimitsProvider) 또는 테스트 스텁 주입.
protocol ClaudeLimitsProviding: Sendable {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus
}

/// 공식 한도 % 조회 — Claude Code 자격증명(Keychain)의 OAuth 토큰으로 usage endpoint 호출.
/// 비공식 endpoint 이므로 실패해도 토큰 표시에는 영향 없음 (한도 섹션만 숨김).
struct OAuthLimitsProvider: ClaudeLimitsProviding, Sendable {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let accessTokenCache = OAuthAccessTokenCache.shared

    func fetch(allowKeychainPrompt: Bool = false) async throws -> LimitStatus {
        let token = try await accessTokenCache.accessToken(allowKeychainPrompt: allowKeychainPrompt)
        do {
            return try await fetchStatus(accessToken: token)
        } catch let error as LimitsError {
            guard case .httpStatus(let status) = error, status == 401 || status == 403 else {
                throw error
            }
            await accessTokenCache.invalidate(removePersistentCache: true)
            let refreshed = try await accessTokenCache.accessToken(
                allowKeychainPrompt: allowKeychainPrompt, bypassCache: true)
            guard refreshed != token else { throw error }
            return try await fetchStatus(accessToken: refreshed)
        }
    }

    private func fetchStatus(accessToken: String) async throws -> LimitStatus {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LimitsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(LimitStatus.self, from: data)
    }
}

private actor OAuthAccessTokenCache {
    static let shared = OAuthAccessTokenCache()
    private var cachedCredential: OAuthCredentialData.Credential?

    func accessToken(allowKeychainPrompt: Bool, bypassCache: Bool = false) throws -> String {
        if !bypassCache, let cachedCredential, !cachedCredential.isExpired {
            return cachedCredential.accessToken
        }

        if let credential = try Self.readPokeTokenBarCache() {
            cachedCredential = credential
            return credential.accessToken
        }
        if let credential = try Self.readClaudeCredentialsFile() {
            cachedCredential = credential
            Self.writePokeTokenBarCache(credential.data)
            return credential.accessToken
        }
        // 무프롬프트(no-UI) Claude Keychain 읽기. 사용자가 과거 한 번 '항상 허용'했다면
        // 앱 cdhash 가 항목 ACL 에 등록돼 *프롬프트 없이* 성공한다. 아직 허용 전이거나 접근
        // 불가면 errSecInteractionNotAllowed 로 조용히 실패 — 다이얼로그가 뜨지 않는다.
        // 이 경로 덕분에 자동 새로고침이 만료된 토큰을 스스로 재취득해 한도(주간 리셋 포함)를
        // 갱신한다. 수동 버튼 없이 자동 동작하게 하는 핵심.
        if let credential = Self.readClaudeKeychainSilently() {
            cachedCredential = credential
            Self.writePokeTokenBarCache(credential.data)
            return credential.accessToken
        }
        // 무프롬프트로 토큰을 못 구함 → 명시적 사용자 동작(설정의 갱신 버튼)일 때만 프롬프트를
        // 동반해 읽는다(최초 1회 '항상 허용' 유도). 이후엔 위 무프롬프트 경로로 자동 동작한다.
        // `security` CLI 보조 경로는 별도 신원이라 두 번째 ACL 프롬프트를 띄워 제거함.
        guard allowKeychainPrompt else {
            throw LimitsError.keychainInteractionNotAllowed
        }

        let credential = try Self.readClaudeKeychain(allowKeychainPrompt: allowKeychainPrompt)
        cachedCredential = credential
        Self.writePokeTokenBarCache(credential.data)
        return credential.accessToken
    }

    /// 무프롬프트 Keychain 읽기 — no-UI 쿼리라 권한이 없으면 프롬프트 대신 errSecInteractionNotAllowed.
    /// '아직 항상 허용 전'(interactionNotAllowed)은 정상 흐름이라 조용히 nil. 그 외(형식 오류·접근 불가)는
    /// 진단을 위해 로그를 남기고 nil — 자동 경로가 왜 토큰을 못 구했는지 추적 가능하게.
    private nonisolated static func readClaudeKeychainSilently() -> OAuthCredentialData.Credential? {
        do {
            return try readClaudeKeychain(allowKeychainPrompt: false)
        } catch LimitsError.keychainInteractionNotAllowed {
            return nil
        } catch {
            AppLog.write("silent claude keychain read failed: \(error)")
            return nil
        }
    }

    func invalidate(removePersistentCache: Bool = false) {
        cachedCredential = nil
        if removePersistentCache {
            Self.deletePokeTokenBarCache()
        }
    }

    private nonisolated static func readPokeTokenBarCache() throws -> OAuthCredentialData.Credential? {
        if KeychainAccessGate.isDisabled {
            throw LimitsError.keychainAccessDisabled
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthCredentialData.tokenMacCacheService,
            kSecAttrAccount as String: OAuthCredentialData.tokenMacCacheAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        KeychainNoUIQuery.apply(to: &query)

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            guard let credential = OAuthCredentialData.credential(from: data), !credential.isExpired else {
                deletePokeTokenBarCache()
                return nil
            }
            return credential
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw LimitsError.keychainInteractionNotAllowed
        default:
            throw LimitsError.keychainUnavailable(status)
        }
    }

    private nonisolated static func writePokeTokenBarCache(_ data: Data) {
        if KeychainAccessGate.isDisabled { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthCredentialData.tokenMacCacheService,
            kSecAttrAccount as String: OAuthCredentialData.tokenMacCacheAccount,
        ]
        KeychainNoUIQuery.apply(to: &query)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            AppLog.write("oauth cache update failed: \(updateStatus)")
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = "PokeTokenBar OAuth Cache"
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.write("oauth cache add failed: \(addStatus)")
        }
    }

    private nonisolated static func deletePokeTokenBarCache() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthCredentialData.tokenMacCacheService,
            kSecAttrAccount as String: OAuthCredentialData.tokenMacCacheAccount,
        ]
        KeychainNoUIQuery.apply(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.write("oauth cache delete failed: \(status)")
        }
    }

    private nonisolated static func readClaudeCredentialsFile() throws -> OAuthCredentialData.Credential? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let credential = OAuthCredentialData.credential(from: data), !credential.isExpired else {
            return nil
        }
        return credential
    }

    private nonisolated static func readClaudeKeychain(
        allowKeychainPrompt: Bool) throws -> OAuthCredentialData.Credential
    {
        if KeychainAccessGate.isDisabled {
            throw LimitsError.keychainAccessDisabled
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthCredentialData.claudeKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowKeychainPrompt {
            KeychainNoUIQuery.apply(to: &query)
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecInteractionNotAllowed {
            throw LimitsError.keychainInteractionNotAllowed
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable(status)
        }
        guard let credential = OAuthCredentialData.credential(from: data) else {
            throw LimitsError.credentialFormat
        }
        return credential
    }
}

enum OAuthCredentialData {
    static let claudeKeychainService = "Claude Code-credentials"
    static let tokenMacCacheService = "io.github.chattymin.poketokenbar.cache"
    static let tokenMacCacheAccount = "oauth.claude"

    struct Credential {
        let accessToken: String
        let expiresAt: Date?
        let data: Data

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date().addingTimeInterval(60)
        }
    }

    static func credential(from data: Data) -> Credential? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else {
            return nil
        }
        return Credential(accessToken: token, expiresAt: expiresAt(from: oauth["expiresAt"]), data: data)
    }

    private static func expiresAt(from raw: Any?) -> Date? {
        let value: Double?
        switch raw {
        case let raw as Double:
            value = raw
        case let raw as Int:
            value = Double(raw)
        case let raw as Int64:
            value = Double(raw)
        case let raw as String:
            value = Double(raw)
        default:
            value = nil
        }
        guard let value, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
