import XCTest
@testable import CropTrimmerCore

final class SourceRenamerTests: XCTestCase {
    func testRenamePreservesContentsExtensionAndIdentityWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("An extremely long movie name.MOV")
        let data = Data("movie contents".utf8)
        try data.write(to: original)
        let identity = try SourceIdentity(url: original)
        let renamed = try SourceRenamer.rename(sourceURL: original, identity: identity, baseName: "  Short  ")
        XCTAssertEqual(renamed.lastPathComponent, "Short.MOV")
        XCTAssertEqual(try Data(contentsOf: renamed), data)
        XCTAssertEqual(try SourceIdentity(url: renamed), identity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try SourceRenamer.rename(sourceURL: renamed, identity: identity, baseName: "Short"), renamed)
        let occupied = directory.appendingPathComponent("Taken.MOV")
        try Data("keep".utf8).write(to: occupied)
        XCTAssertThrowsError(try SourceRenamer.rename(sourceURL: renamed, identity: identity, baseName: "Taken"))
        XCTAssertEqual(try Data(contentsOf: occupied), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: renamed), data)
        for invalid in ["", "  ", "../outside", "a/b", "a:b", ".hidden", "a\u{0}b", "a\nb"] {
            XCTAssertThrowsError(try SourceRenamer.rename(sourceURL: renamed, identity: identity, baseName: invalid))
        }
        let link = directory.appendingPathComponent("Link.MOV")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: renamed)
        XCTAssertThrowsError(try SourceRenamer.rename(sourceURL: link, identity: identity, baseName: "Moved link"))
        try Data("changed contents".utf8).write(to: renamed)
        XCTAssertThrowsError(try SourceRenamer.rename(sourceURL: renamed, identity: identity, baseName: "Changed"))
    }
}
