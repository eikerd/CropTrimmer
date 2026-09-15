import Foundation
import Security
import CropTrimmerCore

enum OpenRouterKeyStore {
    static let service = "com.croptrimmer.mac.openrouter"

    private static func query(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }

    static func read(service: String = service) throws -> String? {
        var request = query(service: service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw MediaError.failed("Could not read the OpenRouter API key from Keychain.")
        }
        return key
    }

    static func save(_ value: String, service: String = service) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MediaError.invalid("Enter an OpenRouter API key.") }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let query = query(service: service)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw MediaError.failed("Could not save the OpenRouter API key in Keychain.")
            }
        } else if status != errSecSuccess {
            throw MediaError.failed("Could not update the OpenRouter API key in Keychain.")
        }
    }
}
