import SwiftUI

/// The AI page of the Settings window: the OpenRouter key, and which vision model does the
/// colour work. The naming model sits on the File Names page, beside the names it shapes.
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
                            result = "Saved"
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
            Section {
                Text("The key is kept in the Keychain, never in a file or this repository. Leave the custom endpoint empty to use OpenRouter.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { apiKey = (try? OpenRouterKeyStore.read()) ?? "" }
        .onDisappear { result = nil }
        .alert("Could not save API key", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var usesOpenRouter: Bool {
        let endpoint = model.colorProviderEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isEmpty || URL(string: endpoint)?.host?.lowercased() == "openrouter.ai"
    }

    private func visionModelPicker(selection: Binding<String>) -> some View {
        Picker("Model", selection: selection) {
            if selection.wrappedValue.isEmpty {
                Text("Choose a model").tag("")
            } else if !VisionModel.all.contains(where: { $0.id == selection.wrappedValue }) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
            ForEach(VisionModel.all, id: \.id) { option in
                Text(option.name).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
