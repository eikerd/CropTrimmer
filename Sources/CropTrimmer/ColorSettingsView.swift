import SwiftUI

struct ColorSettingsView: View {
    @ObservedObject var model: EditorModel
    @State private var apiKey = ""
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API key", text: $apiKey)
                    .onChange(of: apiKey) { _, _ in result = nil }
                HStack {
                    if let result { Text(result).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Save key") {
                        do {
                            try OpenRouterKeyStore.save(apiKey)
                            if model.colorProviderEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                model.colorProviderEndpoint = "https://openrouter.ai/api/v1/chat/completions"
                            }
                            apiKey = ""
                            result = "Saved in Keychain"
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("Color model") {
                if usesOpenRouter {
                    visionModelPicker(selection: $model.colorProviderModel)
                } else {
                    TextField("Model", text: $model.colorProviderModel)
                }
                DisclosureGroup("Custom provider") {
                    TextField("Endpoint", text: $model.colorProviderEndpoint)
                }
            }
            Section("File naming · OpenRouter") {
                visionModelPicker(selection: $model.filenameModel)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 390)
        .preferredColorScheme(.dark)
        .onDisappear { apiKey = ""; result = nil }
        .alert("Could not save API key", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var usesOpenRouter: Bool {
        let endpoint = model.colorProviderEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isEmpty || URL(string: endpoint)?.host?.lowercased() == "openrouter.ai"
    }

    // These models accept image inputs and return text for both suggestion protocols.
    private static let visionModels = [
        (id: "google/gemini-2.5-flash-lite", name: "Google · Gemini 2.5 Flash Lite"),
        (id: "openai/gpt-4.1-mini", name: "OpenAI · GPT-4.1 Mini"),
        (id: "anthropic/claude-haiku-4.5", name: "Anthropic · Claude Haiku 4.5")
    ]

    private func visionModelPicker(selection: Binding<String>) -> some View {
        Picker("Model", selection: selection) {
            if selection.wrappedValue.isEmpty {
                Text("Choose a model").tag("")
            } else if !Self.visionModels.contains(where: { $0.id == selection.wrappedValue }) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
            ForEach(Self.visionModels, id: \.id) { option in
                Text(option.name).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
