import Foundation

public struct SavedLook: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var color: ColorSettings
    public let created: Date

    public init(id: UUID = UUID(), name: String, color: ColorSettings, created: Date = Date()) {
        self.id = id; self.name = name; self.color = color; self.created = created
    }

    fileprivate func validate() throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { throw MediaError.invalid("Saved look names must contain 1–200 characters.") }
        try color.validate()
    }
}

/// Small explicit preset storage. It stores looks only; projects and source
/// media remain session-scoped as required by the MVP.
public actor SavedLookStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var errors: [String] = []

    public init(directory: URL? = nil) {
        if let directory { self.directory = directory }
        else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = support.appendingPathComponent("CropTrimmer/Looks", isDirectory: true)
        }
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ look: SavedLook) throws {
        try look.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(look.id.uuidString + ".json")
        try encoder.encode(look).write(to: url, options: .atomic)
    }

    public func look(id: UUID) throws -> SavedLook? {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(url)
    }

    public func looks() throws -> [SavedLook] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        errors = []
        return files.compactMap { url in
            do { return try decode(url) }
            catch { errors.append(error.localizedDescription); return nil }
        }
    }

    public func lastLoadErrors() -> [String] { errors }

    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func decode(_ url: URL) throws -> SavedLook {
        do {
            let look = try decoder.decode(SavedLook.self, from: Data(contentsOf: url))
            try look.validate()
            return look
        } catch let error as MediaError { throw error }
        catch { throw MediaError.invalid("Saved look \(url.deletingPathExtension().lastPathComponent) is corrupt.") }
    }
}
