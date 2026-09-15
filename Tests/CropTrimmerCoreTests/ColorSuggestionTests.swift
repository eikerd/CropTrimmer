import XCTest
@testable import CropTrimmerCore

final class ColorSuggestionTests: XCTestCase {
    func testLocalProviderReturnsAValidatedMatchedPairCandidate() async throws {
        let samples = [
            ColorSample(source: SIMD3<Float>(0, 0, 0), target: SIMD3<Float>(0.1, 0.1, 0.1)),
            ColorSample(source: SIMD3<Float>(1, 1, 1), target: SIMD3<Float>(0.9, 0.9, 0.9)),
            ColorSample(source: SIMD3<Float>(1, 0, 0), target: SIMD3<Float>(0.9, 0.1, 0.1)),
            ColorSample(source: SIMD3<Float>(0, 1, 0), target: SIMD3<Float>(0.1, 0.9, 0.1)),
            ColorSample(source: SIMD3<Float>(0, 0, 1), target: SIMD3<Float>(0.1, 0.1, 0.9))
        ]
        let result = try await LocalColorSuggestionProvider().suggest(ColorSuggestionRequest(mode: .matchedPair, samples: samples))
        XCTAssertNotNil(result.lut)
        XCTAssertTrue(result.diagnostics.contains("matched"))
    }

    func testLocalProviderDoesNotPretendToHandleUnrelatedReferences() async throws {
        do {
            _ = try await LocalColorSuggestionProvider().suggest(ColorSuggestionRequest(mode: .unrelatedReference))
            XCTFail("Unrelated reference requires a reference-conditioned model")
        } catch MediaError.unavailable { }
    }

    func testHTTPProviderRequiresHTTPSOutsideLoopback() throws {
        XCTAssertThrowsError(try HTTPColorSuggestionProvider(endpoint: URL(string: "http://example.com/color")!))
        XCTAssertNoThrow(try HTTPColorSuggestionProvider(endpoint: URL(string: "http://127.0.0.1:8080/color")!))
        XCTAssertNoThrow(try HTTPColorSuggestionProvider(endpoint: URL(string: "https://example.com/color")!))
    }
}
