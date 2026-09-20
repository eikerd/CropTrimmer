import XCTest
@testable import CropTrimmerCore

final class FilenameSuggestionTests: XCTestCase {
    func testAuthenticationAndBillingErrorsAreDistinct() {
        XCTAssertTrue(FilenameVisionProvider.requestError(statusCode: 401).localizedDescription.contains("API key"))
        XCTAssertTrue(FilenameVisionProvider.requestError(statusCode: 402).localizedDescription.contains("credits"))
        XCTAssertTrue(FilenameVisionProvider.requestError(statusCode: 429).localizedDescription.contains("rate limiting"))
    }
    func testRandomNamesAreSafeAndDistinct() {
        let names = (0..<100).map { _ in FilenameSuggestion.random() }
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertNotNil(name.range(of: "^[a-z]+-[a-z]+-[0-9a-f]{8}$", options: .regularExpression))
        }
    }

    func testDescriptionBecomesBoundedFilename() throws {
        XCTAssertEqual(try FilenameSuggestion.parse("{\"name\":\" Person walking on a beach \"}"), "person-walking-on-a-beach")
        let payload = try JSONSerialization.data(withJSONObject: ["name": String(repeating: "A", count: 300)])
        XCTAssertEqual(try FilenameSuggestion.parse(String(decoding: payload, as: UTF8.self)).count, 80)
    }

    func testUnsafeAndMalformedSuggestionsAreRejected() {
        for name in ["../movie", "path/name", "path\\name", "a:b", "a\nb", "...", "", "🌞"] {
            let data = try! JSONSerialization.data(withJSONObject: ["name": name])
            XCTAssertThrowsError(try FilenameSuggestion.parse(String(decoding: data, as: UTF8.self)))
        }
        XCTAssertThrowsError(try FilenameSuggestion.parse("not json"))
        XCTAssertThrowsError(try FilenameSuggestion.parse("{\"name\":42}"))
    }

    func testProviderSendsOneImageAndParsesSuggestion() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FilenameProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let name = try await FilenameVisionProvider(session: session).suggest(
            framePNG: Data([137,80,78,71]), model: "test-model", apiKey: "test-key")
        XCTAssertEqual(name, "dog-running-in-park")
    }

    func testMissingCredentialsAndOversizedFramesFailBeforeNetwork() async {
        for (data, key) in [(Data([1]), " "), (Data(count: 2 * 1024 * 1024 + 1), "test-key")] {
            do {
                _ = try await FilenameVisionProvider().suggest(framePNG: data, model: "test", apiKey: key)
                XCTFail("Invalid request should not succeed")
            } catch { }
        }
    }
}

private final class FilenameProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.httpMethod, "POST")
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "test-model")
        let messages = json?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.filter { $0["type"] as? String == "image_url" }.count, 1)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "{\"name\":\"dog running in park\"}"]]]])
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
