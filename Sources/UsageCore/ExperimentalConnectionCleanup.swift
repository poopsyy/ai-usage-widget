import Foundation
import LocalAuthentication
import Security

/// Migration only: never reads the retired experiment's session or another application's entries.
public enum ExperimentalConnectionCleanup {
    public static func forget(delete: ([String: Any]) -> OSStatus = { SecItemDelete($0 as CFDictionary) }) throws {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "dev.local.ai-usage-widget.connections",
                                   kSecAttrAccount as String: "claude.web.session.v1",
                                   kSecUseAuthenticationContext as String: context]
        let status = delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "AIUsageCleanup", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "The experimental saved connection could not be removed. Unlock your Keychain and try again. No credentials were read."])
        }
    }
}
