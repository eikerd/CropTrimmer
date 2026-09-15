import Foundation

public enum ExportMethod: String, CaseIterable, Codable, Sendable { case automatic = "Automatic", fast = "Fast trim", accurate = "Accurate trim" }
public enum Quality: String, CaseIterable, Codable, Sendable {
    case high = "High quality", balanced = "Balanced", smaller = "Smaller file"
    public var crf: Int { switch self { case .high: 18; case .balanced: 21; case .smaller: 25 } }
}
public enum ResolvedMethod: String, Codable, Sendable { case copy = "Fast trim", encode = "Re-encode" }
public enum PlaybackMode: String, CaseIterable, Codable, Sendable { case repeatSelection = "A–B repeat", whole = "Whole movie", once = "Play selection once" }

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
    public let encodingRestriction: String?
    public let color: SourceColorDescription
    public init(id: UUID = UUID(), url: URL, identity: SourceIdentity, duration: Double, width: Int, height: Int, encodedWidth: Int, encodedHeight: Int, rotation: Int, fps: Double, videoCodec: String, audioCount: Int, subtitleCount: Int, format: String, startTime: Double = 0, encodingRestriction: String? = nil, color: SourceColorDescription = SourceColorDescription()) {
        self.id = id; self.url = url; self.identity = identity; self.duration = duration; self.width = width; self.height = height; self.encodedWidth = encodedWidth; self.encodedHeight = encodedHeight; self.rotation = rotation; self.fps = fps; self.videoCodec = videoCodec; self.audioCount = audioCount; self.subtitleCount = subtitleCount; self.format = format; self.startTime = startTime; self.encodingRestriction = encodingRestriction; self.color = color
    }
}
public struct EditSettings: Codable, Equatable, Sendable {
    public var start: Double = 0; public var end: Double = 0
    public var cropAspectRatio: CropAspectRatio? = nil
    public var lastLockedCropAspectRatio: CropAspectRatio? = nil
    public var cropEnabled = false; public var crop = PixelRect(width: 1920, height: 1080)
    public var method: ExportMethod = .automatic; public var quality: Quality = .balanced
    public var color = ColorSettings()
    public init() {}
    public init(source: MediaSource) { end = source.duration; crop = PixelRect(width: source.width, height: source.height).constrained(toWidth: source.width, height: source.height) }
    private enum CodingKeys: String, CodingKey { case start, end, cropAspectRatio, lastLockedCropAspectRatio, cropEnabled, crop, method, quality, color }
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
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(start, forKey: .start); try values.encode(end, forKey: .end)
        try values.encode(cropAspectRatio, forKey: .cropAspectRatio); try values.encode(lastLockedCropAspectRatio, forKey: .lastLockedCropAspectRatio)
        try values.encode(cropEnabled, forKey: .cropEnabled); try values.encode(crop, forKey: .crop)
        try values.encode(method, forKey: .method); try values.encode(quality, forKey: .quality); try values.encode(color, forKey: .color)
    }
    public var duration: Double { max(0, end - start) }
    public func validate(source: MediaSource) throws {
        guard start.isFinite, end.isFinite, start >= 0, end <= source.duration + 0.001, end > start else { throw MediaError.invalid("Choose a start before the end, within the movie.") }
        if cropEnabled {
            guard crop.width >= 2, crop.height >= 2, crop.x >= 0, crop.y >= 0, crop.width <= source.width, crop.height <= source.height, crop.x <= source.width - crop.width, crop.y <= source.height - crop.height,
                  crop.width % 2 == 0, crop.height % 2 == 0, crop.x % 2 == 0, crop.y % 2 == 0 else { throw MediaError.invalid("Crop coordinates and dimensions must be even and inside the source image.") }
        }
    }
}
public struct ExportPlan: Sendable {
    public let source: MediaSource; public let settings: EditSettings; public let method: ResolvedMethod
    public let plannedStart: Double; public let plannedEnd: Double; public let copyCutEnd: Double?; public let fileExtension: String; public let explanation: String
    public let colorLUT: ColorLUT?
    public init(source: MediaSource, settings: EditSettings, method: ResolvedMethod, plannedStart: Double, plannedEnd: Double, fileExtension: String = "mp4", explanation: String, copyCutEnd: Double? = nil, colorLUT: ColorLUT? = nil) {
        self.source = source; self.settings = settings; self.method = method; self.plannedStart = plannedStart; self.plannedEnd = plannedEnd; self.copyCutEnd = copyCutEnd; self.fileExtension = fileExtension; self.explanation = explanation; self.colorLUT = colorLUT
    }
    public var width: Int { settings.cropEnabled ? settings.crop.width : source.width }
    public var height: Int { settings.cropEnabled ? settings.crop.height : source.height }
    public var duration: Double { plannedEnd - plannedStart }
    public var startShift: Double { plannedStart - settings.start }
    public var endShift: Double { plannedEnd - settings.end }
}
public struct ExportResult: Identifiable, Codable, Sendable {
    public var id: UUID; public var url: URL; public var sourceURL: URL; public var created: Date
    public var duration: Double; public var width: Int; public var height: Int; public var bytes: Int64
    public var method: ResolvedMethod; public var quality: Quality?; public var settings: EditSettings
    public var actualStart: Double; public var actualEnd: Double; public var note: String
    public init(id: UUID = UUID(), url: URL, sourceURL: URL, created: Date = Date(), duration: Double, width: Int, height: Int, bytes: Int64, method: ResolvedMethod, quality: Quality?, settings: EditSettings, actualStart: Double, actualEnd: Double, note: String = "") {
        self.id = id; self.url = url; self.sourceURL = sourceURL; self.created = created; self.duration = duration; self.width = width; self.height = height; self.bytes = bytes; self.method = method; self.quality = quality; self.settings = settings; self.actualStart = actualStart; self.actualEnd = actualEnd; self.note = note
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
