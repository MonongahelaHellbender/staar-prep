import Foundation
import Combine
import SwiftUI

class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var isListening: Bool = false
    @Published var transcribedText: String = ""
    @Published var pendingAttachments: [AttachmentItem] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    // Settings
    @AppStorage("claudeAPIKey") var apiKey: String = ""
    @AppStorage("assistantPersonality") var assistantPersonality: String = AssistantPersonality.executive.rawValue
    @AppStorage("autoListenEnabled") var autoListenEnabled: Bool = false
    @AppStorage("contextWindowSize") var contextWindowSize: Int = 20

    private let claudeService = ClaudeService()
    private let audioService = AudioService()
    private var cancellables = Set<AnyCancellable>()

    enum AssistantPersonality: String, CaseIterable {
        case executive = "executive"
        case concise = "concise"
        case detailed = "detailed"
        case friendly = "friendly"

        var displayName: String {
            switch self {
            case .executive: return "Executive"
            case .concise: return "Concise"
            case .detailed: return "Detailed"
            case .friendly: return "Friendly"
            }
        }

        var systemPrompt: String {
            switch self {
            case .executive:
                return """
                You are an elite executive assistant with the judgment and discretion of a top-tier C-suite advisor. \
                You listen to the user's daily life, meetings, and conversations to help them stay organized, \
                make better decisions, and manage their time effectively. You are proactive, anticipate needs, \
                summarize key action items, flag important decisions, draft communications, and provide concise \
                briefings. You speak with confidence and professionalism. Keep responses actionable and brief \
                unless detail is requested. You have access to uploaded files and photos to provide context-aware assistance.
                """
            case .concise:
                return """
                You are a highly efficient executive assistant. Be extremely concise. Use bullet points. \
                Only essential information. Action items first. No fluff.
                """
            case .detailed:
                return """
                You are a thorough executive assistant who provides comprehensive analysis and detailed responses. \
                You listen carefully, consider all angles, and provide well-structured, in-depth assistance \
                with full context and reasoning.
                """
            case .friendly:
                return """
                You are a warm, supportive executive assistant who balances professionalism with approachability. \
                You help manage the user's daily life with encouragement and positivity while keeping them \
                on track with their goals.
                """
            }
        }
    }

    init() {
        loadConversations()
        setupAudioService()
    }

    private func setupAudioService() {
        audioService.$transcribedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.transcribedText = text
            }
            .store(in: &cancellables)

        audioService.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listening in
                self?.isListening = listening
            }
            .store(in: &cancellables)
    }

    // MARK: - Conversation Management

    func newConversation() {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        activeConversation = conversations[0]
        saveConversations()
    }

    func selectConversation(_ conversation: Conversation) {
        activeConversation = conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if activeConversation?.id == conversation.id {
            activeConversation = conversations.first
        }
        saveConversations()
    }

    // MARK: - Messaging

    func sendMessage(_ text: String, attachments: [AttachmentItem] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your Claude API key in Settings"
            return
        }

        if activeConversation == nil {
            newConversation()
        }

        let userMessage = Message(role: .user, content: text, attachments: attachments)
        appendMessage(userMessage)
        pendingAttachments = []

        let assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        appendMessage(assistantMessage)

        let personality = AssistantPersonality(rawValue: assistantPersonality) ?? .executive
        let contextMessages = buildContextMessages()

        isProcessing = true

        claudeService.sendMessage(
            messages: contextMessages,
            systemPrompt: personality.systemPrompt,
            apiKey: apiKey
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                switch result {
                case .success(let responseText):
                    self?.updateLastAssistantMessage(responseText)
                case .failure(let error):
                    self?.updateLastAssistantMessage("I encountered an error: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
                self?.saveConversations()
            }
        } onStream: { [weak self] chunk in
            DispatchQueue.main.async {
                self?.appendToLastAssistantMessage(chunk)
            }
        }
    }

    private func buildContextMessages() -> [Message] {
        guard let conversation = activeConversation else { return [] }
        let messages = conversation.messages.filter { !$0.isStreaming }
        let limit = max(2, contextWindowSize)
        return Array(messages.suffix(limit))
    }

    private func appendMessage(_ message: Message) {
        guard let idx = conversations.firstIndex(where: { $0.id == activeConversation?.id }) else { return }
        conversations[idx].messages.append(message)
        conversations[idx].updatedAt = Date()

        // Auto-title from first user message
        if conversations[idx].messages.filter({ $0.role == .user }).count == 1,
           let firstUserMsg = conversations[idx].messages.first(where: { $0.role == .user }) {
            let preview = String(firstUserMsg.content.prefix(40))
            conversations[idx].title = preview.isEmpty ? "New Conversation" : preview
        }

        activeConversation = conversations[idx]
    }

    private func updateLastAssistantMessage(_ text: String) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == activeConversation?.id }),
              let msgIdx = conversations[convIdx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[convIdx].messages[msgIdx].content = text
        conversations[convIdx].messages[msgIdx].isStreaming = false
        activeConversation = conversations[convIdx]
    }

    private func appendToLastAssistantMessage(_ chunk: String) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == activeConversation?.id }),
              let msgIdx = conversations[convIdx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[convIdx].messages[msgIdx].content += chunk
        activeConversation = conversations[convIdx]
    }

    // MARK: - Audio

    func startListening() {
        audioService.startListening()
    }

    func stopListening() {
        audioService.stopListening()
    }

    func sendTranscription() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let attachments = pendingAttachments
        transcribedText = ""
        sendMessage(text, attachments: attachments)
    }

    // MARK: - Attachments

    func addAttachment(_ attachment: AttachmentItem) {
        pendingAttachments.append(attachment)
    }

    func removeAttachment(_ attachment: AttachmentItem) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Persistence

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            UserDefaults.standard.set(data, forKey: "conversations")
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: "conversations") else { return }
        do {
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
            activeConversation = conversations.first
        } catch {
            print("Failed to load conversations: \(error)")
        }
    }
}
