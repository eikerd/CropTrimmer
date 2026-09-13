import Foundation
import Darwin

/// Changes only the source's filename, preserving its extension and directory.
public enum SourceRenamer {
    public static func rename(sourceURL: URL, identity: SourceIdentity, baseName: String) throws -> URL {
        let name = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."),
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              !name.contains("/"), !name.contains(":") else {
            throw MediaError.invalid("Enter a filename without slashes, colons, control characters, or a leading dot.")
        }
        let source = sourceURL.standardizedFileURL
        guard source.isFileURL else { throw MediaError.invalid("Only local movie files can be renamed.") }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw MediaError.invalid("Rename the original movie file, rather than a symbolic link.")
        }
        guard try SourceIdentity(url: source) == identity else { throw MediaError.sourceChanged }
        var destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if !source.pathExtension.isEmpty { destination = destination.appendingPathExtension(source.pathExtension) }
        if destination.path == source.path { return source }
        let result = source.path.withCString { src in
            destination.path.withCString { dst in renamex_np(src, dst, UInt32(RENAME_EXCL)) }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw MediaError.invalid("A file with that name already exists. Choose another name.") }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Could not rename the movie: \(String(cString: strerror(code)))."])
        }
        return destination
    }
}
