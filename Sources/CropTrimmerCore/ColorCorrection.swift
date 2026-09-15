import Foundation

/// The editable, renderer-independent color correction for one loop.
/// Values are normalized RGB coordinates in the agreed working space.
public struct ColorSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var blackPoint: Float
    public var whitePoint: Float
    public var gamma: Float
    public var saturation: Float

    public init(enabled: Bool = false, blackPoint: Float = 0, whitePoint: Float = 1, gamma: Float = 1, saturation: Float = 1) {
        self.enabled = enabled
        self.blackPoint = blackPoint
        self.whitePoint = whitePoint
        self.gamma = gamma
        self.saturation = saturation
    }

    public var isIdentity: Bool {
        !enabled || (blackPoint == 0 && whitePoint == 1 && gamma == 1 && saturation == 1)
    }

    public func validate() throws {
        guard blackPoint.isFinite, whitePoint.isFinite, gamma.isFinite, saturation.isFinite else {
            throw MediaError.invalid("Color correction values must be finite.")
        }
        guard (0...1).contains(blackPoint), (0...1).contains(whitePoint), whitePoint - blackPoint >= (1.0 / 255.0),
              (0.25...4).contains(gamma), (0...2).contains(saturation) else {
            throw MediaError.invalid("Color correction values are outside their supported ranges.")
        }
    }

    /// Applies levels, gamma, and saturation in that order. Gamma is expressed
    /// as a display-style value: values above one lift midtones.
    public func apply(to rgb: SIMD3<Float>) -> SIMD3<Float> {
        guard !isIdentity else { return rgb }
        let span = max(1.0 / 255.0, whitePoint - blackPoint)
        let leveled = SIMD3<Float>(
            powf(clamp((rgb.x - blackPoint) / span), 1 / gamma),
            powf(clamp((rgb.y - blackPoint) / span), 1 / gamma),
            powf(clamp((rgb.z - blackPoint) / span), 1 / gamma)
        )
        let luma = 0.2126 * leveled.x + 0.7152 * leveled.y + 0.0722 * leveled.z
        let saturated = SIMD3<Float>(repeating: luma) + (leveled - SIMD3<Float>(repeating: luma)) * saturation
        return SIMD3<Float>(clamp(saturated.x), clamp(saturated.y), clamp(saturated.z))
    }

    private func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
}
