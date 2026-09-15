import Foundation

public struct ColorSample: Codable, Equatable, Sendable {
    public let source: SIMD3<Float>
    public let target: SIMD3<Float>
    public init(source: SIMD3<Float>, target: SIMD3<Float>) { self.source = source; self.target = target }
}

public struct ColorFitResult: Sendable {
    public let lut: ColorLUT
    public let meanError: Float
    public let maxError: Float
    public let iterations: Int
}

/// Fits a bounded global color transform from corresponding pixels. The first
/// implementation uses a regularized affine model to avoid dense LUT-sized
/// matrices; its result is still emitted as a sampled 3D LUT for both renderers.
public enum ColorLUTFitter {
    public static func fit(samples: [ColorSample], gridSize: Int = 17, identityWeight: Double = 0.001) throws -> ColorFitResult {
        guard samples.count >= 4, (2...65).contains(gridSize), identityWeight.isFinite, identityWeight >= 0 else {
            throw MediaError.invalid("A color match needs at least four corresponding samples.")
        }
        guard samples.allSatisfy({ finite($0.source) && finite($0.target) && inUnit($0.source) && inUnit($0.target) }) else {
            throw MediaError.invalid("Color match samples must be finite normalized RGB values.")
        }

        var coefficients = [[Double]]()
        for channel in 0..<3 {
            var normal = Array(repeating: Array(repeating: 0.0, count: 5), count: 4)
            for sample in samples {
                let x = [Double(sample.source.x), Double(sample.source.y), Double(sample.source.z), 1]
                let y = Double(sample.target[channel])
                for row in 0..<4 { for column in 0..<4 { normal[row][column] += x[row] * x[column] } }
                for row in 0..<4 { normal[row][4] += x[row] * y }
            }
            // Pull the solution toward identity, which keeps sparse/noisy fits tame.
            for axis in 0..<3 { normal[axis][axis] += identityWeight; normal[axis][4] += identityWeight }
            normal[3][3] += identityWeight
            coefficients.append(try solve(normal))
        }

        let transform: (SIMD3<Float>) -> SIMD3<Float> = { value in
            let x = [Double(value.x), Double(value.y), Double(value.z), 1]
            return SIMD3<Float>(
                clamp(Float(coefficients[0].enumerated().reduce(0) { $0 + $1.element * x[$1.offset] })),
                clamp(Float(coefficients[1].enumerated().reduce(0) { $0 + $1.element * x[$1.offset] })),
                clamp(Float(coefficients[2].enumerated().reduce(0) { $0 + $1.element * x[$1.offset] }))
            )
        }
        var values = [Float](); values.reserveCapacity(gridSize * gridSize * gridSize * 3)
        for b in 0..<gridSize { for g in 0..<gridSize { for r in 0..<gridSize {
            let input = SIMD3<Float>(Float(r) / Float(gridSize - 1), Float(g) / Float(gridSize - 1), Float(b) / Float(gridSize - 1))
            let output = transform(input); values += [output.x, output.y, output.z]
        } } }
        let lut = try ColorLUT(size: gridSize, values: values)
        let errors = samples.map { magnitude(transform($0.source) - $0.target) }
        return ColorFitResult(lut: lut, meanError: errors.reduce(0, +) / Float(errors.count), maxError: errors.max() ?? 0, iterations: 1)
    }

    private static func solve(_ input: [[Double]]) throws -> [Double] {
        var matrix = input
        for pivot in 0..<4 {
            guard let row = (pivot..<4).max(by: { abs(matrix[$0][pivot]) < abs(matrix[$1][pivot]) }), abs(matrix[row][pivot]) > 1e-12 else {
                throw MediaError.invalid("The color match samples do not span enough color variation.")
            }
            matrix.swapAt(pivot, row)
            let divisor = matrix[pivot][pivot]
            for column in pivot..<5 { matrix[pivot][column] /= divisor }
            for row in 0..<4 where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot..<5 { matrix[row][column] -= factor * matrix[pivot][column] }
            }
        }
        return matrix.map { $0[4] }
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func inUnit(_ value: SIMD3<Float>) -> Bool { (0...1).contains(value.x) && (0...1).contains(value.y) && (0...1).contains(value.z) }
    private static func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
    private static func magnitude(_ value: SIMD3<Float>) -> Float { sqrt(value.x * value.x + value.y * value.y + value.z * value.z) }
}
