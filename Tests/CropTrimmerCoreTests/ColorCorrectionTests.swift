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

    func testCompiledLUTSamplesIdentityAndManualTransform() throws {
        let identity = try ColorLUT.compile(settings: ColorSettings(), size: 3)
        XCTAssertEqual(identity.size, 3)
        let identitySample = identity.sample(SIMD3<Float>(0.2, 0.4, 0.8))
        XCTAssertEqual(identitySample.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(identitySample.y, 0.4, accuracy: 0.0001)
        XCTAssertEqual(identitySample.z, 0.8, accuracy: 0.0001)

        let manual = try ColorLUT.compile(settings: ColorSettings(enabled: true, gamma: 2), size: 17)
        let sampled = manual.sample(SIMD3<Float>(0.5, 0.5, 0.5))
        XCTAssertEqual(sampled.x, sqrtf(0.5), accuracy: 0.01)
        XCTAssertEqual(sampled.y, sampled.x, accuracy: 0.0001)
    }

    func testLUTRejectsInvalidShapeAndSamplesClampedCoordinates() throws {
        XCTAssertThrowsError(try ColorLUT(size: 1, values: [0, 0, 0]))
        let lut = try ColorLUT(size: 2, values: [
            0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0,
            0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1
        ])
        let clamped = lut.sample(SIMD3<Float>(-1, 2, 0.5))
        XCTAssertEqual(clamped.x, 0, accuracy: 0.0001)
        XCTAssertEqual(clamped.y, 1, accuracy: 0.0001)
        XCTAssertEqual(clamped.z, 0.5, accuracy: 0.0001)
    }

    func testCubeSerializationRoundTripsSemanticTable() throws {
        let lut = try ColorLUT.compile(settings: ColorSettings(enabled: true, gamma: 1.4), size: 3)
        let decoded = try ColorLUT(cubeText: lut.cubeText)
        XCTAssertEqual(decoded.size, lut.size)
        XCTAssertEqual(decoded.values, lut.values)
        XCTAssertEqual(decoded.colorSpace, "sRGB")
    }

    func testCubeParserRejectsUnsupportedOrTruncatedTables() {
        XCTAssertThrowsError(try ColorLUT(cubeText: "LUT_1D_SIZE 16\n"))
        XCTAssertThrowsError(try ColorLUT(cubeText: "LUT_3D_SIZE 2\n0 0 0\n"))
    }
}
