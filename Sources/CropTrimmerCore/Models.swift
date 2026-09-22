import Foundation

public enum ExportMethod: String, CaseIterable, Codable, Sendable { case automatic = "Automatic", fast = "Fast trim", accurate = "Accurate trim" }
public enum Quality: String, CaseIterable, Codable, Sendable {
    case high = "High quality", balanced = "Balanced", smaller = "Smaller file"
    public var crf: Int { switch self { case .high: 18; case .balanced: 21; case .smaller: 25 } }
}
public enum ResolvedMethod: String, Codable, Sendable { case copy = "Fast trim", encode = "Re-encode" }

/// The frame a joined clip renders into when its loops are not all the same size — which happens
/// as soon as two loops crop differently, or one is turned a quarter and another is not. Neither
/// choice crops or stretches a loop: a loop smaller than the frame is centred on black.
public enum JoinFrame: String, CaseIterable, Sendable {
    /// The smallest frame that holds every loop at full size: the widest width beside the tallest
    /// height. Nothing is ever scaled down, so mixing a portrait loop with a landscape one gives
    /// a squarer frame than either of them.
    case fitAll = "Fit every loop"
    /// The first loop's own frame. Later loops are scaled down to fit inside it.
    case matchFirst = "Match the first loop"
}

/// The question Export All asks when its loops are not all the same size, and nothing else: the
/// words, and the frame each answer produces. It lives here so the wording can be tested and the
/// editor is left holding only the dialog.
public struct JoinFramePrompt: Equatable, Sendable {
    public let message: String
    public let detail: String
    public let fitTitle: String
    public let matchTitle: String
    public let cancelTitle = "Cancel"

    /// Nil when every loop already renders into one frame — there is nothing to decide, so the
    /// owner is not stopped to decide it.
    public init?(sizes: [(width: Int, height: Int)], fit: (width: Int, height: Int), matched: (width: Int, height: Int)) {
        guard let first = sizes.first, sizes.contains(where: { $0 != first }) else { return nil }
        message = "These loops are not all the same size."
        detail = sizes.enumerated().map { "Loop \($0.offset + 1) is \($0.element.width) × \($0.element.height)" }.joined(separator: ", ")
            + ". Choose the frame the joined clip is rendered into. A loop smaller than the frame is centred on black; none of them is cropped or stretched."
        fitTitle = "Fit Every Loop · \(fit.width) × \(fit.height)"
        matchTitle = "Match Loop 1 · \(matched.width) × \(matched.height)"
    }
}

/// One joined export: finished segment movies, the frame they are composited into, and the
/// stream settings the single output carries. Assembled by the editor, carried out by the engine.
public struct JoinRequest: Sendable {
    public let segments: [URL]
    public let width: Int
    public let height: Int
    public let fps: Double
    public let quality: Quality
    public let audio: Bool
    /// The segment lengths added up, as measured in the finished segments rather than planned.
    public let expectedDuration: Double
    /// The first loop's settings, so the review sheet can describe the clip it came from.
    public let settings: EditSettings
    public let sourceURL: URL
    public init(segments: [URL], width: Int, height: Int, fps: Double, quality: Quality, audio: Bool,
                expectedDuration: Double, settings: EditSettings, sourceURL: URL) {
        self.segments = segments; self.width = width; self.height = height; self.fps = fps
        self.quality = quality; self.audio = audio; self.expectedDuration = expectedDuration
        self.settings = settings; self.sourceURL = sourceURL
    }
}
public enum PlaybackMode: String, CaseIterable, Codable, Sendable {
    case repeatSelection = "A–B repeat", whole = "Whole movie", once = "Play selection once"
    /// Every loop in turn, in timeline order, wrapping round at the last one and playing nothing
    /// in between. Each loop keeps its own speed while it is the one playing.
    case allLoops = "Play all loops"
    /// The mode a single click on the transport's mode button moves to, VLC-style.
    public var next: Self {
        switch self { case .repeatSelection: .once; case .once: .allLoops; case .allLoops: .whole; case .whole: .repeatSelection }
    }
    /// True where playback is bounded by a loop's A and B rather than by the whole movie.
    public var followsLoop: Bool { self != .whole }
}

public struct PixelRect: Codable, Equatable, Sendable {
    public var x: Int; public var y: Int; public var width: Int; public var height: Int
    public init(x: Int = 0, y: Int = 0, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    public func constrained(toWidth w: Int, height h: Int, even: Bool = true) -> Self {
        let unit = even ? 2 : 1
        let width = max(unit, min(self.width, w) / unit * unit)
        let height = max(unit, min(self.height, h) / unit * unit)
        return .init(x: max(0, min(x, w - width)) / unit * unit, y: max(0, min(y, h - height)) / unit * unit, width: width, height: height)
    }
}
public struct SourceIdentity: Codable, Equatable, Sendable {
    public let size: Int64; public let modified: Date; public let inode: UInt64
    public init(url: URL) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (a[.size] as? NSNumber)?.int64Value ?? 0
        modified = a[.modificationDate] as? Date ?? .distantPast
        inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

/// Color tags reported by the decoder. Unknown values are retained so the UI
/// and future providers can distinguish a real tag from an assumption.
public struct SourceColorDescription: Codable, Equatable, Sendable {
    public let pixelFormat: String
    public let primaries: String
    public let transfer: String
    public let matrix: String
    public let range: String
    public init(pixelFormat: String = "unknown", primaries: String = "unknown", transfer: String = "unknown", matrix: String = "unknown", range: String = "unknown") {
        self.pixelFormat = pixelFormat; self.primaries = primaries; self.transfer = transfer; self.matrix = matrix; self.range = range
    }
    public var isTaggedSDR709: Bool {
        primaries == "bt709" && transfer == "bt709" && matrix == "bt709" && ["tv", "pc"].contains(range)
    }
    public var isAmbiguous: Bool { [primaries, transfer, matrix, range].contains("unknown") || [primaries, transfer, matrix, range].contains("unspecified") }
}
public struct MediaSource: Identifiable, Sendable {
    public let id: UUID; public let url: URL; public let identity: SourceIdentity
    public let duration: Double; public let width: Int; public let height: Int
    public let encodedWidth: Int; public let encodedHeight: Int; public let rotation: Int
    public let fps: Double; public let videoCodec: String; public let audioCount: Int
    public let subtitleCount: Int; public let format: String; public let startTime: Double
    /// How far the first picture sits after the container's own start. FFmpeg's input `-ss` counts
    /// from the container, the editor counts from the picture, so every seek adds this.
    public let seekOffset: Double
    public let encodingRestriction: String?
    public let color: SourceColorDescription
    public init(id: UUID = UUID(), url: URL, identity: SourceIdentity, duration: Double, width: Int, height: Int, encodedWidth: Int, encodedHeight: Int, rotation: Int, fps: Double, videoCodec: String, audioCount: Int, subtitleCount: Int, format: String, startTime: Double = 0, seekOffset: Double = 0, encodingRestriction: String? = nil, color: SourceColorDescription = SourceColorDescription()) {
        self.id = id; self.url = url; self.identity = identity; self.duration = duration; self.width = width; self.height = height; self.encodedWidth = encodedWidth; self.encodedHeight = encodedHeight; self.rotation = rotation; self.fps = fps; self.videoCodec = videoCodec; self.audioCount = audioCount; self.subtitleCount = subtitleCount; self.format = format; self.startTime = startTime; self.seekOffset = seekOffset; self.encodingRestriction = encodingRestriction; self.color = color
    }
}
public struct EditSettings: Codable, Equatable, Sendable {
    public var start: Double = 0; public var end: Double = 0
    public var cropAspectRatio: CropAspectRatio? = nil
    public var lastLockedCropAspectRatio: CropAspectRatio? = nil
    public var cropEnabled = false; public var crop = PixelRect(width: 1920, height: 1080)
    public var method: ExportMethod = .automatic; public var quality: Quality = .balanced
    public var color = ColorSettings()
    /// How fast this loop plays and renders. 1 is the source's own speed; 0.5 is half speed, which
    /// takes twice as long to play. Previewing and exporting use the same number.
    public var speed: Double = 1
    /// Clockwise turn of the upright picture, in degrees: 0, 90, 180 or 270. The crop is measured on
    /// the turned picture, so an aspect lock names the shape of the export.
    public var rotation = 0
    public init() {}
    public init(source: MediaSource) { end = source.duration; crop = PixelRect(width: source.width, height: source.height).constrained(toWidth: source.width, height: source.height) }
    /// The speeds the menus offer. Anything else is refused by `validate`, so a stored or typed
    /// value can never reach the encoder.
    public static let speeds: [Double] = [0.1, 0.125, 0.25, 0.5, 0.75, 1, 1.5, 2, 4, 8]
    public static func speedLabel(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...3))) + "×"
    }
    /// The turns the rotate button cycles through, in order.
    public static let rotations = [0, 90, 180, 270]

    /// The picture this loop crops, and exports whole when it is not cropped: the upright source turned by `rotation`.
    public func pictureSize(of source: MediaSource) -> (width: Int, height: Int) {
        rotation % 180 == 0 ? (source.width, source.height) : (source.height, source.width)
    }

    /// One more clockwise quarter turn, as the rotate button cycles. The crop turns with the picture, so it
    /// keeps framing the same content and four turns give back the same rectangle; a locked ratio turns too.
    public func turnedClockwise(source: MediaSource) -> EditSettings {
        var next = self
        next.rotation = (rotation + 90) % 360
        // On a picture `height` tall, a clockwise quarter turn carries the point (x, y) to (height - y, x).
        let height = pictureSize(of: source).height
        let size = next.pictureSize(of: source)
        next.crop = PixelRect(x: height - crop.y - crop.height, y: crop.x, width: crop.height, height: crop.width)
            .constrained(toWidth: size.width, height: size.height)
        next.cropAspectRatio = cropAspectRatio?.quarterTurned
        if let last = lastLockedCropAspectRatio, last.quarterTurned != .free { next.lastLockedCropAspectRatio = last.quarterTurned }
        return next
    }

    private enum CodingKeys: String, CodingKey { case start, end, cropAspectRatio, lastLockedCropAspectRatio, cropEnabled, crop, method, quality, color, speed, rotation }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        start = try values.decode(Double.self, forKey: .start)
        end = try values.decode(Double.self, forKey: .end)
        cropAspectRatio = try values.decodeIfPresent(CropAspectRatio.self, forKey: .cropAspectRatio)
        lastLockedCropAspectRatio = try values.decodeIfPresent(CropAspectRatio.self, forKey: .lastLockedCropAspectRatio)
        cropEnabled = try values.decode(Bool.self, forKey: .cropEnabled)
        crop = try values.decode(PixelRect.self, forKey: .crop)
        method = try values.decode(ExportMethod.self, forKey: .method)
        quality = try values.decode(Quality.self, forKey: .quality)
        color = try values.decodeIfPresent(ColorSettings.self, forKey: .color) ?? ColorSettings()
        speed = try values.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        rotation = try values.decodeIfPresent(Int.self, forKey: .rotation) ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(start, forKey: .start); try values.encode(end, forKey: .end)
        try values.encode(cropAspectRatio, forKey: .cropAspectRatio); try values.encode(lastLockedCropAspectRatio, forKey: .lastLockedCropAspectRatio)
        try values.encode(cropEnabled, forKey: .cropEnabled); try values.encode(crop, forKey: .crop)
        try values.encode(method, forKey: .method); try values.encode(quality, forKey: .quality); try values.encode(color, forKey: .color)
        try values.encode(speed, forKey: .speed); try values.encode(rotation, forKey: .rotation)
    }
    public var duration: Double { max(0, end - start) }
    /// How long the exported movie runs: the source span stretched or compressed by `speed`.
    public var outputDuration: Double { speed > 0 ? duration / speed : duration }
    public func validate(source: MediaSource) throws {
        guard start.isFinite, end.isFinite, start >= 0, end <= source.duration + 0.001, end > start else { throw MediaError.invalid("Choose a start before the end, within the movie.") }
        guard Self.speeds.contains(where: { abs($0 - speed) < 0.000001 }) else {
            throw MediaError.invalid("Choose a speed from the menu, between \(Self.speedLabel(Self.speeds[0])) and \(Self.speedLabel(Self.speeds[Self.speeds.count - 1])).")
        }
        guard Self.rotations.contains(rotation) else { throw MediaError.invalid("Choose a rotation of 0°, 90°, 180° or 270°.") }
        if cropEnabled {
            let (width, height) = pictureSize(of: source)
            guard crop.width >= 2, crop.height >= 2, crop.x >= 0, crop.y >= 0, crop.width <= width, crop.height <= height, crop.x <= width - crop.width, crop.y <= height - crop.height,
                  crop.width % 2 == 0, crop.height % 2 == 0, crop.x % 2 == 0, crop.y % 2 == 0 else { throw MediaError.invalid("Crop coordinates and dimensions must be even and inside the picture.") }
        }
        try color.validate()
    }
}
public struct ExportPlan: Sendable {
    public let source: MediaSource; public let settings: EditSettings; public let method: ResolvedMethod
    public let plannedStart: Double; public let plannedEnd: Double; public let copyCutEnd: Double?; public let fileExtension: String; public let explanation: String
    public let colorLUT: ColorLUT?
    public init(source: MediaSource, settings: EditSettings, method: ResolvedMethod, plannedStart: Double, plannedEnd: Double, fileExtension: String = "mp4", explanation: String, copyCutEnd: Double? = nil) throws {
        if method == .copy && !settings.color.isIdentity { throw MediaError.invalid("A color correction cannot use fast-copy export.") }
        self.source = source; self.settings = settings; self.method = method; self.plannedStart = plannedStart; self.plannedEnd = plannedEnd; self.copyCutEnd = copyCutEnd; self.fileExtension = fileExtension; self.explanation = explanation
        self.colorLUT = settings.color.isIdentity ? nil : try ColorLUT.compile(settings: settings.color)
    }
    public var width: Int { settings.cropEnabled ? settings.crop.width : settings.pictureSize(of: source).width }
    public var height: Int { settings.cropEnabled ? settings.crop.height : settings.pictureSize(of: source).height }
    /// The span taken from the source. `outputDuration` is what the exported file runs for, which
    /// differs whenever the loop carries a speed.
    public var duration: Double { plannedEnd - plannedStart }
    public var outputDuration: Double { settings.speed > 0 ? duration / settings.speed : duration }
    public var startShift: Double { plannedStart - settings.start }
    public var endShift: Double { plannedEnd - settings.end }
}
public struct ExportResult: Identifiable, Codable, Sendable {
    public var id: UUID; public var url: URL; public var sourceURL: URL; public var created: Date
    public var duration: Double; public var width: Int; public var height: Int; public var bytes: Int64
    public var method: ResolvedMethod; public var quality: Quality?; public var settings: EditSettings
    public var actualStart: Double; public var actualEnd: Double; public var note: String
    /// How many loops this one file was made of. One for an ordinary export; the joined clip counts
    /// its loops, because a single pair of requested boundaries would say nothing true about it.
    public var segments: Int
    public init(id: UUID = UUID(), url: URL, sourceURL: URL, created: Date = Date(), duration: Double, width: Int, height: Int, bytes: Int64, method: ResolvedMethod, quality: Quality?, settings: EditSettings, actualStart: Double, actualEnd: Double, note: String = "", segments: Int = 1) {
        self.id = id; self.url = url; self.sourceURL = sourceURL; self.created = created; self.duration = duration; self.width = width; self.height = height; self.bytes = bytes; self.method = method; self.quality = quality; self.settings = settings; self.actualStart = actualStart; self.actualEnd = actualEnd; self.note = note; self.segments = segments
    }
}
public enum MediaError: LocalizedError {
    case invalid(String), unavailable(String), failed(String), sourceChanged, cancelled
    public var errorDescription: String? {
        switch self { case .invalid(let s), .unavailable(let s), .failed(let s): s
        case .sourceChanged: "The original movie changed. Reopen it before exporting."
        case .cancelled: "Cancelled" }
    }
}
public func timeLabel(_ value: Double) -> String {
    guard value.isFinite else { return "00:00.000" }
    let bounded = min(max(0, value), 999_999_999)
    let ms = Int((bounded * 1000).rounded())
    return String(format: "%02d:%02d.%03d", ms / 60000, (ms / 1000) % 60, ms % 1000)
}
public func byteLabel(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
