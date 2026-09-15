import XCTest
@testable import CropTrimmer

final class ColorProviderCredentialsTests: XCTestCase {
    func testBlankPrimaryKeyFallsBackToTrimmedOpenRouterKey() {
        for primary in ["", " \n"] {
            let environment = ["CROPTRIMMER_COLOR_PROVIDER_API_KEY": primary,
                               "OPENROUTER_API_KEY": " test-router-key \n"]
            XCTAssertEqual(EditorModel.colorProviderAPIKey(environment: environment, isOpenRouter: true), "test-router-key")
            XCTAssertNil(EditorModel.colorProviderAPIKey(environment: environment, isOpenRouter: false))
        }
    }

    func testPrimaryKeyPrecedenceAndBlankCredentials() {
        XCTAssertEqual(EditorModel.colorProviderAPIKey(environment: [
            "CROPTRIMMER_COLOR_PROVIDER_API_KEY": " test-primary-key ",
            "OPENROUTER_API_KEY": "test-router-key"
        ], isOpenRouter: true), "test-primary-key")
        XCTAssertNil(EditorModel.colorProviderAPIKey(environment: ["OPENROUTER_API_KEY": " \n"], isOpenRouter: true))
        XCTAssertNil(EditorModel.colorProviderAPIKey(environment: [:], isOpenRouter: true))
    }
}
