import XCTest
@testable import CropTrimmer

final class OpenRouterKeyStoreTests: XCTestCase {
    func testSaveReadAndReplaceInIsolatedDefaults() throws {
        let suite = "com.croptrimmer.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(try OpenRouterKeyStore.read(defaults: defaults))
        try OpenRouterKeyStore.save(" test-key-one \n", defaults: defaults)
        XCTAssertEqual(try OpenRouterKeyStore.read(defaults: defaults), "test-key-one")
        try OpenRouterKeyStore.save("test-key-two", defaults: defaults)
        XCTAssertEqual(try OpenRouterKeyStore.read(defaults: defaults), "test-key-two")
        XCTAssertThrowsError(try OpenRouterKeyStore.save(" \n", defaults: defaults))
        XCTAssertEqual(try OpenRouterKeyStore.read(defaults: defaults), "test-key-two")
        OpenRouterKeyStore.clear(defaults: defaults)
        XCTAssertNil(try OpenRouterKeyStore.read(defaults: defaults))
    }
}
