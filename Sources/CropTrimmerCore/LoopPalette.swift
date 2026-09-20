import Foundation

/// The 36 loop colors, like Ableton's clip colors: 12 hues around the wheel in three tones
/// (vivid, deep, pale). Index `tone * 12 + hue`. Core keeps them as HSB so it stays UI-free.
public enum LoopPalette {
    public static let hueCount = 12
    public static let toneCount = 3
    public static let count = hueCount * toneCount

    private static let hueNames = ["Red", "Orange", "Yellow", "Lime", "Green", "Mint",
                                   "Cyan", "Azure", "Blue", "Violet", "Magenta", "Rose"]
    private static let tones: [(name: String, saturation: Double, brightness: Double)] = [
        ("", 0.80, 0.95), ("Deep ", 0.75, 0.68), ("Pale ", 0.42, 0.97),
    ]

    public static func isValid(_ index: Int) -> Bool { (0..<count).contains(index) }
    public static func hue(of index: Int) -> Int { index % hueCount }
    public static func tone(of index: Int) -> Int { index / hueCount }

    /// Hue, saturation and brightness, each 0…1.
    public static func hsb(_ index: Int) -> (hue: Double, saturation: Double, brightness: Double) {
        let tone = tones[tone(of: index)]
        return (Double(hue(of: index)) / Double(hueCount), tone.saturation, tone.brightness)
    }

    public static func name(_ index: Int) -> String { tones[tone(of: index)].name + hueNames[hue(of: index)] }

    /// A random color whose hue no existing loop uses, so loops stay easy to tell apart; when every hue
    /// is taken, any unused color; when all are used, any color.
    public static func randomIndex<G: RandomNumberGenerator>(avoiding used: [Int], using generator: inout G) -> Int {
        let usedHues = Set(used.map(hue(of:)))
        let freshHue = (0..<count).filter { !usedHues.contains(hue(of: $0)) }
        let unused = (0..<count).filter { !used.contains($0) }
        let pool = !freshHue.isEmpty ? freshHue : (!unused.isEmpty ? unused : Array(0..<count))
        return pool.randomElement(using: &generator)!
    }

    public static func randomIndex(avoiding used: [Int]) -> Int {
        var generator = SystemRandomNumberGenerator()
        return randomIndex(avoiding: used, using: &generator)
    }
}
