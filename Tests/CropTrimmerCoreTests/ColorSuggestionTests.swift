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

    func testReferenceProviderRequestCarriesSourceAndReferenceImages() throws {
        let request = ColorSuggestionRequest(mode: .unrelatedReference, sourceImage: Data([1, 2]), referenceImage: Data([3, 4]), sourceID: "source")
        let decoded = try JSONDecoder().decode(ColorSuggestionRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.sourceImage, Data([1, 2]))
        XCTAssertEqual(decoded.referenceImage, Data([3, 4]))
        XCTAssertEqual(decoded.sourceID, "source")
    }

    func testOpenAICompatibleProviderParsesConservativeProposal() throws {
        let proposal = try OpenAICompatibleColorSuggestionProvider.parseProposal("```json\n{\"black_point\":0.04,\"whitePoint\":0.96,\"gamma\":1.1,\"saturation\":1.05}\n```")
        XCTAssertEqual(proposal.blackPoint, 0.04, accuracy: 0.0001)
        XCTAssertEqual(proposal.whitePoint, 0.96, accuracy: 0.0001)
        XCTAssertEqual(proposal.gamma, 1.1, accuracy: 0.0001)
        XCTAssertEqual(proposal.saturation, 1.05, accuracy: 0.0001)
        XCTAssertNoThrow(try proposal.colorSettings())
    }

    func testOpenAICompatibleProviderRejectsUnsafeProposal() throws {
        XCTAssertThrowsError(try OpenAICompatibleColorSuggestionProvider.parseProposal("{\"blackPoint\":0.8,\"whitePoint\":0.2,\"gamma\":1,\"saturation\":1}")) { error in
            guard case MediaError.invalid = error else { return XCTFail("Expected invalid color settings, got \(error)") }
        }
    }

    func testOpenAICompatibleConfigurationUsesHTTPSOrLoopbackAndRequiresModel() throws {
        XCTAssertNoThrow(try OpenAICompatibleColorSuggestionProvider.Configuration(endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, model: "qwen/qwen2.5-vl-7b-instruct"))
        XCTAssertNoThrow(try OpenAICompatibleColorSuggestionProvider.Configuration(endpoint: URL(string: "http://127.0.0.1:8080/v1/chat/completions")!, model: "local-vision"))
        XCTAssertThrowsError(try OpenAICompatibleColorSuggestionProvider.Configuration(endpoint: URL(string: "http://example.com/v1/chat/completions")!, model: "local-vision"))
        XCTAssertThrowsError(try OpenAICompatibleColorSuggestionProvider.Configuration(endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, model: "  "))
    }
}
