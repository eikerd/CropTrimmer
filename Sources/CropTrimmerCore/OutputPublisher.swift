import Foundation
import Darwin

/// Publishes only temporary paths issued by this process, without replacing existing files.
public enum OutputPublisher {
    private static let lock = NSLock()
    private static var owned = Set<String>()
    public static func temporaryURL(in directory: URL, extension fileExtension: String) -> URL {
        let suffix = safeExtension(fileExtension)
        let url = directory.appendingPathComponent(".croptrimmer-\(UUID().uuidString).\(suffix)").standardizedFileURL
        lock.lock(); owned.insert(url.path); lock.unlock()
        return url
    }
    public static func publish(temporaryURL: URL, sourceURL: URL, cropped: Bool, trimmed: Bool = true, directory: URL, extension fileExtension: String, loopNumber: Int? = nil) throws -> URL {
        let temporary = temporaryURL.standardizedFileURL
        lock.lock(); let isOwned = owned.contains(temporary.path); lock.unlock()
        guard isOwned, temporary.deletingLastPathComponent().resolvingSymlinksInPath() == directory.standardizedFileURL.resolvingSymlinksInPath(), temporary != sourceURL.standardizedFileURL else {
            throw MediaError.failed("The export temporary file does not belong to this job or destination.")
        }
        let values = try temporary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else { throw MediaError.failed("Export produced no regular movie file.") }
        let base = baseName(sourceURL: sourceURL, cropped: cropped, trimmed: trimmed, loopNumber: loopNumber)
        for index in 1...10000 {
            let destination = directory.appendingPathComponent(base + (index == 1 ? "" : " \(index)")).appendingPathExtension(safeExtension(fileExtension))
            let result = temporary.path.withCString { src in destination.path.withCString { dst in renamex_np(src, dst, UInt32(RENAME_EXCL)) } }
            if result == 0 {
                lock.lock(); owned.remove(temporary.path); lock.unlock()
                return destination
            }
            let code = errno
            if code == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Could not publish export without replacing files: \(String(cString: strerror(code))). Choose another destination."])
        }
        throw MediaError.failed("Too many files share this export name. Choose another destination.")
    }
    public static func baseName(sourceURL: URL, cropped: Bool, trimmed: Bool, loopNumber: Int? = nil) -> String {
        let loopSuffix = loopNumber.map { " - loop \(String(format: "%02d", max(1, $0)))" } ?? ""
        return sourceURL.deletingPathExtension().lastPathComponent + loopSuffix + (cropped ? (trimmed ? " - trim crop" : " - crop") : " - trim")
    }
    public static func discard(temporaryURL: URL) {
        let path = temporaryURL.standardizedFileURL.path
        lock.lock(); let wasOwned = owned.remove(path) != nil; lock.unlock()
        if wasOwned { try? FileManager.default.removeItem(at: temporaryURL) }
    }
    private static func safeExtension(_ value: String) -> String {
        let clean = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return clean.isEmpty ? "mp4" : clean
    }
}
