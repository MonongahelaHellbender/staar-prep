import Foundation
import UIKit

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct AttachmentItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: AttachmentType
    var data: Data?
    var localURL: URL?

    enum AttachmentType: String, Codable {
        case image
        case pdf
        case document
        case audio
    }

    init(id: UUID = UUID(), name: String, type: AttachmentType, data: Data? = nil, localURL: URL? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.data = data
        self.localURL = localURL
    }
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var attachments: [AttachmentItem]
    var isStreaming: Bool
    var agentActions: [AgentAction]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        attachments: [AttachmentItem] = [],
        isStreaming: Bool = false,
        agentActions: [AgentAction]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.isStreaming = isStreaming
        self.agentActions = agentActions
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Conversation") {
        self.id = id
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
