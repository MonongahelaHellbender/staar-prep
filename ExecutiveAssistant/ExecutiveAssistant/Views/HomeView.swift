import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var selectedTab: ContentView.Tab
    @State private var showingQuickAction = false
    @State private var quickActionText = ""

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
                VStack(alignment: .leading, spacing: 24) {

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
                                if !store.isListening {
                                    store.startListening()
                                }
                            }

                            QuickActionButton(
                                icon: "plus.bubble.fill",
                                title: "New Chat",
                                color: .blue
                            ) {
                                store.newConversation()
                                selectedTab = .conversation
                            }

                            QuickActionButton(
                                icon: "doc.badge.plus",
                                title: "Upload File",
                                color: .green
                            ) {
                                selectedTab = .conversation
                            }

                            QuickActionButton(
                                icon: "list.bullet.clipboard.fill",
                                title: "Summarize",
                                color: .orange
                            ) {
                                store.newConversation()
                                store.sendMessage("Please summarize everything we've discussed today and list any action items.")
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
                        APIKeyWarningCard {
                            selectedTab = .settings
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
        }
    }
}

struct StatusCard: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isListening ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .overlay(
                            store.isListening ?
                            Circle()
                                .stroke(Color.green.opacity(0.4), lineWidth: 4)
                                .scaleEffect(store.isListening ? 1.5 : 1)
                                .animation(.easeInOut(duration: 1).repeatForever(), value: store.isListening)
                            : nil
                        )
                    Text(store.isListening ? "Listening..." : "Standby")
                        .font(.subheadline.bold())
                }
                Text("\(store.conversations.count) conversations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                let personality = ConversationStore.AssistantPersonality(rawValue: store.assistantPersonality)
                Text(personality?.displayName ?? "Executive")
                    .font(.subheadline.bold())
                    .foregroundColor(.indigo)
                Text("Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
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
