import Foundation

public enum CropAspectRatio: String, CaseIterable, Codable, Sendable {
    case free = "Freeform", original = "Original", widescreen = "16:9", classic = "4:3"
    case square = "1:1", portrait = "9:16", cinema = "1.85:1", scope = "2.39:1"

    public func value(sourceWidth: Int, sourceHeight: Int) -> Double? {
        switch self {
        case .free: nil
        case .original: Double(sourceWidth) / Double(max(1, sourceHeight))
        case .widescreen: 16.0 / 9
        case .classic: 4.0 / 3
        case .square: 1
        case .portrait: 9.0 / 16
        case .cinema: 1.85
        case .scope: 2.39
        }
    }

    /// The same frame after a quarter turn of the picture beneath it. Freeform, Original and 1:1 read the
    /// same either way up and 16:9 swaps with 9:16; the menu has no upright 4:3, 1.85:1 or 2.39:1, so
    /// those unlock rather than squeeze the turned crop.
    public var quarterTurned: CropAspectRatio {
        switch self {
        case .free, .original, .square: self
        case .widescreen: .portrait
        case .portrait: .widescreen
        case .classic, .cinema, .scope: .free
        }
    }
}

/// Locked sizes are rounded to the nearest available even source pixel.
public enum CropGeometry {
    private static func size(height: Double, ratio: Double, maxWidth: Int, maxHeight: Int) -> (Int, Int) {
        let w = max(2, maxWidth / 2 * 2), h = max(2, maxHeight / 2 * 2)
        let target = min(max(2, height), min(Double(h), Double(w) / ratio))
        return (min(w, max(2, Int((target * ratio / 2).rounded()) * 2)),
                min(h, max(2, Int((target / 2).rounded()) * 2)))
    }

    public static func fitted(_ rect: PixelRect, aspect: CropAspectRatio, sourceWidth: Int, sourceHeight: Int) -> PixelRect {
        let rect = rect.constrained(toWidth: sourceWidth, height: sourceHeight)
        guard let ratio = aspect.value(sourceWidth: sourceWidth, sourceHeight: sourceHeight) else { return rect }
        let (w, h) = size(height: min(Double(rect.height), Double(rect.width) / ratio), ratio: ratio, maxWidth: rect.width, maxHeight: rect.height)
        return PixelRect(x: rect.x + (rect.width - w) / 2, y: rect.y + (rect.height - h) / 2, width: w, height: h)
            .constrained(toWidth: sourceWidth, height: sourceHeight)
    }

    public static func resized(_ rect: PixelRect, aspect: CropAspectRatio, corner: Int, dx: Int, dy: Int, sourceWidth: Int, sourceHeight: Int) -> PixelRect {
        let left = corner % 2 == 0, top = corner < 2
        let anchorX = left ? rect.x + rect.width : rect.x
        let anchorY = top ? rect.y + rect.height : rect.y
        let maxW = left ? anchorX : sourceWidth - anchorX
        let maxH = top ? anchorY : sourceHeight - anchorY
        let desiredW = Double(rect.width) + Double(dx) * (left ? -1 : 1)
        let desiredH = Double(rect.height) + Double(dy) * (top ? -1 : 1)
        let w: Int, h: Int
        if let ratio = aspect.value(sourceWidth: sourceWidth, sourceHeight: sourceHeight) {
            // Project pointer movement onto the locked diagonal while anchoring
            // the opposite corner, then bound both dimensions together.
            (w, h) = size(height: (desiredW * ratio + desiredH) / (ratio * ratio + 1), ratio: ratio, maxWidth: maxW, maxHeight: maxH)
        } else {
            w = max(2, min(maxW, Int(desiredW)) / 2 * 2)
            h = max(2, min(maxH, Int(desiredH)) / 2 * 2)
        }
        return PixelRect(x: left ? anchorX - w : anchorX, y: top ? anchorY - h : anchorY, width: w, height: h)
            .constrained(toWidth: sourceWidth, height: sourceHeight)
    }

    public static func dimension(_ rect: PixelRect, width: Int? = nil, height: Int? = nil, aspect: CropAspectRatio, sourceWidth: Int, sourceHeight: Int) -> PixelRect {
        var result = rect
        if let ratio = aspect.value(sourceWidth: sourceWidth, sourceHeight: sourceHeight) {
            let target = width.map { Double($0) / ratio } ?? Double(height ?? rect.height)
            (result.width, result.height) = size(height: target, ratio: ratio, maxWidth: sourceWidth - rect.x, maxHeight: sourceHeight - rect.y)
        } else {
            result.width = width ?? rect.width; result.height = height ?? rect.height
        }
        return result.constrained(toWidth: sourceWidth, height: sourceHeight)
    }
}
