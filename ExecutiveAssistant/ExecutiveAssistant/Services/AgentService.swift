import Foundation

/// Runs the Claude tool-use agent loop: send → receive → execute tools → repeat until end_turn.
class AgentService {

    static let shared = AgentService()
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let model = "claude-opus-4-6"
    private let maxIterations = 10

    static let agentSystemPromptAddition = """

    \n\n---\nYou are operating in AGENT MODE. You have access to tools that can control this iPhone directly. \
    When the user asks you to take an action (call someone, send a message, set a reminder, navigate somewhere, \
    open an app, search the web, etc.), use the appropriate tool immediately without asking for confirmation — \
    just do it and report back. For phone calls and messages, iOS will show its own confirmation dialog. \
    Always use get_current_datetime before scheduling events or reminders. Chain multiple tools as needed \
    to complete complex tasks. After executing actions, give a brief confirmation of what was done.
    """

    // MARK: - Public API

    func runAgent(
        messages: [Message],
        systemPrompt: String,
        apiKey: String,
        onProgress: @escaping (AgentProgressEvent) -> Void
    ) async -> String {
        var apiMessages = buildInitialAPIMessages(from: messages)
        var fullResponse = ""
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1

            let result: AgentAPIResponse
            do {
                result = try await callClaude(messages: apiMessages, systemPrompt: systemPrompt, apiKey: apiKey)
            } catch {
                return "I encountered an error: \(error.localizedDescription)"
            }

            // Collect any text content from this turn
            let textContent = result.textContent
            if !textContent.isEmpty {
                onProgress(.textChunk(textContent))
                if result.stopReason == "end_turn" {
                    fullResponse = textContent
                }
            }

            if result.stopReason == "end_turn" || result.toolUseCalls.isEmpty {
                if fullResponse.isEmpty { fullResponse = textContent }
                break
            }

            // Build assistant message with all content blocks (text + tool_use)
            var assistantContent: [AgentAPIContent] = []
            if !textContent.isEmpty {
                assistantContent.append(.text(textContent))
            }
            for toolCall in result.toolUseCalls {
                assistantContent.append(.toolUse(id: toolCall.id, name: toolCall.name, input: toolCall.input))
            }
            apiMessages.append(AgentAPIMessage(role: "assistant", content: assistantContent))

            // Execute each tool and collect results
            var toolResultContent: [AgentAPIContent] = []
            for toolCall in result.toolUseCalls {
                let displayName = AgentToolDefinition.displayName(for: toolCall.name)
                let summary = buildInputSummary(toolCall)
                onProgress(.toolStarted(toolName: toolCall.name, summary: summary))

                let toolResult = await PhoneActionsService.shared.execute(toolCall)

                onProgress(.toolCompleted(
                    toolName: toolCall.name,
                    result: toolResult.content,
                    isError: toolResult.isError
                ))

                toolResultContent.append(.toolResult(
                    toolUseId: toolCall.id,
                    content: toolResult.content,
                    isError: toolResult.isError
                ))
            }

            apiMessages.append(AgentAPIMessage(role: "user", content: toolResultContent))
        }

        return fullResponse
    }

    // MARK: - API Call

    private func callClaude(
        messages: [AgentAPIMessage],
        systemPrompt: String,
        apiKey: String
    ) async throws -> AgentAPIResponse {
        guard let url = URL(string: baseURL) else { throw AgentError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body = AgentRequest(
            model: model,
            max_tokens: 4096,
            system: systemPrompt,
            tools: AgentToolDefinition.allTools,
            messages: messages
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw AgentError.apiError(http.statusCode, errorBody)
        }

        return try JSONDecoder().decode(AgentAPIResponse.self, from: data)
    }

    // MARK: - Message Building

    private func buildInitialAPIMessages(from messages: [Message]) -> [AgentAPIMessage] {
        messages.compactMap { msg -> AgentAPIMessage? in
            var content: [AgentAPIContent] = []

            for attachment in msg.attachments {
                if attachment.type == .image, let data = attachment.data {
                    let mediaType = mediaType(for: attachment.name)
                    content.append(.image(mediaType: mediaType, base64: data.base64EncodedString()))
                } else if let data = attachment.data, let text = String(data: data, encoding: .utf8) {
                    content.append(.text("[\(attachment.name)]:\n\(text)"))
                }
            }

            if !msg.content.isEmpty {
                content.append(.text(msg.content))
            }

            guard !content.isEmpty else { return nil }
            return AgentAPIMessage(role: msg.role.rawValue, content: content)
        }
    }

    private func mediaType(for fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        return "image/jpeg"
    }

    private func buildInputSummary(_ tool: ToolUseBlock) -> String {
        switch tool.name {
        case "make_phone_call":
            let name = tool.string("contact_name") ?? tool.string("phone_number") ?? ""
            return "Calling \(name)"
        case "send_text_message":
            let name = tool.string("contact_name") ?? tool.string("phone_number") ?? ""
            return "Texting \(name)"
        case "compose_email":
            let to = tool.string("to") ?? ""
            let subject = tool.string("subject") ?? ""
            return "Email to \(to): \(subject)"
        case "create_calendar_event":
            return tool.string("title") ?? "New event"
        case "create_reminder":
            return tool.string("title") ?? "New reminder"
        case "search_contacts":
            return "Looking up \(tool.string("name") ?? "contact")"
        case "open_app":
            return "Opening \(tool.string("app_name") ?? "app")"
        case "web_search":
            return tool.string("query") ?? "Search query"
        case "open_maps":
            return tool.string("query") ?? "Location"
        case "set_timer":
            let mins = tool.double("duration_minutes").map { "\(Int($0)) min" } ?? ""
            return "Timer: \(mins)"
        case "get_current_datetime":
            return "Checking current time"
        case "open_url":
            return tool.string("url") ?? "URL"
        default:
            return tool.name
        }
    }

    // MARK: - Errors

    enum AgentError: LocalizedError {
        case invalidURL
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .apiError(let code, let body):
                if let data = body.data(using: .utf8),
                   let json = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                   let error = json["error"],
                   case .object(let errObj) = error,
                   let msg = errObj["message"]?.stringValue {
                    return "API \(code): \(msg)"
                }
                return "API error \(code)"
            }
        }
    }
}

// MARK: - API Request/Response Models

struct AgentRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let tools: [AgentToolDefinition]
    let messages: [AgentAPIMessage]
}

struct AgentAPIMessage: Encodable {
    let role: String
    let content: [AgentAPIContent]
}

enum AgentAPIContent: Encodable {
    case text(String)
    case image(mediaType: String, base64: String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let mediaType, let base64):
            try c.encode("image", forKey: .type)
            var src = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try src.encode("base64", forKey: .type)
            try src.encode(mediaType, forKey: .mediaType)
            try src.encode(base64, forKey: .data)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .toolUseId)
            try c.encode(content, forKey: .content)
            if isError { try c.encode(true, forKey: .isError) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input, content
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }
    enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

// MARK: - API Response

struct AgentAPIResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let stop_reason: String

    var stopReason: String { stop_reason }

    var textContent: String {
        content.compactMap { block -> String? in
            if case .text(let t) = block { return t }
            return nil
        }.joined()
    }

    var toolUseCalls: [ToolUseBlock] {
        content.compactMap { block -> ToolUseBlock? in
            if case .toolUse(let b) = block { return b }
            return nil
        }
    }

    enum ContentBlock: Decodable {
        case text(String)
        case toolUse(ToolUseBlock)

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                let id = try c.decode(String.self, forKey: .id)
                let name = try c.decode(String.self, forKey: .name)
                let input = try c.decode(JSONValue.self, forKey: .input)
                self = .toolUse(ToolUseBlock(id: id, name: name, input: input))
            default:
                self = .text("")
            }
        }

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
        }
    }
}

// ToolResult returned by PhoneActionsService
struct ToolResult {
    let content: String
    let isError: Bool

    static func success(_ content: String) -> ToolResult { ToolResult(content: content, isError: false) }
    static func failure(_ content: String) -> ToolResult { ToolResult(content: content, isError: true) }
}
