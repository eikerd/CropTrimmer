import XCTest

/// The owner's floor: no text in the app renders below 12 pt. This scans the UI sources for the
/// ways it has slipped in: explicit point sizes (`.system`, `Font.system`, `.custom(_:size:)` and
/// AppKit's `NSFont.systemFont(ofSize:)`, wherever they are built), Apple's small text styles (caption, footnote and
/// subheadline are 10–11 pt on macOS), small and mini control sizes (11 and 9 pt), and shrink-to-fit.
/// The scan spans lines, so a modifier chain broken across lines is still seen. A point size set
/// directly on an `Image(systemName:)` is an icon, not text, and a control size set directly on a
/// `ProgressView()` sizes a spinner, not text; both are exempt — and nothing else around them is.
final class MinimumTextSizeTests: XCTestCase {
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    static let pointSize = regex(#"(?:\bFont)?\.(?:system\(\s*size:|custom\(\s*"[^"]*"\s*,\s*(?:fixedSize|size):)\s*(1[01]|[0-9])(\.[0-9]+)?\s*[,)]|\bNSFont\.(?:monospacedDigitS|s)ystemFont\(ofSize:\s*(1[01]|[0-9])(\.[0-9]+)?\s*[,)]"#)
    static let iconReceiver = regex(#"Image\(systemName: "[^"]*"\)\s*\.font\(\s*$"#)
    static let smallStyles = regex(#"\.font\(\s*\.(caption2?|footnote|subheadline)\b"#)
    static let miniControls = regex(#"\.controlSize\(\s*\.mini\s*\)"#)
    static let smallControls = regex(#"\.controlSize\(\s*\.small\s*\)"#)
    static let spinnerReceiver = regex(#"ProgressView\(\)\s*$"#)
    static let shrinkToFit = regex(#"\.minimumScaleFactor\("#)

    /// Every way the source puts text under 12 pt, with the line each starts on.
    static func violations(in text: String) -> [(line: Int, message: String)] {
        let whole = NSRange(text.startIndex..., in: text)
        func start(of match: NSTextCheckingResult) -> String.Index { Range(match.range, in: text)!.lowerBound }
        func line(of match: NSTextCheckingResult) -> Int { text[..<start(of: match)].filter { $0 == "\n" }.count + 1 }
        func receiver(before match: NSTextCheckingResult, is pattern: NSRegularExpression) -> Bool {
            let prefix = String(text[..<start(of: match)])
            return pattern.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)) != nil
        }
        var found: [(line: Int, message: String)] = []
        for match in pointSize.matches(in: text, range: whole) where !receiver(before: match, is: iconReceiver) {
            found.append((line(of: match), "text below 12 pt"))
        }
        for match in smallStyles.matches(in: text, range: whole) {
            found.append((line(of: match), "caption, footnote and subheadline are below 12 pt on macOS"))
        }
        for match in miniControls.matches(in: text, range: whole) { found.append((line(of: match), "mini controls render 9 pt text")) }
        for match in smallControls.matches(in: text, range: whole) where !receiver(before: match, is: spinnerReceiver) {
            found.append((line(of: match), "small controls render 11 pt text"))
        }
        for match in shrinkToFit.matches(in: text, range: whole) { found.append((line(of: match), "shrink-to-fit can drop text below 12 pt")) }
        return found.sorted { $0.line < $1.line }
    }

    func testNoUITextBelowTwelvePoints() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CropTrimmer").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for violation in Self.violations(in: text) { XCTFail("\(file.lastPathComponent):\(violation.line): \(violation.message)") }
        }
    }

    func testScanSeesChainsAcrossLinesAndExemptsOnlyIconsAndSpinners() {
        let messages = { (source: String) in Self.violations(in: source).map(\.message) }
        XCTAssertEqual(messages(#"Image(systemName: "film").font(.system(size: 9, weight: .bold))"#), [])
        XCTAssertEqual(messages("Image(systemName: \"film\")\n    .font(.system(size: 9))"), [])
        XCTAssertEqual(messages(#"HStack { Image(systemName: "film").font(.system(size: 9)); Text("A").font(.system(size: 10)) }"#), ["text below 12 pt"])
        XCTAssertEqual(messages("Text(\"A\")\n    .font(\n        .system(size: 10))"), ["text below 12 pt"])
        XCTAssertEqual(messages(#"Text("A").font(.system(size: 12))"#), [])
        XCTAssertEqual(messages(#"Text("A").font(.custom("AppFont", size: 10))"#), ["text below 12 pt"])
        XCTAssertEqual(messages(#"Text("A").font(.custom("AppFont", fixedSize: 11))"#), ["text below 12 pt"])
        XCTAssertEqual(messages(#"Text("A").font(Font.system(size: 10))"#), ["text below 12 pt"])
        XCTAssertEqual(messages(#"let small = Font.system(size: 9, weight: .bold)"#), ["text below 12 pt"])
        XCTAssertEqual(messages(#"field.font = NSFont.systemFont(ofSize: 10)"#), ["text below 12 pt"])
        XCTAssertEqual(messages(#"Text("A").font(.custom("AppFont", size: 14))"#), [])
        XCTAssertEqual(messages(#"Image(systemName: "film").font(Font.system(size: 9))"#), [])
        XCTAssertEqual(messages("ProgressView()\n    .controlSize(.small)"), [])
        XCTAssertEqual(messages(#"Text(x).font(.caption).controlSize(.small)"#).count, 2)
        XCTAssertEqual(Self.violations(in: "let a = 1\nText(\"A\")\n    .font(.caption)").first?.line, 3)
    }
}
