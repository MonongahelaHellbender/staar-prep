import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var showAPIKey = false
    @State private var tempAPIKey = ""
    @State private var showingClearAlert = false
    @State private var testingAPI = false
    @State private var apiTestResult: String?
    @FocusState private var apiKeyFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                // API Configuration
                Section {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude API Key")
                                .font(.subheadline.bold())
                            if store.apiKey.isEmpty {
                                Text("Required to use the assistant")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("••••••••" + String(store.apiKey.suffix(4)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(store.apiKey.isEmpty ? "Add" : "Edit") {
                            tempAPIKey = store.apiKey
                            showAPIKey = true
                        }
                        .font(.subheadline)
                        .foregroundColor(.indigo)
                    }

                    if !store.apiKey.isEmpty {
                        Button {
                            testAPIKey()
                        } label: {
                            HStack {
                                Image(systemName: testingAPI ? "hourglass" : "checkmark.circle")
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                Text(testingAPI ? "Testing..." : "Test Connection")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let result = apiTestResult {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(result.contains("✓") ? .green : .red)
                                }
                            }
                        }
                        .disabled(testingAPI)
                    }
                } header: {
                    Text("API Configuration")
                } footer: {
                    Text("Your API key is stored securely on device. Get your key at console.anthropic.com")
                }

                // Assistant Personality
                Section {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        Text("Personality")
                        Spacer()
                        Picker("", selection: $store.assistantPersonality) {
                            ForEach(ConversationStore.AssistantPersonality.allCases, id: \.rawValue) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        Text("Context Window")
                        Spacer()
                        Stepper("\(store.contextWindowSize) msgs", value: $store.contextWindowSize, in: 4...50, step: 2)
                            .labelsHidden()
                        Text("\(store.contextWindowSize)")
                            .foregroundColor(.secondary)
                            .frame(width: 36)
                    }
                } header: {
                    Text("Assistant")
                }

                // Listening Settings
                Section {
                    Toggle(isOn: $store.autoListenEnabled) {
                        HStack {
                            Image(systemName: "mic.badge.auto.fill")
                                .foregroundColor(.indigo)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Listen")
                                Text("Automatically start listening when app opens")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.indigo)
                } header: {
                    Text("Listening")
                }

                // About
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "cpu.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        Text("AI Model")
                        Spacer()
                        Text("claude-opus-4-6")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Text("About")
                }

                // Data Management
                Section {
                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .frame(width: 28)
                            Text("Clear All Conversations")
                        }
                    }
                } header: {
                    Text("Data")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAPIKey) {
                APIKeyInputSheet(apiKey: $tempAPIKey) { key in
                    store.apiKey = key
                    showAPIKey = false
                    apiTestResult = nil
                }
            }
            .alert("Clear All Conversations", isPresented: $showingClearAlert) {
                Button("Clear All", role: .destructive) {
                    store.conversations = []
                    store.activeConversation = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All conversation history will be permanently deleted.")
            }
        }
    }

    private func testAPIKey() {
        testingAPI = true
        apiTestResult = nil
        let service = ClaudeService()
        let testMsg = Message(role: .user, content: "Hello, respond with just 'ok'.")
        service.sendMessage(
            messages: [testMsg],
            systemPrompt: "You are a test assistant.",
            apiKey: store.apiKey
        ) { result in
            DispatchQueue.main.async {
                testingAPI = false
                switch result {
                case .success: apiTestResult = "✓ Connected"
                case .failure(let error): apiTestResult = "✗ \(error.localizedDescription)"
                }
            }
        } onStream: { _ in }
    }
}

struct APIKeyInputSheet: View {
    @Binding var apiKey: String
    let onSave: (String) -> Void
    @State private var showKey = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Enter API Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your API key starts with 'sk-ant-'")
                        Text("It is stored securely in device keychain and never leaves your device.")
                    }
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .font(.headline)
                }
            }
        }
    }
}
