import XCTest
@testable import CropTrimmerCore

final class SavedLookTests: XCTestCase {
    func testLooksPersistApplyAsCopiesAndDeleteSafely() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-looks-" + UUID().uuidString)
        let store = SavedLookStore(directory: directory)
        let look = SavedLook(name: "Warm interview", color: ColorSettings(enabled: true, gamma: 1.2, saturation: 0.9))
        try await store.save(look)
        let loaded = try await store.looks()
        XCTAssertEqual(loaded, [look])
        var applied = try XCTUnwrap(loaded.first)
        applied.name = "Changed locally"
        XCTAssertNotEqual(try await store.look(id: look.id)?.name, applied.name)
        try await store.delete(id: look.id)
        XCTAssertTrue(try await store.looks().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCorruptLookIsRejectedWithoutHidingOtherLooks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-looks-" + UUID().uuidString)
        let store = SavedLookStore(directory: directory)
        try await store.save(SavedLook(name: "Good", color: ColorSettings()))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        do { _ = try await store.looks(); XCTFail("Corrupt look should be reported") } catch MediaError.invalid { }
        try? FileManager.default.removeItem(at: directory)
    }
}
