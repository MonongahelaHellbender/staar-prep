import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var selectedTab: ContentView.Tab

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Your Executive Assistant")
                            .font(.largeTitle.bold())
                        Text(dateString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    // Status Card
                    StatusCard()

                    // Active Focus Task (if set)
                    if !store.currentFocusTask.isEmpty {
                        ActiveFocusCard(selectedTab: $selectedTab)
                    }

                    // Overwhelm SOS — prominent
                    Button {
                        store.sendOverwhelmSOS()
                        selectedTab = .conversation
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sos")
                                .font(.title3.bold())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overwhelmed?")
                                    .font(.subheadline.bold())
                                Text("Get ONE clear next action from your assistant")
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.red.gradient)
                        .cornerRadius(16)
                    }

                    // Quick Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Actions")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            QuickActionButton(
                                icon: "mic.fill",
                                title: "Start Listening",
                                color: .indigo
                            ) {
                                selectedTab = .conversation
                                if !store.isListening { store.startListening() }
                            }

                            QuickActionButton(
                                icon: "bolt.fill",
                                title: store.agentModeEnabled ? "Agent: ON" : "Agent Mode",
                                color: store.agentModeEnabled ? .orange : .purple
                            ) {
                                store.agentModeEnabled.toggle()
                                selectedTab = .conversation
                            }

                            QuickActionButton(
                                icon: "scope",
                                title: "Focus Mode",
                                color: .teal
                            ) {
                                selectedTab = .focus
                            }

                            QuickActionButton(
                                icon: "plus.bubble.fill",
                                title: "New Chat",
                                color: .blue
                            ) {
                                store.newConversation()
                                selectedTab = .conversation
                            }
                        }
                    }

                    // Recent Conversations
                    if !store.conversations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Conversations")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            ForEach(store.conversations.prefix(3)) { conversation in
                                RecentConversationRow(conversation: conversation) {
                                    store.selectConversation(conversation)
                                    selectedTab = .conversation
                                }
                            }
                        }
                    }

                    // API Key Warning
                    if store.apiKey.isEmpty {
                        APIKeyWarningCard { selectedTab = .settings }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Active Focus Card

struct ActiveFocusCard: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var selectedTab: ContentView.Tab

    var body: some View {
        Button {
            selectedTab = .focus
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .foregroundColor(.teal)
                    .frame(width: 36, height: 36)
                    .background(Color.teal.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently Focusing On")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(store.currentFocusTask)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !store.focusTasks.isEmpty {
                        let completed = store.focusTasks.filter { $0.isCompleted }.count
                        Text("\(completed)/\(store.focusTasks.count) steps done")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.teal.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.2), lineWidth: 1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isListening ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(store.isListening ? "Listening..." : "Standby")
                        .font(.subheadline.bold())
                }
                Text("\(store.conversations.count) conversations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if store.agentModeEnabled {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    let personality = ConversationStore.AssistantPersonality(rawValue: store.assistantPersonality)
                    Text(personality?.displayName ?? "Executive")
                        .font(.subheadline.bold())
                        .foregroundColor(.indigo)
                }
                Text(store.agentModeEnabled ? "Agent Mode" : "Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Reusable Components

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
}

struct RecentConversationRow: View {
    let conversation: Conversation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundColor(.indigo)
                    .frame(width: 36, height: 36)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(conversation.messages.count) messages · \(conversation.updatedAt.relativeString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

struct APIKeyWarningCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key Required")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Tap to add your Claude API key in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            .cornerRadius(12)
        }
    }
}

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
