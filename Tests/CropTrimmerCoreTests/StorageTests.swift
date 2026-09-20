import XCTest
@testable import CropTrimmerCore

final class StorageTests: XCTestCase {
    func testConcurrentPublicationNeverOverwrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Movie.mov")
        let existing = directory.appendingPathComponent("Movie - trim.mp4")
        try Data("original".utf8).write(to: source)
        try Data("keep me".utf8).write(to: existing)
        let outputs = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
            for index in 0..<12 {
                group.addTask {
                    let temporary = OutputPublisher.temporaryURL(in: directory, extension: "mp4")
                    try Data("result \(index)".utf8).write(to: temporary)
                    return try OutputPublisher.publish(temporaryURL: temporary, sourceURL: source, cropped: false, directory: directory, extension: "mp4")
                }
            }
            var result: [URL] = []
            for try await url in group { result.append(url) }
            return result
        }
        XCTAssertEqual(Set(outputs).count, 12)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep me")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }
    func testOperationSuffixes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (cropped, trimmed, expected) in [(true, true, "Movie - trim crop.mp4"), (true, false, "Movie - crop.mp4"), (false, true, "Movie - trim.mp4")] {
            let temporary = OutputPublisher.temporaryURL(in: directory, extension: "mp4")
            try Data("movie".utf8).write(to: temporary)
            let output = try OutputPublisher.publish(temporaryURL: temporary, sourceURL: directory.appendingPathComponent("Movie.mov"), cropped: cropped, trimmed: trimmed, directory: directory, extension: "mp4")
            XCTAssertEqual(output.lastPathComponent, expected)
        }
    }
    func testSequentialLoopNamesAndRepeatedExportKeepExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var outputs: [URL] = []
        for number in [1, 2, 3, 1] {
            let temporary = OutputPublisher.temporaryURL(in: directory, extension: "mp4")
            try Data("movie".utf8).write(to: temporary)
            outputs.append(try OutputPublisher.publish(temporaryURL: temporary, sourceURL: directory.appendingPathComponent("Movie.mov"), cropped: false, directory: directory, extension: "mp4", loopNumber: number))
        }
        XCTAssertEqual(outputs.map(\.lastPathComponent), ["Movie - loop 01 - trim.mp4", "Movie - loop 02 - trim.mp4", "Movie - loop 03 - trim.mp4", "Movie - loop 01 - trim 2.mp4"])
        XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testRejectsUnownedTemporary() throws {
        let directory = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try OutputPublisher.publish(temporaryURL: directory.appendingPathComponent("unowned.mp4"), sourceURL: directory.appendingPathComponent("source.mov"), cropped: true, directory: directory, extension: "mp4"))
    }
}

final class FilenameOptionsTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/tmp/Clip.mp4")

    func testStandardOptionsKeepTheNamesTheAppAlwaysProduced() {
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: true, loopNumber: 1), "Clip - loop 01 - trim crop")
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: false, trimmed: true, loopNumber: 12), "Clip - loop 12 - trim")
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: false), "Clip - crop")
    }

    func testEachOperationCanBeLeftOutOfTheName() {
        var options = FilenameOptions(includeLoopNumber: false, includeCrop: true, includeTrim: true)
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: true, loopNumber: 3, options: options), "Clip - trim crop")
        options = FilenameOptions(includeLoopNumber: true, includeCrop: false, includeTrim: true)
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: true, loopNumber: 3, options: options), "Clip - loop 03 - trim")
        options = FilenameOptions(includeLoopNumber: true, includeCrop: true, includeTrim: false)
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: true, loopNumber: 3, options: options), "Clip - loop 03 - crop")
        options = FilenameOptions(includeLoopNumber: false, includeCrop: false, includeTrim: false)
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: true, trimmed: true, loopNumber: 3, options: options), "Clip",
                       "With every part switched off the export takes the source's own name; uniquing keeps it from replacing it")
    }

    func testSpeedJoinsTheNameOnlyWhenAskedForAndOnlyWhenItIsNotNormal() {
        let options = FilenameOptions(includeSpeed: true)
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: false, trimmed: true, loopNumber: 1, speed: 0.5, options: options), "Clip - loop 01 - trim - 0.5x")
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: false, trimmed: true, loopNumber: 1, speed: 8, options: options), "Clip - loop 01 - trim - 8x")
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: false, trimmed: true, loopNumber: 1, speed: 1, options: options), "Clip - loop 01 - trim")
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: source, cropped: false, trimmed: true, loopNumber: 1, speed: 0.5), "Clip - loop 01 - trim",
                       "Speed stays out of the name unless the preference asks for it")
    }

    func testOptionsSurviveAStoreAndReload() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CropTrimmer.filename.\(UUID().uuidString)"))
        XCTAssertEqual(FilenameOptions.load(from: defaults), .standard)
        FilenameOptions(includeLoopNumber: false, includeCrop: true, includeTrim: false, includeSpeed: true).save(to: defaults)
        let restored = FilenameOptions.load(from: defaults)
        XCTAssertFalse(restored.includeLoopNumber); XCTAssertTrue(restored.includeSpeed); XCTAssertFalse(restored.includeTrim)
    }
}

final class OutputPublisherOwnershipTests: XCTestCase {
    /// `standardizedFileURL` strips a `/private` prefix only once the file exists, so a temporary
    /// registered before the encode was looked up under a different spelling after it. Every
    /// export into /private/tmp or /private/var failed with "does not belong to this job or
    /// destination" and left its temporary behind, because `discard` missed it for the same reason.
    func testPublishAcceptsATemporaryWhoseSpellingChangedOnceItExisted() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/CropTrimmer-ownership-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Clip.mp4")
        try Data("source".utf8).write(to: source)

        let temporary = OutputPublisher.temporaryURL(in: directory, extension: "mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path), "Registered before the file exists")
        try Data("export".utf8).write(to: temporary)

        let published = try OutputPublisher.publish(temporaryURL: temporary, sourceURL: source, cropped: false,
                                                   trimmed: true, directory: directory, extension: "mp4", loopNumber: 1)
        XCTAssertEqual(published.lastPathComponent, "Clip - loop 01 - trim.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: published.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path), "The temporary was moved, not copied")
    }

    /// The same mismatch made `discard` silently keep the file instead of cleaning it up.
    func testDiscardRemovesATemporaryUnderPrivate() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/CropTrimmer-discard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = OutputPublisher.temporaryURL(in: directory, extension: "mp4")
        try Data("export".utf8).write(to: temporary)
        OutputPublisher.discard(temporaryURL: temporary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    /// A path this process never issued is still refused, which is the point of the check.
    func testPublishStillRefusesAFileItNeverIssued() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/CropTrimmer-foreign-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Clip.mp4")
        try Data("source".utf8).write(to: source)
        let foreign = directory.appendingPathComponent("not-ours.mp4")
        try Data("export".utf8).write(to: foreign)
        XCTAssertThrowsError(try OutputPublisher.publish(temporaryURL: foreign, sourceURL: source, cropped: false,
                                                        trimmed: true, directory: directory, extension: "mp4"))
    }
}
