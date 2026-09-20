import Foundation

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
