import XCTest

/// The owner's floor: no text in the app renders below 12 pt. This scans the UI sources for the
/// ways it has slipped in: explicit point sizes, Apple's small text styles (caption, footnote and
/// subheadline are 10–11 pt on macOS), small and mini control sizes (11 and 9 pt), and shrink-to-fit.
/// A point size set directly on an `Image(systemName:)` is an icon, not text, and progress spinners
/// are not text either; both are exempt — and nothing else on the same line is.
final class MinimumTextSizeTests: XCTestCase {
    static let pointSize = try! NSRegularExpression(pattern: #"\.font\(\.system\(size: (1[01]|[0-9])(\.[0-9]+)?[,)]"#)
    static let iconReceiver = try! NSRegularExpression(pattern: #"Image\(systemName: "[^"]*"\)$"#)
    static let smallStyles = try! NSRegularExpression(pattern: #"\.font\(\.(caption2?|footnote|subheadline)\b"#)

    /// Every way one source line puts text under 12 pt, as messages; empty when the line is clean.
    static func violations(in line: String) -> [String] {
        var found: [String] = []
        let whole = NSRange(line.startIndex..., in: line)
        for match in pointSize.matches(in: line, range: whole) {
            let prefix = String(line[..<Range(match.range, in: line)!.lowerBound])
            let onIcon = iconReceiver.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)) != nil
            if !onIcon { found.append("text below 12 pt") }
        }
        if smallStyles.firstMatch(in: line, range: whole) != nil { found.append("caption, footnote and subheadline are below 12 pt on macOS") }
        if line.contains("controlSize(.mini)") { found.append("mini controls render 9 pt text") }
        if line.contains("controlSize(.small)") && !line.contains("ProgressView") { found.append("small controls render 11 pt text") }
        if line.contains("minimumScaleFactor(") { found.append("shrink-to-fit can drop text below 12 pt") }
        return found
    }

    func testNoUITextBelowTwelvePoints() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CropTrimmer").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                for problem in Self.violations(in: line) { XCTFail("\(file.lastPathComponent):\(number + 1): \(problem)") }
            }
        }
    }

    func testIconExemptionDoesNotCoverTextOnTheSameLine() {
        XCTAssertEqual(Self.violations(in: #"Image(systemName: "film").font(.system(size: 9, weight: .bold))"#), [])
        XCTAssertEqual(Self.violations(in: #"HStack { Image(systemName: "film").font(.system(size: 9)); Text("A").font(.system(size: 10)) }"#), ["text below 12 pt"])
        XCTAssertEqual(Self.violations(in: #"Text("A").font(.system(size: 12))"#), [])
        XCTAssertEqual(Self.violations(in: #"Text(x).font(.caption).controlSize(.small)"#).count, 2)
    }
}
