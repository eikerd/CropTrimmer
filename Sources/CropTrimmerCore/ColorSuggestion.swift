import Foundation

public enum ColorSuggestionMode: String, Codable, Sendable {
    case automaticEnhancement
    case matchedPair
    case unrelatedReference
}

public struct ColorSuggestionRequest: Codable, Sendable {
    public let mode: ColorSuggestionMode
    public let samples: [ColorSample]
    public let referenceImage: Data?
    public let sourceID: String?
    public init(mode: ColorSuggestionMode, samples: [ColorSample] = [], referenceImage: Data? = nil, sourceID: String? = nil) {
        self.mode = mode; self.samples = samples; self.referenceImage = referenceImage; self.sourceID = sourceID
    }
}

public struct ColorSuggestionResult: Codable, Sendable {
    public let lut: ColorLUT?
    public let diagnostics: String
    public let meanError: Float?
    public init(lut: ColorLUT?, diagnostics: String, meanError: Float? = nil) {
        self.lut = lut; self.diagnostics = diagnostics; self.meanError = meanError
    }
}

public protocol ColorSuggestionProvider: Sendable {
    func suggest(_ request: ColorSuggestionRequest) async throws -> ColorSuggestionResult
}

public actor LocalColorSuggestionProvider: ColorSuggestionProvider {
    public init() {}
    public func suggest(_ request: ColorSuggestionRequest) async throws -> ColorSuggestionResult {
        guard request.mode == .matchedPair else {
            throw MediaError.unavailable("The local provider supports matched before/after frames only. An unrelated reference needs a reference-conditioned model.")
        }
        let fit = try ColorLUTFitter.fit(samples: request.samples)
        return ColorSuggestionResult(lut: fit.lut, diagnostics: "matched \(request.samples.count) corresponding color samples.", meanError: fit.meanError)
    }
}

/// Version-neutral HTTP adapter for a local LAN service or hosted API. The
/// service returns the same validated result consumed by the render pipeline.
public actor HTTPColorSuggestionProvider: ColorSuggestionProvider {
    private let endpoint: URL
    private let session: URLSession
    public init(endpoint: URL, session: URLSession = .shared) throws {
        let scheme = endpoint.scheme?.lowercased() ?? ""
        let host = endpoint.host?.lowercased() ?? ""
        guard scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw MediaError.invalid("Color provider endpoints must use HTTPS, except for localhost development services.")
        }
        self.endpoint = endpoint; self.session = session
    }

    public func suggest(_ request: ColorSuggestionRequest) async throws -> ColorSuggestionResult {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            var data = Data(); data.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                data.append(byte)
                if data.count > 32 * 1024 * 1024 { throw MediaError.failed("The color provider returned an oversized result.") }
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MediaError.unavailable("The color provider did not accept the request.")
            }
            do { return try JSONDecoder().decode(ColorSuggestionResult.self, from: data) }
            catch { throw MediaError.failed("The color provider returned an invalid result.") }
        } catch let error as MediaError { throw error }
        catch is CancellationError { throw MediaError.cancelled }
        catch { throw MediaError.unavailable("The color provider could not be reached.") }
    }
}
