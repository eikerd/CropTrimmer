import Foundation

/// The editable, renderer-independent color correction for one loop.
/// Values are normalized RGB coordinates in the agreed working space.
public struct ColorSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var blackPoint: Float
    public var whitePoint: Float
    public var gamma: Float
    public var saturation: Float
    public var baseLUT: ColorLUT?

    public init(enabled: Bool = false, blackPoint: Float = 0, whitePoint: Float = 1, gamma: Float = 1, saturation: Float = 1, baseLUT: ColorLUT? = nil) {
        self.enabled = enabled
        self.blackPoint = blackPoint
        self.whitePoint = whitePoint
        self.gamma = gamma
        self.saturation = saturation
        self.baseLUT = baseLUT
    }

    public var isIdentity: Bool {
        !enabled || ((baseLUT == nil || baseLUT?.isIdentity == true) && blackPoint == 0 && whitePoint == 1 && gamma == 1 && saturation == 1)
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
        let base = baseLUT?.sample(rgb) ?? rgb
        let span = max(1.0 / 255.0, whitePoint - blackPoint)
        let leveled = SIMD3<Float>(
            powf(clamp((base.x - blackPoint) / span), 1 / gamma),
            powf(clamp((base.y - blackPoint) / span), 1 / gamma),
            powf(clamp((base.z - blackPoint) / span), 1 / gamma)
        )
        let luma = 0.2126 * leveled.x + 0.7152 * leveled.y + 0.0722 * leveled.z
        let saturated = SIMD3<Float>(repeating: luma) + (leveled - SIMD3<Float>(repeating: luma)) * saturation
        return SIMD3<Float>(clamp(saturated.x), clamp(saturated.y), clamp(saturated.z))
    }

    private func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
}

/// A portable 3D RGB lookup table. Red is the fastest-changing axis, matching
/// Core Image's cube layout and the explicit adapter used by export.
public struct ColorLUT: Codable, Equatable, Sendable {
    public let size: Int
    public let values: [Float]
    public let colorSpace: String

    private enum CodingKeys: String, CodingKey { case size, values, colorSpace }

    public init(size: Int, values: [Float], colorSpace: String = "sRGB") throws {
        guard (2...65).contains(size), values.count == size * size * size * 3,
              values.allSatisfy({ $0.isFinite }) else {
            throw MediaError.invalid("The 3D color table has an invalid size or payload.")
        }
        guard !colorSpace.isEmpty else { throw MediaError.invalid("The color table has no color space.") }
        self.size = size; self.values = values; self.colorSpace = colorSpace
    }

    public var isIdentity: Bool {
        guard colorSpace.caseInsensitiveCompare("sRGB") == .orderedSame else { return false }
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let index = ((b * size + g) * size + r) * 3
                    let expected = [Float(r) / Float(size - 1), Float(g) / Float(size - 1), Float(b) / Float(size - 1)]
                    if abs(values[index] - expected[0]) > 0.000001 || abs(values[index + 1] - expected[1]) > 0.000001 || abs(values[index + 2] - expected[2]) > 0.000001 { return false }
                }
            }
        }
        return true
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(size: values.decode(Int.self, forKey: .size),
                      values: values.decode([Float].self, forKey: .values),
                      colorSpace: values.decode(String.self, forKey: .colorSpace))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(size, forKey: .size)
        try values.encode(self.values, forKey: .values)
        try values.encode(colorSpace, forKey: .colorSpace)
    }

    public init(cubeText: String) throws {
        var size: Int?
        var domainMin: [Float] = [0, 0, 0], domainMax: [Float] = [1, 1, 1]
        var samples: [Float] = []
        for rawLine in cubeText.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !fields.isEmpty else { continue }
            switch fields[0].uppercased() {
            case "TITLE": continue
            case "LUT_1D_SIZE": throw MediaError.invalid("1D LUTs are not supported; import a 3D color table.")
            case "LUT_3D_SIZE":
                guard fields.count == 2, let value = Int(fields[1]), (2...65).contains(value), size == nil else { throw MediaError.invalid("The 3D LUT size is invalid.") }
                size = value
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let values = fields.dropFirst().compactMap { Float($0) }
                guard fields.count == 4, values.count == 3, values.allSatisfy({ $0.isFinite }) else { throw MediaError.invalid("The LUT domain is invalid.") }
                if fields[0].uppercased() == "DOMAIN_MIN" { domainMin = values } else { domainMax = values }
            default:
                let values = fields.compactMap { Float($0) }
                guard fields.count == 3, values.count == 3, values.allSatisfy({ $0.isFinite }) else { throw MediaError.invalid("The LUT contains an invalid sample.") }
                samples += values
            }
        }
        guard let size, domainMin == [0, 0, 0], domainMax == [1, 1, 1], samples.count == size * size * size * 3 else {
            throw MediaError.invalid("The LUT is missing a supported unit 3D table.")
        }
        try self.init(size: size, values: samples)
    }

    public static func compile(settings: ColorSettings, size: Int = 33) throws -> ColorLUT {
        try settings.validate()
        guard (2...65).contains(size) else { throw MediaError.invalid("The 3D color table size is unsupported.") }
        var values = [Float](); values.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let input = SIMD3<Float>(Float(r) / Float(size - 1), Float(g) / Float(size - 1), Float(b) / Float(size - 1))
                    let output = settings.apply(to: input)
                    values += [output.x, output.y, output.z]
                }
            }
        }
        return try ColorLUT(size: size, values: values)
    }

    public func sample(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let coordinates = SIMD3<Float>(clamp(rgb.x), clamp(rgb.y), clamp(rgb.z)) * Float(size - 1)
        let lower = SIMD3<Int>(Int(floor(coordinates.x)), Int(floor(coordinates.y)), Int(floor(coordinates.z)))
        let upper = SIMD3<Int>(min(size - 1, lower.x + 1), min(size - 1, lower.y + 1), min(size - 1, lower.z + 1))
        let fraction = coordinates - SIMD3<Float>(lower)
        func value(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
            let index = ((b * size + g) * size + r) * 3
            return SIMD3<Float>(values[index], values[index + 1], values[index + 2])
        }
        let c000 = value(lower.x, lower.y, lower.z), c100 = value(upper.x, lower.y, lower.z)
        let c010 = value(lower.x, upper.y, lower.z), c110 = value(upper.x, upper.y, lower.z)
        let c001 = value(lower.x, lower.y, upper.z), c101 = value(upper.x, lower.y, upper.z)
        let c011 = value(lower.x, upper.y, upper.z), c111 = value(upper.x, upper.y, upper.z)
        let c00 = c000 + (c100 - c000) * fraction.x, c10 = c010 + (c110 - c010) * fraction.x
        let c01 = c001 + (c101 - c001) * fraction.x, c11 = c011 + (c111 - c011) * fraction.x
        let c0 = c00 + (c10 - c00) * fraction.y, c1 = c01 + (c11 - c01) * fraction.y
        return c0 + (c1 - c0) * fraction.z
    }

    /// Writes the table in the text format understood by FFmpeg's lut3d filter.
    public var cubeText: String {
        var text = "TITLE \"Crop Trimmer color correction\"\nLUT_3D_SIZE \(size)\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        text.reserveCapacity(values.count * 10)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let index = ((b * size + g) * size + r) * 3
                    text += String(format: "%.9f %.9f %.9f\n", values[index], values[index + 1], values[index + 2])
                }
            }
        }
        return text
    }

    private func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
}
