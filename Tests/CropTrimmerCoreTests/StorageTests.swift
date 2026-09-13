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
