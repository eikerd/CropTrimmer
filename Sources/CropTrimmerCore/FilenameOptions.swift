import Foundation
import os

/// Which operations get to show up in an exported file's name. The owner's preference, so the
/// name can be kept short ("Clip - loop 01") or made to describe what was done to it
/// ("Clip - loop 01 - trim crop - rot90 - 0.5x").
public struct FilenameOptions: Codable, Equatable, Sendable {
    public var includeLoopNumber: Bool
    public var includeCrop: Bool
    public var includeTrim: Bool
    public var includeSpeed: Bool
    public var includeRotation: Bool

    public init(includeLoopNumber: Bool = true, includeCrop: Bool = true, includeTrim: Bool = true, includeSpeed: Bool = false, includeRotation: Bool = true) {
        self.includeLoopNumber = includeLoopNumber
        self.includeCrop = includeCrop
        self.includeTrim = includeTrim
        self.includeSpeed = includeSpeed
        self.includeRotation = includeRotation
    }

    /// Options stored before a part existed have no key for it; that part takes its standard value
    /// rather than failing the whole decode and resetting the owner's other choices.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        includeLoopNumber = try values.decode(Bool.self, forKey: .includeLoopNumber)
        includeCrop = try values.decode(Bool.self, forKey: .includeCrop)
        includeTrim = try values.decode(Bool.self, forKey: .includeTrim)
        includeSpeed = try values.decode(Bool.self, forKey: .includeSpeed)
        includeRotation = try values.decodeIfPresent(Bool.self, forKey: .includeRotation) ?? Self.standard.includeRotation
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
