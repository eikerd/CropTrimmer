import XCTest

/// The owner's floor: no text in the app renders below 12 pt. This scans the UI sources for the
/// ways it has slipped in: explicit point sizes, Apple's small text styles (caption, footnote and
/// subheadline are 10–11 pt on macOS), small and mini control sizes (11 and 9 pt), and shrink-to-fit.
/// Icons (`Image(systemName:)`) and progress spinners are not text and are exempt.
final class MinimumTextSizeTests: XCTestCase {
    func testNoUITextBelowTwelvePoints() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CropTrimmer").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let pointSize = try NSRegularExpression(pattern: #"\.font\(\.system\(size: (1[01]|[0-9])(\.[0-9]+)?[,)]"#)
        let smallStyles = try NSRegularExpression(pattern: #"\.font\(\.(caption2?|footnote|subheadline)\b"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let where_ = "\(file.lastPathComponent):\(number + 1)"
                let range = NSRange(line.startIndex..., in: line)
                if !line.contains("Image(systemName") {
                    XCTAssertNil(pointSize.firstMatch(in: line, range: range), "\(where_): text below 12 pt")
                }
                XCTAssertNil(smallStyles.firstMatch(in: line, range: range), "\(where_): caption, footnote and subheadline are below 12 pt on macOS")
                XCTAssertFalse(line.contains("controlSize(.mini)"), "\(where_): mini controls render 9 pt text")
                if !line.contains("ProgressView") {
                    XCTAssertFalse(line.contains("controlSize(.small)"), "\(where_): small controls render 11 pt text")
                }
                XCTAssertFalse(line.contains("minimumScaleFactor("), "\(where_): shrink-to-fit can drop text below 12 pt")
            }
        }
    }
}
