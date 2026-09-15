import Foundation

public enum ColorSuggestionMode: String, Codable, Sendable {
    case automaticEnhancement
    case matchedPair
    case unrelatedReference
}

public struct ColorSuggestionRequest: Codable, Sendable {
    public let mode: ColorSuggestionMode
    public let samples: [ColorSample]
    public let sourceImage: Data?
    public let referenceImage: Data?
    public let sourceID: String?
    public init(mode: ColorSuggestionMode, samples: [ColorSample] = [], sourceImage: Data? = nil, referenceImage: Data? = nil, sourceID: String? = nil) {
        self.mode = mode; self.samples = samples; self.sourceImage = sourceImage; self.referenceImage = referenceImage; self.sourceID = sourceID
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

/// Adapter for vision models that implement OpenAI chat completions. It works
/// with OpenRouter and local OpenAI-compatible servers such as llama-server.
/// The model returns four bounded display adjustments; Crop Trimmer compiles
/// them into its own validated LUT before use.
public actor OpenAICompatibleColorSuggestionProvider: ColorSuggestionProvider {
    public struct Configuration: Sendable {
        public let endpoint: URL
        public let model: String
        /// Keep this in the process environment or a secret store. It is never persisted.
        public let apiKey: String?
        public let timeout: TimeInterval

        public init(endpoint: URL, model: String, apiKey: String? = nil, timeout: TimeInterval = 120) throws {
            let scheme = endpoint.scheme?.lowercased() ?? ""
            let host = endpoint.host?.lowercased() ?? ""
            guard scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
                throw MediaError.invalid("Color provider endpoints must use HTTPS, except for localhost development services.")
            }
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MediaError.invalid("A color model name is required.")
            }
            guard timeout.isFinite, timeout > 0, timeout <= 600 else {
                throw MediaError.invalid("The color provider timeout is invalid.")
            }
            self.endpoint = endpoint
            self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : apiKey
            self.timeout = timeout
        }
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    private struct Content: Encodable {
        let type: String
        let text: String?
        let imageURL: ImageURL?

        static func text(_ value: String) -> Content { Content(type: "text", text: value, imageURL: nil) }
        static func image(_ value: String) -> Content { Content(type: "image_url", text: nil, imageURL: ImageURL(url: value)) }

        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    }

    private struct ImageURL: Encodable { let url: String }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: AssistantContent }
            let message: Message
        }
        let choices: [Choice]
    }

    private enum AssistantContent: Decodable {
        case text(String)
        case parts([Part])

        struct Part: Decodable { let text: String? }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(value)
            } else {
                self = .parts(try decoder.singleValueContainer().decode([Part].self))
            }
        }

        var textValue: String {
            switch self {
            case .text(let value): return value
            case .parts(let parts): return parts.compactMap(\.text).joined()
            }
        }
    }

    /// The compact contract sent to a vision model. Values use the same ranges
    /// as `ColorSettings`, so hallucinated or unsafe proposals are rejected.
    public struct ColorAdjustmentProposal: Codable, Equatable, Sendable {
        public let blackPoint: Float
        public let whitePoint: Float
        public let gamma: Float
        public let saturation: Float

        public init(blackPoint: Float, whitePoint: Float, gamma: Float, saturation: Float) {
            self.blackPoint = blackPoint; self.whitePoint = whitePoint; self.gamma = gamma; self.saturation = saturation
        }

        public func colorSettings() throws -> ColorSettings {
            let settings = ColorSettings(enabled: true, blackPoint: blackPoint, whitePoint: whitePoint, gamma: gamma, saturation: saturation)
            try settings.validate()
            return settings
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration; self.session = session
    }

    public func suggest(_ request: ColorSuggestionRequest) async throws -> ColorSuggestionResult {
        guard request.mode == .unrelatedReference else {
            throw MediaError.invalid("The vision color provider is intended for an unrelated reference image.")
        }
        guard let source = request.sourceImage, let reference = request.referenceImage else {
            throw MediaError.invalid("A source frame and reference image are required for a vision color suggestion.")
        }
        guard source.count <= 16 * 1024 * 1024, reference.count <= 16 * 1024 * 1024,
              source.count + reference.count <= 24 * 1024 * 1024 else {
            throw MediaError.failed("The images are too large for a color provider request.")
        }

        let instruction = """
        You are a conservative colorist. Compare the SOURCE frame to the REFERENCE image and return only one JSON object with these numeric keys: blackPoint, whitePoint, gamma, saturation. Use normalized values: blackPoint and whitePoint from 0 to 1 with whitePoint at least 1/255 above blackPoint, gamma from 0.25 to 4 where values above 1 lift midtones, and saturation from 0 to 2 where 1 is unchanged. Correct exposure and neutral color balance conservatively; do not crop, sharpen, invent detail, or describe the images. Return no markdown and no extra keys.
        """
        let payload = Request(model: configuration.model, messages: [Message(role: "user", content: [
            .text(instruction), .text("SOURCE frame:"), .image(Self.dataURL(for: source)),
            .text("REFERENCE image:"), .image(Self.dataURL(for: reference))
        ])], temperature: 0)
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = configuration.apiKey { urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            var data = Data(); data.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                data.append(byte)
                if data.count > 2 * 1024 * 1024 { throw MediaError.failed("The color model returned an oversized result.") }
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MediaError.unavailable("The color model did not accept the request.")
            }
            let decoded: Response
            do { decoded = try JSONDecoder().decode(Response.self, from: data) }
            catch { throw MediaError.failed("The color model returned an invalid response.") }
            guard let choice = decoded.choices.first else { throw MediaError.failed("The color model returned no suggestion.") }
            let proposal = try Self.parseProposal(choice.message.content.textValue)
            let lut = try ColorLUT.compile(settings: proposal.colorSettings())
            return ColorSuggestionResult(lut: lut, diagnostics: "vision model \(configuration.model) proposed bounded levels, gamma, and saturation adjustments.")
        } catch let error as MediaError { throw error }
        catch is CancellationError { throw MediaError.cancelled }
        catch { throw MediaError.unavailable("The color model could not be reached.") }
    }

    public static func parseProposal(_ text: String) throws -> ColorAdjustmentProposal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end else {
            throw MediaError.failed("The color model did not return a JSON color adjustment.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let proposal = try decoder.decode(ColorAdjustmentProposal.self, from: Data(trimmed[start...end].utf8))
            _ = try proposal.colorSettings()
            return proposal
        } catch let error as MediaError { throw error }
        catch { throw MediaError.failed("The color model returned an invalid color adjustment.") }
    }

    private static func dataURL(for data: Data) -> String {
        let mime: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { mime = "image/png" }
        else if data.starts(with: [0xFF, 0xD8, 0xFF]) { mime = "image/jpeg" }
        else { mime = "application/octet-stream" }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
