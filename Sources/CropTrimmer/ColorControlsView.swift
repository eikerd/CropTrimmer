import SwiftUI
import CropTrimmerCore

struct ColorControlsView: View {
    @ObservedObject var model: EditorModel
    let loopID: UUID
    let number: Int
    @State private var expanded = false

    private var edit: EditSettings { model.loops.ranges.first { $0.id == loopID }?.settings ?? EditSettings() }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 5) {
                colorSlider("Black point", key: \.blackPoint, range: 0...max(0, min(0.95, Double(edit.color.whitePoint) - 1.0 / 255.0)))
                colorSlider("White point", key: \.whitePoint, range: min(1, max(0.05, Double(edit.color.blackPoint) + 1.0 / 255.0))...1)
                colorSlider("Gamma", key: \.gamma, range: 0.25...4)
                colorSlider("Saturation", key: \.saturation, range: 0...2)
                HStack {
                    Spacer()
                    Button("Reset") { update { $0.color = ColorSettings() } }
                        .accessibilityLabel("Reset Loop \(number) color correction")
                }
            }.padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text("Color correction")
                Spacer(minLength: 8)
                Toggle("Enable", isOn: binding(\.enabled)).toggleStyle(.checkbox)
                    .accessibilityLabel("Loop \(number) enable color correction")
            }
            .padding(.leading, 6)
        }
        .font(.system(size: 12))
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
