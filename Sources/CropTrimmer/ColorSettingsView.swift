import AppKit
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
            Section("File naming · OpenRouter") {
                visionModelPicker(selection: $model.filenameModel)
            }
            Section("Crop") {
                HStack {
                    Text("Default size")
                    Spacer()
                    TextField("Width", value: $model.defaultCropWidth, format: .number)
                        .frame(width: 60).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Default crop width in pixels")
                    Text("×").foregroundStyle(.secondary)
                    TextField("Height", value: $model.defaultCropHeight, format: .number)
                        .frame(width: 60).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Default crop height in pixels")
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismissSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 510)
        .preferredColorScheme(.dark)
        .onAppear { apiKey = (try? OpenRouterKeyStore.read()) ?? "" }
        .onDisappear { result = nil }
        .alert("Could not save API key", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // The Settings scene has no dismiss action of its own, so close the window
    // hosting this view directly.
    private func dismissSettings() {
        let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first { $0.title == "Crop Trimmer Settings" }
        settingsWindow?.performClose(nil)
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
