import Foundation
import UIKit

class ClaudeService {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let modelID = "claude-opus-4-6"
    private let apiVersion = "2023-06-01"

    struct ClaudeRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [ClaudeMessage]
        let stream: Bool
    }

    struct ClaudeMessage: Encodable {
        let role: String
        let content: [ClaudeContent]
    }

    enum ClaudeContent: Encodable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        enum CodingKeys: String, CodingKey {
            case type, text, source
        }

        struct ImageSource: Encodable {
            let type: String = "base64"
            let media_type: String
            let data: String
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let mediaType, let base64Data):
                try container.encode("image", forKey: .type)
                let source = ImageSource(media_type: mediaType, data: base64Data)
                try container.encode(source, forKey: .source)
            }
        }
    }

    struct StreamEvent {
        let type: String
        let delta: String?
    }

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void,
        onStream: @escaping (String) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion(.failure(ServiceError.invalidURL))
            return
        }

        var claudeMessages: [ClaudeMessage] = []

        for message in messages {
            var contents: [ClaudeContent] = []

            // Add attachments (images) first
            for attachment in message.attachments {
                if attachment.type == .image, let data = attachment.data {
                    let base64 = data.base64EncodedString()
                    let mediaType = mediaTypeForAttachment(attachment)
                    contents.append(.image(mediaType: mediaType, base64Data: base64))
                } else if let data = attachment.data, let text = String(data: data, encoding: .utf8) {
                    contents.append(.text("[\(attachment.name)]:\n\(text)"))
                }
            }

            // Add text content
            if !message.content.isEmpty {
                contents.append(.text(message.content))
            }

            if !contents.isEmpty {
                claudeMessages.append(ClaudeMessage(role: message.role.rawValue, content: contents))
            }
        }

        guard !claudeMessages.isEmpty else {
            completion(.failure(ServiceError.emptyMessages))
            return
        }

        let request = ClaudeRequest(
            model: modelID,
            max_tokens: 4096,
            system: systemPrompt,
            messages: claudeMessages,
            stream: true
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(ServiceError.noData))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    completion(.failure(ServiceError.apiError(httpResponse.statusCode, errorBody)))
                } else {
                    completion(.failure(ServiceError.httpError(httpResponse.statusCode)))
                }
                return
            }

            // Parse streaming response
            var fullText = ""
            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []

            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if jsonString == "[DONE]" { continue }

                    if let jsonData = jsonString.data(using: .utf8),
                       let event = try? JSONDecoder().decode(StreamChunk.self, from: jsonData) {
                        if let delta = event.delta?.text, !delta.isEmpty {
                            fullText += delta
                            onStream(delta)
                        }
                    }
                }
            }

            completion(.success(fullText))
        }

        task.resume()
    }

    private func mediaTypeForAttachment(_ attachment: AttachmentItem) -> String {
        let name = attachment.name.lowercased()
        if name.hasSuffix(".png") { return "image/png" }
        if name.hasSuffix(".gif") { return "image/gif" }
        if name.hasSuffix(".webp") { return "image/webp" }
        return "image/jpeg"
    }

    struct StreamChunk: Decodable {
        let type: String?
        let delta: DeltaContent?

        struct DeltaContent: Decodable {
            let type: String?
            let text: String?
        }
    }

    enum ServiceError: LocalizedError {
        case invalidURL
        case emptyMessages
        case noData
        case httpError(Int)
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .emptyMessages: return "No messages to send"
            case .noData: return "No response data received"
            case .httpError(let code): return "HTTP error \(code)"
            case .apiError(let code, let body): return "API error \(code): \(body)"
            }
        }
    }
}
