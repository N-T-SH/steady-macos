import SwiftUI

struct PreferencesView: View {
    // API key stored in Keychain
    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    // LLM config stored in UserDefaults
    @AppStorage("llm.providerURL") private var providerURL = LLMConfig.default.providerURL
    @AppStorage("llm.classificationModel") private var classificationModel = LLMConfig.default.classificationModel
    @AppStorage("llm.conversationModel") private var conversationModel = LLMConfig.default.conversationModel

    // Obsidian integration
    @AppStorage("obsidian.vaultPath") private var vaultPath = ""
    @AppStorage("obsidian.enabled") private var obsidianEnabled = false

    // Notifications
    @AppStorage("notifications.enabled") private var notificationsEnabled = true

    var body: some View {
        TabView {
            apiTab
                .tabItem { Label("API", systemImage: "key") }

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }

            obsidianTab
                .tabItem { Label("Obsidian", systemImage: "doc.text") }
        }
        .padding()
        .frame(width: 480, height: 320)
        .onAppear { loadAPIKey() }
    }

    // MARK: - API Tab

    private var apiTab: some View {
        Form {
            Section {
                LabeledContent("Provider URL") {
                    TextField("https://openrouter.ai/api/v1", text: $providerURL)
                        .frame(width: 280)
                }

                LabeledContent("API Key") {
                    HStack {
                        SecureField("sk-or-…", text: $apiKey)
                            .frame(width: 240)
                        Button(apiKeySaved ? "Saved ✓" : "Save") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.isEmpty)
                    }
                }

                LabeledContent("Classification Model") {
                    TextField("e.g. google/gemini-flash-2.0", text: $classificationModel)
                        .frame(width: 280)
                }

                LabeledContent("Conversation Model") {
                    TextField("e.g. anthropic/claude-haiku-4-5", text: $conversationModel)
                        .frame(width: 280)
                }
            } header: {
                Text("OpenRouter / OpenAI-compatible endpoint")
                    .font(.headline)
            } footer: {
                Text("Models are passed directly to the provider. Restart the app after changing these settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Link("Get an OpenRouter API key →", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)
            }
        }
        .padding()
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $notificationsEnabled)

                Text("Steady delivers notifications passively by default (no sound, banner only). Drift alerts appear after the grace period (2 min) of off-task browsing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Notification Settings")
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Obsidian Tab

    private var obsidianTab: some View {
        Form {
            Section {
                Toggle("Sync sessions to Obsidian vault", isOn: $obsidianEnabled)

                LabeledContent("Vault Path") {
                    HStack {
                        TextField("/Users/you/Obsidian/MyVault", text: $vaultPath)
                            .frame(width: 220)
                            .disabled(!obsidianEnabled)
                        Button("Browse…") { browseForVault() }
                            .disabled(!obsidianEnabled)
                    }
                }

                Text("Session notes are written to \(vaultPath.isEmpty ? "<vault>" : vaultPath)/6. Habit Tracking/Sessions/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Obsidian Integration")
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func loadAPIKey() {
        apiKey = (try? KeychainHelper.load(key: LLMConfig.default.apiKeyIdentifier)) ?? ""
        apiKeySaved = !apiKey.isEmpty
    }

    private func saveAPIKey() {
        try? KeychainHelper.save(key: LLMConfig.default.apiKeyIdentifier, data: apiKey)
        withAnimation { apiKeySaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
    }

    private func browseForVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
        }
    }
}
