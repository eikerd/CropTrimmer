import XCTest
@testable import CropTrimmerCore

final class ColorCorrectionTests: XCTestCase {
    func testDefaultsAreAnIdentityCorrection() {
        let settings = ColorSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.blackPoint, 0)
        XCTAssertEqual(settings.whitePoint, 1)
        XCTAssertEqual(settings.gamma, 1)
        XCTAssertEqual(settings.saturation, 1)
        XCTAssertTrue(settings.isIdentity)
        XCTAssertEqual(settings.apply(to: SIMD3<Float>(0.2, 0.4, 0.8)), SIMD3<Float>(0.2, 0.4, 0.8))
    }

    func testLevelsGammaAndSaturationUseDocumentedOrder() throws {
        var settings = ColorSettings(enabled: true, blackPoint: 0.1, whitePoint: 0.9, gamma: 2, saturation: 0)
        let result = settings.apply(to: SIMD3<Float>(0.5, 0.5, 0.5))
        XCTAssertEqual(result.x, powf(0.5, 0.5), accuracy: 0.0001)
        XCTAssertEqual(result.x, result.y, accuracy: 0.0001)
        XCTAssertEqual(result.y, result.z, accuracy: 0.0001)
        settings.gamma = 1
        settings.saturation = 1
        XCTAssertEqual(settings.apply(to: SIMD3<Float>(0.1, 0.5, 0.9)).x, 0, accuracy: 0.0001)
        XCTAssertEqual(settings.apply(to: SIMD3<Float>(0.1, 0.5, 0.9)).z, 1, accuracy: 0.0001)
    }

    func testValidationRejectsNonFiniteAndCrossedEndpoints() {
        var settings = ColorSettings(enabled: true)
        XCTAssertNoThrow(try settings.validate())
        settings.blackPoint = .nan
        XCTAssertThrowsError(try settings.validate())
        settings.blackPoint = 0.8
        settings.whitePoint = 0.2
        XCTAssertThrowsError(try settings.validate())
        settings.blackPoint = 0
        settings.whitePoint = 1
        settings.gamma = 0
        XCTAssertThrowsError(try settings.validate())
    }

    func testEditSettingsDecodeWithoutColorUsesIdentityDefaults() throws {
        let legacy = #"{"start":0,"end":3,"cropAspectRatio":null,"lastLockedCropAspectRatio":null,"cropEnabled":false,"crop":{"x":0,"y":0,"width":640,"height":360},"method":"Automatic","quality":"Balanced"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EditSettings.self, from: legacy)
        XCTAssertEqual(decoded.duration, 3)
        XCTAssertEqual(decoded.color, ColorSettings())
    }
}
