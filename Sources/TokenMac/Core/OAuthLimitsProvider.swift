import Foundation
import Security

enum LimitsError: Error {
    case keychainUnavailable
    case credentialFormat
    case httpStatus(Int)
}

/// 공식 한도 % 조회 — Claude Code 자격증명(Keychain)의 OAuth 토큰으로 usage endpoint 호출.
/// 비공식 endpoint 이므로 실패해도 토큰 표시에는 영향 없음 (한도 섹션만 숨김).
struct OAuthLimitsProvider: Sendable {
    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async throws -> LimitStatus {
        let token = try accessToken()
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LimitsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(LimitStatus.self, from: data)
    }

    private func accessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else {
            throw LimitsError.credentialFormat
        }
        return token
    }
}
