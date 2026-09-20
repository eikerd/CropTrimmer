import Foundation
import os

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

    private static let log = Logger(subsystem: "com.croptrimmer.mac", category: "preferences")

    /// Falls back to the standard names when nothing is stored, and says so in the log when
    /// something *was* stored but could not be read — otherwise a silent reset of the owner's
    /// preferences looks exactly like never having set them.
    public static func load(from defaults: UserDefaults = .standard) -> FilenameOptions {
        guard let data = defaults.data(forKey: key) else { return .standard }
        do {
            return try JSONDecoder().decode(FilenameOptions.self, from: data)
        } catch {
            log.error("Stored file-name options could not be read (\(error.localizedDescription, privacy: .public)); using the standard names.")
            return .standard
        }
    }

    public func save(to defaults: UserDefaults = .standard) {
        do {
            defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
        } catch {
            Self.log.error("File-name options could not be saved (\(error.localizedDescription, privacy: .public)); this session keeps them, the next one will not.")
        }
    }
}
