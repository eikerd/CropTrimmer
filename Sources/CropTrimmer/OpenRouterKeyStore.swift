import Foundation
import CropTrimmerCore

// The key lives in plain UserDefaults, not the Keychain. The app is signed
// ad-hoc (scripts/build-app.sh), so its code identity changes on every build
// and the Keychain re-prompts for the login password each time — "Always
// Allow" never sticks. The owner chose a stored preference for this personal
// tool: paste once, no prompts. The value is readable by anything running as
// the user, so treat the key as rotatable rather than secret.
enum OpenRouterKeyStore {
    static let defaultsKey = "openRouterAPIKey"

    static func read(defaults: UserDefaults = .standard) throws -> String? {
        let key = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    static func save(_ value: String, defaults: UserDefaults = .standard) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MediaError.invalid("Enter an OpenRouter API key.") }
        defaults.set(key, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
