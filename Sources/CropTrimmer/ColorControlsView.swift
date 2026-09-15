import SwiftUI
import CropTrimmerCore

struct ColorControlsView: View {
    @ObservedObject var model: EditorModel
    let loopID: UUID
    let number: Int
    @State private var expanded = false

    private var edit: EditSettings { model.loops.ranges.first { $0.id == loopID }?.settings ?? EditSettings() }

    var body: some View {
        DisclosureGroup("Color correction", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Enable", isOn: binding(\.enabled)).toggleStyle(.checkbox)
                    .accessibilityLabel("Loop \(number) enable color correction")
                colorSlider("Black point", key: \.blackPoint, range: 0...0.95)
                colorSlider("White point", key: \.whitePoint, range: 0.05...1)
                colorSlider("Gamma", key: \.gamma, range: 0.25...4)
                colorSlider("Saturation", key: \.saturation, range: 0...2)
                HStack {
                    Spacer()
                    Button("Reset") { update { $0.color = ColorSettings() } }
                        .accessibilityLabel("Reset Loop \(number) color correction")
                }
            }.padding(.top, 4)
        }
        .font(.system(size: 10))
        .onAppear { expanded = edit.color.enabled && !edit.color.isIdentity }
    }

    private func colorSlider(_ label: String, key: WritableKeyPath<ColorSettings, Float>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 5) {
            Text(label).frame(width: 72, alignment: .leading)
            Slider(value: Binding(get: { Double(edit.color[keyPath: key]) }, set: { value in
                update { $0.color[keyPath: key] = Float(value) }
            }), in: range)
            Text(String(format: label == "Gamma" ? "%.2f" : "%.3f", edit.color[keyPath: key]))
                .monospacedDigit().frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loop \(number) \(label)")
        .accessibilityValue(String(format: "%.3f", edit.color[keyPath: key]))
    }

    private func binding<Value>(_ key: WritableKeyPath<ColorSettings, Value>) -> Binding<Value> {
        Binding(get: { edit.color[keyPath: key] }, set: { value in update { $0.color[keyPath: key] = value } })
    }

    private func update(_ change: (inout EditSettings) -> Void) {
        var next = edit
        change(&next)
        _ = model.updateLoop(id: loopID, settings: next)
    }
}
