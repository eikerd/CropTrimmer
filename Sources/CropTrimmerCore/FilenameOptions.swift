import Foundation

/// Which operations get to show up in an exported file's name. The owner's preference, so the
/// name can be kept short ("Clip - loop 01") or made to describe what was done to it
/// ("Clip - loop 01 - trim crop - 0.5x").
public struct FilenameOptions: Codable, Equatable, Sendable {
    public var includeLoopNumber: Bool
    public var includeCrop: Bool
    public var includeTrim: Bool
    public var includeSpeed: Bool

    public init(includeLoopNumber: Bool = true, includeCrop: Bool = true, includeTrim: Bool = true, includeSpeed: Bool = false) {
        self.includeLoopNumber = includeLoopNumber
        self.includeCrop = includeCrop
        self.includeTrim = includeTrim
        self.includeSpeed = includeSpeed
    }

    /// What the app shipped with before any of this was configurable.
    public static let standard = FilenameOptions()

    private static let key = "CropTrimmer.filenameOptions"

    public static func load(from defaults: UserDefaults = .standard) -> FilenameOptions {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FilenameOptions.self, from: data) else { return .standard }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
