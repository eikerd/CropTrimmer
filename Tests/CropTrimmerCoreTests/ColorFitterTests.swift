import XCTest
import simd
@testable import CropTrimmerCore

final class ColorFitterTests: XCTestCase {
    func testFitterRecoversAKnownGlobalTransformOnHeldOutSamples() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.1, 0.2, 0.8), SIMD3(0.3, 0.7, 0.2),
            SIMD3(0.8, 0.25, 0.4), SIMD3(0.4, 0.6, 0.9), SIMD3(0.15, 0.85, 0.55)
        ]
        let transform: (SIMD3<Float>) -> SIMD3<Float> = { value in
            SIMD3(min(1, value.x * 0.85 + 0.06), min(1, value.y * 0.9 + 0.03), min(1, value.z * 0.75 + 0.1))
        }
        let samples = points.map { ColorSample(source: $0, target: transform($0)) }
        let result = try ColorLUTFitter.fit(samples: samples, gridSize: 9)
        XCTAssertLessThan(result.meanError, 0.08)
        let heldOut = SIMD3<Float>(0.52, 0.48, 0.64)
        let error = distance(result.lut.sample(heldOut), transform(heldOut))
        XCTAssertLessThan(error, 0.12)
    }

    func testFitterRejectsInsufficientOrNonFiniteSamples() {
        XCTAssertThrowsError(try ColorLUTFitter.fit(samples: [], gridSize: 9))
        XCTAssertThrowsError(try ColorLUTFitter.fit(samples: [ColorSample(source: SIMD3<Float>(repeating: .nan), target: SIMD3<Float>(repeating: 0))], gridSize: 9))
    }
}
