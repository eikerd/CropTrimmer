import XCTest
import Security
@testable import CropTrimmer

final class OpenRouterKeyStoreTests: XCTestCase {
    func testSaveReadAndReplaceInIsolatedKeychainItem() throws {
        let service = "com.croptrimmer.tests.\(UUID().uuidString)"
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service] as CFDictionary)
        }
        XCTAssertNil(try OpenRouterKeyStore.read(service: service))
        try OpenRouterKeyStore.save(" test-key-one \n", service: service)
        XCTAssertEqual(try OpenRouterKeyStore.read(service: service), "test-key-one")
        try OpenRouterKeyStore.save("test-key-two", service: service)
        XCTAssertEqual(try OpenRouterKeyStore.read(service: service), "test-key-two")
        XCTAssertThrowsError(try OpenRouterKeyStore.save(" \n", service: service))
        XCTAssertEqual(try OpenRouterKeyStore.read(service: service), "test-key-two")
    }
}
