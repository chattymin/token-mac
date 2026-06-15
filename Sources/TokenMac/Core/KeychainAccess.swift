import Foundation

#if os(macOS)
import Darwin
import LocalAuthentication
import Security

enum KeychainAccessGate {
    private static let defaultsKey = "disableKeychainAccess"

    static var isDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

enum KeychainNoUIQuery {
    private static let uiFailPolicy = resolveUIFailPolicy()

    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        // Some legacy Keychain ACL states can still prompt unless the old UI-fail
        // policy is present. Resolve it dynamically to avoid deprecated API usage.
        query[kSecUseAuthenticationUI as String] = uiFailPolicy as CFString
    }

    static func uiFailPolicyForTesting() -> String {
        uiFailPolicy
    }

    private static func resolveUIFailPolicy() -> String {
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }
}
#endif
