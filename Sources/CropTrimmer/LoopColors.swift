import SwiftUI
import CropTrimmerCore

/// SwiftUI colors for the loop palette.
enum LoopColors {
    static func fill(_ index: Int) -> Color {
        let c = LoopPalette.hsb(index)
        return Color(hue: c.hue, saturation: c.saturation, brightness: c.brightness)
    }

    /// The loop's color lifted enough to read as text or a thin line on the dark editor background.
    static func onDark(_ index: Int) -> Color {
        let c = LoopPalette.hsb(index)
        return Color(hue: c.hue, saturation: min(c.saturation, 0.7), brightness: max(c.brightness, 0.92))
    }

    /// Black or white, whichever reads better on the solid loop color.
    static func text(on index: Int) -> Color {
        let c = LoopPalette.hsb(index)
        let rgb = NSColor(hue: c.hue, saturation: c.saturation, brightness: c.brightness, alpha: 1).usingColorSpace(.sRGB)!
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance > 0.28 ? .black : .white
    }
}

/// A loop's color swatch; clicking it opens the 36-color grid.
struct LoopColorSwatch: View {
    let colorIndex: Int
    let number: Int
    let choose: (Int) -> Void
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Circle().fill(LoopColors.fill(colorIndex)).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Loop \(number) color: \(LoopPalette.name(colorIndex))")
        .accessibilityLabel("Loop \(number) color").accessibilityValue(LoopPalette.name(colorIndex))
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            LoopColorGrid(colorIndex: colorIndex) { choose($0); picking = false }
        }
    }
}

/// The 36 loop colors: hues across, vivid / deep / pale down. The current color is ringed in white.
struct LoopColorGrid: View {
    let colorIndex: Int
    let choose: (Int) -> Void

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<LoopPalette.toneCount, id: \.self) { tone in
                GridRow {
                    ForEach(0..<LoopPalette.hueCount, id: \.self) { hue in
                        let index = tone * LoopPalette.hueCount + hue
                        Button { choose(index) } label: {
                            RoundedRectangle(cornerRadius: 4).fill(LoopColors.fill(index)).frame(width: 20, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: index == colorIndex ? 2 : 0))
                        }
                        .buttonStyle(.plain).help(LoopPalette.name(index)).accessibilityLabel(LoopPalette.name(index))
                        .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                    }
                }
            }
        }.padding(10)
    }
}
