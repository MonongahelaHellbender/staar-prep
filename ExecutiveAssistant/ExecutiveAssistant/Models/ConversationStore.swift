import Foundation
import Combine
import SwiftUI

// MARK: - Focus Task

struct FocusTask: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
    var estimatedMinutes: Int?
    let createdAt: Date = Date()
}

// MARK: - Conversation Store

class ConversationStore: ObservableObject {
    // Conversations
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?

    // Listening
    @Published var isListening: Bool = false
    @Published var transcribedText: String = ""

    // Attachments
    @Published var pendingAttachments: [AttachmentItem] = []

    // Processing state
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    // Focus / ADD
    @Published var focusTasks: [FocusTask] = []
    @Published var currentFocusTask: String = ""

    // Settings (persisted)
    @AppStorage("claudeAPIKey") var apiKey: String = ""
    @AppStorage("assistantPersonality") var assistantPersonality: String = AssistantPersonality.executive.rawValue
    @AppStorage("autoListenEnabled") var autoListenEnabled: Bool = false
    @AppStorage("contextWindowSize") var contextWindowSize: Int = 20
    @AppStorage("agentModeEnabled") var agentModeEnabled: Bool = false
    @AppStorage("pomodoroDuration") var pomodoroDuration: Int = 25

    private let claudeService = ClaudeService()
    let audioService = AudioService()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Personality Modes

    enum AssistantPersonality: String, CaseIterable {
        case executive = "executive"
        case adhdCoach = "adhd_coach"
        case concise = "concise"
        case detailed = "detailed"
        case friendly = "friendly"

        var displayName: String {
            switch self {
            case .executive: return "Executive"
            case .adhdCoach: return "ADHD Coach"
            case .concise: return "Concise"
            case .detailed: return "Detailed"
            case .friendly: return "Friendly"
            }
        }

        var systemPrompt: String {
            switch self {
            case .executive:
                return """
                You are an elite executive assistant. You listen to the user's daily life, meetings, \
                and conversations to help them stay organized, make better decisions, and manage time. \
                You are proactive, anticipate needs, summarize key action items, flag important decisions, \
                draft communications, and provide concise briefings. Speak with confidence and professionalism. \
                Keep responses actionable and brief unless detail is requested. \
                You have access to uploaded files and photos to provide context-aware assistance.
                """
            case .adhdCoach:
                return """
                You are an expert executive assistant and ADHD coach. Your user has ADD/ADHD, adapt accordingly:
                - Keep ALL responses SHORT (3-5 lines max) unless detail is explicitly requested
                - Start with ONE clear, concrete action — never lead with a list of options
                - Break any multi-step task into numbered micro-steps, each under 15 min
                - Add time estimates: "This takes ~10 min"
                - Celebrate wins enthusiastically but briefly: "Great job finishing that!"
                - Suggest a Pomodoro timer when relevant: "Set a 25-min timer and just start"
                - Never present more than 3 options at once
                - If the user seems overwhelmed, acknowledge briefly then give ONE action
                - Use bullet points, not paragraphs
                - End with the single most important next action
                - For quick captures, organize into: [Reminder], [Task], or [Note] clearly
                """
            case .concise:
                return """
                You are a highly efficient executive assistant. Be extremely concise. Use bullet points. \
                Only essential information. Action items first. No filler.
                """
            case .detailed:
                return """
                You are a thorough executive assistant who provides comprehensive analysis. \
                Listen carefully, consider all angles, and provide well-structured in-depth assistance \
                with full context and reasoning.
                """
            case .friendly:
                return """
                You are a warm, supportive executive assistant who balances professionalism with \
                approachability. Help manage the user's daily life with encouragement and positivity \
                while keeping them on track with their goals.
                """
            }
        }
    }

    // MARK: - Init

    init() {
        loadConversations()
        loadFocusTasks()
        setupAudioService()
    }

    private func setupAudioService() {
        audioService.$transcribedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.transcribedText = text }
            .store(in: &cancellables)

        audioService.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listening in self?.isListening = listening }
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

    // MARK: - Send Message

    func sendMessage(_ text: String, attachments: [AttachmentItem] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your Claude API key in Settings"
            return
        }

        if activeConversation == nil { newConversation() }

        let userMessage = Message(role: .user, content: text, attachments: attachments)
        appendMessage(userMessage)
        pendingAttachments = []

        let assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        appendMessage(assistantMessage)

        isProcessing = true

        if agentModeEnabled {
            runAgentTask()
        } else {
            runStreamingTask()
        }
    }

    // MARK: - Streaming (non-agent)

    private func runStreamingTask() {
        let personality = AssistantPersonality(rawValue: assistantPersonality) ?? .executive
        let contextMessages = buildContextMessages()

        claudeService.sendMessage(
            messages: contextMessages,
            systemPrompt: personality.systemPrompt,
            apiKey: apiKey
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                switch result {
                case .success(let text): self?.updateLastAssistantMessage(text)
                case .failure(let error):
                    self?.updateLastAssistantMessage("Error: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
                self?.saveConversations()
            }
        } onStream: { [weak self] chunk in
            DispatchQueue.main.async { self?.appendToLastAssistantMessage(chunk) }
        }
    }

    // MARK: - Agent Task

    private func runAgentTask() {
        let personality = AssistantPersonality(rawValue: assistantPersonality) ?? .executive
        let systemPrompt = personality.systemPrompt + AgentService.agentSystemPromptAddition
        let contextMessages = buildContextMessages()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let finalText = await AgentService.shared.runAgent(
                messages: contextMessages,
                systemPrompt: systemPrompt,
                apiKey: self.apiKey
            ) { [weak self] event in
                guard let self else { return }
                switch event {
                case .textChunk(let chunk):
                    self.appendToLastAssistantMessage(chunk)
                case .toolStarted(let toolName, let summary):
                    self.addAgentAction(AgentAction(
                        toolName: toolName,
                        inputSummary: summary,
                        status: .executing,
                        isError: false
                    ))
                case .toolCompleted(let toolName, let result, let isError):
                    self.updateAgentAction(toolName: toolName, result: result, isError: isError)
                }
            }

            self.isProcessing = false
            if !finalText.isEmpty { self.ensureLastAssistantHasContent(finalText) }
            self.finalizeLastAssistantMessage()
            self.saveConversations()
        }
    }

    // MARK: - Agent Action Helpers

    private func addAgentAction(_ action: AgentAction) {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx) else { return }
        if conversations[convIdx].messages[msgIdx].agentActions == nil {
            conversations[convIdx].messages[msgIdx].agentActions = []
        }
        conversations[convIdx].messages[msgIdx].agentActions!.append(action)
        activeConversation = conversations[convIdx]
    }

    private func updateAgentAction(toolName: String, result: String, isError: Bool) {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx),
              let actionIdx = conversations[convIdx].messages[msgIdx].agentActions?
                .lastIndex(where: { $0.toolName == toolName && $0.status == .executing })
        else { return }
        conversations[convIdx].messages[msgIdx].agentActions![actionIdx].result = result
        conversations[convIdx].messages[msgIdx].agentActions![actionIdx].status = isError ? .failed : .success
        conversations[convIdx].messages[msgIdx].agentActions![actionIdx].isError = isError
        activeConversation = conversations[convIdx]
    }

    private func ensureLastAssistantHasContent(_ text: String) {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx),
              conversations[convIdx].messages[msgIdx].content.isEmpty else { return }
        conversations[convIdx].messages[msgIdx].content = text
        activeConversation = conversations[convIdx]
    }

    private func finalizeLastAssistantMessage() {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx) else { return }
        conversations[convIdx].messages[msgIdx].isStreaming = false
        activeConversation = conversations[convIdx]
    }

    // MARK: - ADD/ADHD Shortcuts

    func sendOverwhelmSOS() {
        if activeConversation == nil { newConversation() }
        sendMessage("I'm overwhelmed and don't know where to start. What is the SINGLE most important thing I should do right now? One action only, be very brief and specific.")
    }

    func extractTasksFromLastResponse() {
        sendMessage("""
        Based on your last response, extract the action steps as a JSON array. \
        Return ONLY valid JSON, nothing else: \
        [{"title":"Step description","estimatedMinutes":15},{"title":"Step 2","estimatedMinutes":10}]
        """)
    }

    func parseAndSaveFocusTasks(from jsonString: String) {
        struct TaskJSON: Decodable {
            let title: String
            let estimatedMinutes: Int?
        }
        guard let start = jsonString.firstIndex(of: "["),
              let end = jsonString.lastIndex(of: "]") else { return }
        let slice = String(jsonString[start...end])
        guard let data = slice.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([TaskJSON].self, from: data) else { return }
        focusTasks = parsed.map { FocusTask(title: $0.title, estimatedMinutes: $0.estimatedMinutes) }
        saveFocusTasks()
    }

    // MARK: - Focus Tasks

    func toggleFocusTask(_ task: FocusTask) {
        guard let idx = focusTasks.firstIndex(where: { $0.id == task.id }) else { return }
        focusTasks[idx].isCompleted.toggle()
        saveFocusTasks()
    }

    func deleteFocusTasks(at offsets: IndexSet) {
        focusTasks.remove(atOffsets: offsets)
        saveFocusTasks()
    }

    func addFocusTask(_ title: String, estimatedMinutes: Int? = nil) {
        focusTasks.append(FocusTask(title: title, estimatedMinutes: estimatedMinutes))
        saveFocusTasks()
    }

    func clearCompletedTasks() {
        focusTasks.removeAll { $0.isCompleted }
        saveFocusTasks()
    }

    // MARK: - Audio

    func startListening() { audioService.startListening() }
    func stopListening() { audioService.stopListening() }

    func sendTranscription() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcribedText = ""
        sendMessage(text, attachments: pendingAttachments)
    }

    func sendQuickCapture(_ text: String) {
        guard !text.isEmpty else { return }
        if activeConversation == nil { newConversation() }
        sendMessage("[Quick capture — organize into [Reminder]/[Task]/[Note] as appropriate]: \(text)")
    }

    // MARK: - Attachments

    func addAttachment(_ attachment: AttachmentItem) { pendingAttachments.append(attachment) }
    func removeAttachment(_ attachment: AttachmentItem) { pendingAttachments.removeAll { $0.id == attachment.id } }

    // MARK: - Private Helpers

    private var activeConvIdx: Int? {
        conversations.firstIndex(where: { $0.id == activeConversation?.id })
    }

    private func lastAssistantMsgIdx(in convIdx: Int) -> Int? {
        conversations[convIdx].messages.lastIndex(where: { $0.role == .assistant })
    }

    private func buildContextMessages() -> [Message] {
        guard let conversation = activeConversation else { return [] }
        let msgs = conversation.messages.filter { !$0.isStreaming }
        return Array(msgs.suffix(max(2, contextWindowSize)))
    }

    private func appendMessage(_ message: Message) {
        guard let idx = activeConvIdx else { return }
        conversations[idx].messages.append(message)
        conversations[idx].updatedAt = Date()

        if conversations[idx].messages.filter({ $0.role == .user }).count == 1,
           let firstUser = conversations[idx].messages.first(where: { $0.role == .user }) {
            let preview = String(firstUser.content.prefix(40))
            conversations[idx].title = preview.isEmpty ? "New Conversation" : preview
        }
        activeConversation = conversations[idx]
    }

    private func updateLastAssistantMessage(_ text: String) {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx) else { return }
        conversations[convIdx].messages[msgIdx].content = text
        conversations[convIdx].messages[msgIdx].isStreaming = false
        activeConversation = conversations[convIdx]
    }

    private func appendToLastAssistantMessage(_ chunk: String) {
        guard let convIdx = activeConvIdx,
              let msgIdx = lastAssistantMsgIdx(in: convIdx) else { return }
        conversations[convIdx].messages[msgIdx].content += chunk
        activeConversation = conversations[convIdx]
    }

    // MARK: - Persistence

    private func saveConversations() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: "conversations")
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: "conversations"),
              let loaded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = loaded
        activeConversation = conversations.first
    }

    private func saveFocusTasks() {
        guard let data = try? JSONEncoder().encode(focusTasks) else { return }
        UserDefaults.standard.set(data, forKey: "focusTasks")
    }

    private func loadFocusTasks() {
        guard let data = UserDefaults.standard.data(forKey: "focusTasks"),
              let loaded = try? JSONDecoder().decode([FocusTask].self, from: data) else { return }
        focusTasks = loaded
    }
}
