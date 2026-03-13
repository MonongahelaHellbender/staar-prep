import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var showAPIKey = false
    @State private var tempAPIKey = ""
    @State private var showingClearAlert = false
    @State private var testingAPI = false
    @State private var apiTestResult: String?

    var body: some View {
        NavigationView {
            Form {
                // API Configuration
                Section {
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(.indigo).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude API Key").font(.subheadline.bold())
                            if store.apiKey.isEmpty {
                                Text("Required to use the assistant")
                                    .font(.caption).foregroundColor(.orange)
                            } else {
                                Text("••••••••" + String(store.apiKey.suffix(4)))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(store.apiKey.isEmpty ? "Add" : "Edit") {
                            tempAPIKey = store.apiKey
                            showAPIKey = true
                        }
                        .font(.subheadline).foregroundColor(.indigo)
                    }

                    if !store.apiKey.isEmpty {
                        Button { testAPIKey() } label: {
                            HStack {
                                Image(systemName: testingAPI ? "hourglass" : "checkmark.circle")
                                    .foregroundColor(.green).frame(width: 28)
                                Text(testingAPI ? "Testing..." : "Test Connection").foregroundColor(.primary)
                                Spacer()
                                if let result = apiTestResult {
                                    Text(result).font(.caption)
                                        .foregroundColor(result.contains("✓") ? .green : .red)
                                }
                            }
                        }
                        .disabled(testingAPI)
                    }
                } header: {
                    Text("API Configuration")
                } footer: {
                    Text("Your API key is stored securely on device. Get yours at console.anthropic.com")
                }

                // Agent Mode
                Section {
                    Toggle(isOn: $store.agentModeEnabled) {
                        HStack {
                            Image(systemName: "bolt.fill").foregroundColor(.orange).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Agent Mode")
                                Text("Let the assistant take actions on your phone")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.orange)

                    if store.agentModeEnabled {
                        HStack {
                            Image(systemName: "info.circle").foregroundColor(.secondary).frame(width: 28)
                            Text("Agent mode uses non-streaming API calls and may require additional permissions (Calendar, Reminders, Contacts).")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Agent Mode")
                } footer: {
                    Text("When enabled, Claude can make phone calls, send messages, create calendar events, set reminders, search contacts, open apps, and more.")
                }

                // Focus & ADD Support
                Section {
                    HStack {
                        Image(systemName: "timer").foregroundColor(.indigo).frame(width: 28)
                        Text("Pomodoro Duration")
                        Spacer()
                        Picker("", selection: $store.pomodoroDuration) {
                            Text("15 min").tag(15)
                            Text("20 min").tag(20)
                            Text("25 min").tag(25)
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Focus & ADD Support")
                } footer: {
                    Text("The ADHD Coach personality mode provides structured, brief responses with one action at a time. Select it below.")
                }

                // Assistant
                Section {
                    HStack {
                        Image(systemName: "person.fill").foregroundColor(.indigo).frame(width: 28)
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
                        Image(systemName: "text.bubble.fill").foregroundColor(.indigo).frame(width: 28)
                        Text("Context Window")
                        Spacer()
                        Stepper("", value: $store.contextWindowSize, in: 4...50, step: 2)
                            .labelsHidden()
                        Text("\(store.contextWindowSize) msgs")
                            .foregroundColor(.secondary)
                            .frame(width: 60)
                    }

                    Toggle(isOn: $store.autoListenEnabled) {
                        HStack {
                            Image(systemName: "mic.badge.auto.fill").foregroundColor(.indigo).frame(width: 28)
                            Text("Auto-Listen on Open")
                        }
                    }
                    .tint(.indigo)
                } header: {
                    Text("Assistant")
                }

                // About
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill").foregroundColor(.indigo).frame(width: 28)
                        Text("Version")
                        Spacer()
                        Text("1.1.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "cpu.fill").foregroundColor(.indigo).frame(width: 28)
                        Text("AI Model")
                        Spacer()
                        Text("claude-opus-4-6").font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }

                // Data Management
                Section {
                    Button(role: .destructive) { showingClearAlert = true } label: {
                        HStack {
                            Image(systemName: "trash.fill").frame(width: 28)
                            Text("Clear All Conversations")
                        }
                    }
                    Button(role: .destructive) { store.focusTasks.removeAll() } label: {
                        HStack {
                            Image(systemName: "checklist").frame(width: 28)
                            Text("Clear Focus Tasks")
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
        let testMsg = Message(role: .user, content: "Reply with just 'ok'.")
        service.sendMessage(messages: [testMsg], systemPrompt: "Be brief.", apiKey: store.apiKey) { result in
            DispatchQueue.main.async {
                testingAPI = false
                switch result {
                case .success: apiTestResult = "✓ Connected"
                case .failure(let e): apiTestResult = "✗ \(e.localizedDescription)"
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
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Enter API Key")
                } footer: {
                    Text("Your key starts with 'sk-ant-' and is stored securely on device only.")
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
