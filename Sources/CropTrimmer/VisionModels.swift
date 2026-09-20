import SwiftUI

/// OpenRouter models that accept image input and return text, so they serve both
/// the color and filename suggestion protocols. Settings and the rename panel
/// read the same list, so the two pickers can never drift apart.
struct VisionModel: Identifiable, Hashable {
    let id: String
    let name: String

    static let all: [VisionModel] = [
        VisionModel(id: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite"),
        VisionModel(id: "openai/gpt-4.1-mini", name: "GPT-4.1 Mini"),
        VisionModel(id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5"),
        VisionModel(id: "qwen/qwen3-vl-235b-a22b-instruct", name: "Qwen3 VL 235B"),
        VisionModel(id: "qwen/qwen3-vl-30b-a3b-instruct", name: "Qwen3 VL 30B"),
        VisionModel(id: "qwen/qwen3-vl-8b-instruct", name: "Qwen3 VL 8B")
    ]
}

/// A picker over `VisionModel.all` that never hides what is actually selected. A model id is
/// persisted forever, and the list has already grown from three entries to six, so a stored id
/// that is later renamed or dropped would otherwise leave the menu showing nothing at all.
/// Keeping the raw id as its own entry means the setting stays visible and changeable.
struct VisionModelPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            if selection.isEmpty {
                Text("Choose a model").tag("")
            } else if !VisionModel.all.contains(where: { $0.id == selection }) {
                Text(selection).tag(selection)
            }
            ForEach(VisionModel.all, id: \.id) { option in
                Text(option.name).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
