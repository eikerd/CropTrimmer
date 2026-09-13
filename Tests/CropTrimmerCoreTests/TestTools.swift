import Foundation

/// Fixture generation needs a development FFmpeg. Homebrew installs it under
/// /opt/homebrew on Apple silicon and /usr/local on Intel; MediaEngine searches both.
enum TestTools {
    static let ffmpeg: String = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/ffmpeg"
}
