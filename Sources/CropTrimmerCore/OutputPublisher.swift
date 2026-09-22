import Foundation
import Darwin

/// Publishes only temporary paths issued by this process, without replacing existing files.
public enum OutputPublisher {
    private static let lock = NSLock()
    private static var owned = Set<String>()
    public static func temporaryURL(in directory: URL, extension fileExtension: String) -> URL {
        let suffix = safeExtension(fileExtension)
        let url = directory.appendingPathComponent(".croptrimmer-\(UUID().uuidString).\(suffix)").standardizedFileURL
        lock.lock(); owned.formUnion(spellings(of: url)); lock.unlock()
        return url
    }

    /// Every spelling one temporary answers to. `standardizedFileURL` strips a `/private` prefix
    /// only once the file exists, so a path registered before the encode comes back different
    /// afterwards; registering and matching both spellings keeps ownership stable either way.
    private static func spellings(of url: URL) -> Set<String> {
        var paths: Set<String> = [url.path, url.standardizedFileURL.path]
        for path in paths {
            if path.hasPrefix("/private/") { paths.insert(String(path.dropFirst("/private".count))) }
            else { paths.insert("/private" + path) }
        }
        return paths
    }

    /// True when this process issued the temporary, under any of its spellings.
    private static func isOwned(_ url: URL) -> Bool {
        let candidates = spellings(of: url)
        lock.lock(); defer { lock.unlock() }
        return !owned.isDisjoint(with: candidates)
    }

    private static func release(_ url: URL) {
        let candidates = spellings(of: url)
        lock.lock(); owned.subtract(candidates); lock.unlock()
    }
    public static func publish(temporaryURL: URL, sourceURL: URL, cropped: Bool, trimmed: Bool = true, directory: URL, extension fileExtension: String, loopNumber: Int? = nil, speed: Double = 1, rotation: Int = 0, options: FilenameOptions = .standard) throws -> URL {
        let temporary = temporaryURL.standardizedFileURL
        // Compared as paths, not URLs: `deletingLastPathComponent()` leaves a trailing slash, so
        // the same folder spelled two ways is two different URLs but one path.
        let temporaryParent = temporary.deletingLastPathComponent().resolvingSymlinksInPath().path
        let destinationParent = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard isOwned(temporaryURL), temporaryParent == destinationParent, temporary.path != sourceURL.standardizedFileURL.path else {
            throw MediaError.failed("The export temporary file does not belong to this job or destination.")
        }
        let values = try temporary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else { throw MediaError.failed("Export produced no regular movie file.") }
        let base = baseName(sourceURL: sourceURL, cropped: cropped, trimmed: trimmed, loopNumber: loopNumber, speed: speed, rotation: rotation, options: options)
        for index in 1...10000 {
            let destination = directory.appendingPathComponent(base + (index == 1 ? "" : " \(index)")).appendingPathExtension(safeExtension(fileExtension))
            let result = temporary.path.withCString { src in destination.path.withCString { dst in renamex_np(src, dst, UInt32(RENAME_EXCL)) } }
            if result == 0 {
                release(temporaryURL)
                return destination
            }
            let code = errno
            if code == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Could not publish export without replacing files: \(String(cString: strerror(code))). Choose another destination."])
        }
        throw MediaError.failed("Too many files share this export name. Choose another destination.")
    }
    /// The name an export takes, before the uniquing suffix. Each operation contributes its own
    /// part only if the owner asked for it; with everything switched off the name is the source's,
    /// and uniquing keeps it from ever replacing the original.
    public static func baseName(sourceURL: URL, cropped: Bool, trimmed: Bool, loopNumber: Int? = nil, speed: Double = 1, rotation: Int = 0, options: FilenameOptions = .standard) -> String {
        var name = sourceURL.deletingPathExtension().lastPathComponent
        if options.includeLoopNumber, let loopNumber {
            name += " - loop \(String(format: "%02d", max(1, loopNumber)))"
        }
        let showsTrim = options.includeTrim && trimmed
        let showsCrop = options.includeCrop && cropped
        switch (showsTrim, showsCrop) {
        case (true, true): name += " - trim crop"
        case (true, false): name += " - trim"
        case (false, true): name += " - crop"
        case (false, false): break
        }
        if options.includeRotation, rotation != 0 { name += " - rot\(rotation)" }
        if options.includeSpeed, abs(speed - 1) > 0.000001 {
            name += " - " + speed.formatted(.number.precision(.fractionLength(0...3))) + "x"
        }
        return name
    }
    public static func discard(temporaryURL: URL) {
        guard isOwned(temporaryURL) else { return }
        release(temporaryURL)
        try? FileManager.default.removeItem(at: temporaryURL)
    }
    private static func safeExtension(_ value: String) -> String {
        let clean = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return clean.isEmpty ? "mp4" : clean
    }
}
