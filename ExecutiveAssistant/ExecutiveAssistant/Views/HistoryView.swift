import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: Conversation?

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return store.conversations
        }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if store.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Conversations Yet")
                            .font(.title3.bold())
                        Text("Your conversation history will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(groupedConversations, id: \.key) { group in
                            Section(header: Text(group.key).font(.caption).textCase(.uppercase)) {
                                ForEach(group.value) { conversation in
                                    ConversationHistoryRow(conversation: conversation)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                conversationToDelete = conversation
                                                showingDeleteAlert = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .onTapGesture {
                                            store.selectConversation(conversation)
                                        }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search conversations")
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.newConversation()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let conv = conversationToDelete {
                        store.deleteConversation(conv)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This conversation will be permanently deleted.")
            }
        }
    }

    private var groupedConversations: [(key: String, value: [Conversation])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredConversations) { conversation -> String in
            if calendar.isDateInToday(conversation.updatedAt) { return "Today" }
            if calendar.isDateInYesterday(conversation.updatedAt) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: conversation.updatedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }
}

struct ConversationHistoryRow: View {
    @EnvironmentObject var store: ConversationStore
    let conversation: Conversation

    var lastMessage: Message? {
        conversation.messages.last
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.indigo)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.updatedAt.relativeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let msg = lastMessage {
                    Text(msg.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text("\(conversation.messages.count) messages")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .background(
            store.activeConversation?.id == conversation.id
            ? Color.indigo.opacity(0.05)
            : Color.clear
        )
        .cornerRadius(8)
    }
}
