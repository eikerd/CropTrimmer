import XCTest
@testable import CropTrimmerCore

final class SavedLookTests: XCTestCase {
    func testLooksPersistApplyAsCopiesAndDeleteSafely() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-looks-" + UUID().uuidString)
        let store = SavedLookStore(directory: directory)
        let look = SavedLook(name: "Warm interview", color: ColorSettings(enabled: true, gamma: 1.2, saturation: 0.9))
        try await store.save(look)
        let loaded = try await store.looks()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, look.id)
        XCTAssertEqual(loaded.first?.name, look.name)
        XCTAssertEqual(loaded.first?.color, look.color)
        var applied = try XCTUnwrap(loaded.first)
        applied.name = "Changed locally"
        let storedName = try await store.look(id: look.id)?.name
        XCTAssertNotEqual(storedName, applied.name)
        try await store.delete(id: look.id)
        let remaining = try await store.looks()
        XCTAssertTrue(remaining.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCorruptLookIsRejectedWithoutHidingOtherLooks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-looks-" + UUID().uuidString)
        let store = SavedLookStore(directory: directory)
        try await store.save(SavedLook(name: "Good", color: ColorSettings()))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = try await store.looks()
        XCTAssertEqual(loaded.map(\.name), ["Good"])
        let errors = await store.lastLoadErrors()
        XCTAssertEqual(errors.count, 1)
        try? FileManager.default.removeItem(at: directory)
    }
}
