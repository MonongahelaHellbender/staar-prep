import Foundation

// MARK: - JSONValue: decodes arbitrary JSON from Claude tool call inputs

indirect enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        if case .number(let n) = self { return n }
        if case .string(let s) = self { return Double(s) }
        return nil
    }

    var intValue: Int? { doubleValue.map(Int.init) }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }

    subscript(key: String) -> JSONValue? {
        if case .object(let d) = self { return d[key] }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Tool Use Block (decoded from Claude API response)

struct ToolUseBlock {
    let id: String
    let name: String
    let input: JSONValue

    func string(_ key: String) -> String? { input[key]?.stringValue }
    func int(_ key: String) -> Int? { input[key]?.intValue }
    func double(_ key: String) -> Double? { input[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { input[key]?.boolValue }
}

// MARK: - Tool Definition (sent to Claude API)

struct AgentToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: ToolSchema

    struct ToolSchema: Encodable {
        let type = "object"
        let properties: [String: PropertySchema]
        let required: [String]

        struct PropertySchema: Encodable {
            let type: String
            let description: String
            let enumValues: [String]?

            init(_ type: String, _ description: String, enum values: [String]? = nil) {
                self.type = type
                self.description = description
                self.enumValues = values
            }

            enum CodingKeys: String, CodingKey {
                case type, description
                case enumValues = "enum"
            }
        }
    }
}

// MARK: - All Available Tools

extension AgentToolDefinition {

    static let allTools: [AgentToolDefinition] = [
        makePhoneCall, sendTextMessage, composeEmail,
        createCalendarEvent, createReminder, searchContacts,
        openApp, webSearch, openMaps, setTimer, getCurrentDatetime, openURL
    ]

    static let makePhoneCall = AgentToolDefinition(
        name: "make_phone_call",
        description: "Initiate a phone call. iOS will show a confirmation prompt before dialing.",
        input_schema: .init(properties: [
            "phone_number": .init("string", "Phone number to call, e.g. '+15551234567'"),
            "contact_name": .init("string", "Display name of the person being called")
        ], required: ["phone_number"])
    )

    static let sendTextMessage = AgentToolDefinition(
        name: "send_text_message",
        description: "Open the Messages app with a pre-filled recipient and message body. The user must tap Send.",
        input_schema: .init(properties: [
            "phone_number": .init("string", "Recipient phone number"),
            "message": .init("string", "The message text to pre-fill"),
            "contact_name": .init("string", "Recipient display name")
        ], required: ["phone_number", "message"])
    )

    static let composeEmail = AgentToolDefinition(
        name: "compose_email",
        description: "Open the Mail app with a pre-filled email. The user must tap Send.",
        input_schema: .init(properties: [
            "to": .init("string", "Recipient email address"),
            "subject": .init("string", "Email subject line"),
            "body": .init("string", "Email body content"),
            "cc": .init("string", "CC email address (optional)")
        ], required: ["to", "subject", "body"])
    )

    static let createCalendarEvent = AgentToolDefinition(
        name: "create_calendar_event",
        description: "Create a new event in the user's default calendar using EventKit. Requires calendar permission.",
        input_schema: .init(properties: [
            "title": .init("string", "Event title"),
            "start_date": .init("string", "Start in ISO 8601 format, e.g. '2026-03-15T14:00:00'"),
            "end_date": .init("string", "End in ISO 8601 format. Defaults to 1 hour after start."),
            "location": .init("string", "Event location or address"),
            "notes": .init("string", "Additional notes"),
            "all_day": .init("boolean", "Set true for an all-day event")
        ], required: ["title", "start_date"])
    )

    static let createReminder = AgentToolDefinition(
        name: "create_reminder",
        description: "Create a reminder in the Reminders app using EventKit. Requires reminders permission.",
        input_schema: .init(properties: [
            "title": .init("string", "Reminder title"),
            "due_date": .init("string", "Due date in ISO 8601 format (optional)"),
            "notes": .init("string", "Additional notes"),
            "priority": .init("string", "Priority level", enum: ["none", "low", "medium", "high"])
        ], required: ["title"])
    )

    static let searchContacts = AgentToolDefinition(
        name: "search_contacts",
        description: "Search the user's Contacts for a person by name, returning phone numbers and emails.",
        input_schema: .init(properties: [
            "name": .init("string", "Contact name to search for")
        ], required: ["name"])
    )

    static let openApp = AgentToolDefinition(
        name: "open_app",
        description: "Open a native iPhone app. Supports: Settings, Maps, Calendar, Reminders, Messages, Mail, Safari, Camera, Photos, Music, Clock, Notes, FaceTime, App Store, Health, and more.",
        input_schema: .init(properties: [
            "app_name": .init("string", "App name, e.g. 'Settings', 'Maps', 'Music', 'Notes'")
        ], required: ["app_name"])
    )

    static let webSearch = AgentToolDefinition(
        name: "web_search",
        description: "Open a web search in Safari.",
        input_schema: .init(properties: [
            "query": .init("string", "The search query"),
            "engine": .init("string", "Search engine", enum: ["google", "duckduckgo", "bing"])
        ], required: ["query"])
    )

    static let openMaps = AgentToolDefinition(
        name: "open_maps",
        description: "Open Apple Maps to search for a place or get directions.",
        input_schema: .init(properties: [
            "query": .init("string", "Place name, address, or search query"),
            "action": .init("string", "Action to perform", enum: ["search", "navigate"])
        ], required: ["query"])
    )

    static let setTimer = AgentToolDefinition(
        name: "set_timer",
        description: "Open the Clock app to set a countdown timer.",
        input_schema: .init(properties: [
            "duration_minutes": .init("number", "Timer duration in minutes"),
            "label": .init("string", "Optional label for the timer")
        ], required: ["duration_minutes"])
    )

    static let getCurrentDatetime = AgentToolDefinition(
        name: "get_current_datetime",
        description: "Get the current date, time, day of week, and timezone. Use before scheduling anything.",
        input_schema: .init(properties: [:], required: [])
    )

    static let openURL = AgentToolDefinition(
        name: "open_url",
        description: "Open a specific URL in Safari or the appropriate app.",
        input_schema: .init(properties: [
            "url": .init("string", "The full URL to open, e.g. 'https://example.com'")
        ], required: ["url"])
    )
}

// MARK: - Tool Display Helpers

extension AgentToolDefinition {
    static func displayName(for toolName: String) -> String {
        switch toolName {
        case "make_phone_call": return "Making phone call"
        case "send_text_message": return "Composing text message"
        case "compose_email": return "Composing email"
        case "create_calendar_event": return "Creating calendar event"
        case "create_reminder": return "Creating reminder"
        case "search_contacts": return "Searching contacts"
        case "open_app": return "Opening app"
        case "web_search": return "Searching the web"
        case "open_maps": return "Opening Maps"
        case "set_timer": return "Setting timer"
        case "get_current_datetime": return "Getting current time"
        case "open_url": return "Opening URL"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func systemIcon(for toolName: String) -> String {
        switch toolName {
        case "make_phone_call": return "phone.fill"
        case "send_text_message": return "message.fill"
        case "compose_email": return "envelope.fill"
        case "create_calendar_event": return "calendar.badge.plus"
        case "create_reminder": return "bell.badge.fill"
        case "search_contacts": return "person.crop.circle.badge.magnifyingglass"
        case "open_app": return "iphone"
        case "web_search": return "magnifyingglass"
        case "open_maps": return "map.fill"
        case "set_timer": return "timer"
        case "get_current_datetime": return "clock.fill"
        case "open_url": return "safari.fill"
        default: return "bolt.fill"
        }
    }
}

// MARK: - Agent Progress Events

enum AgentProgressEvent {
    case toolStarted(toolName: String, summary: String)
    case toolCompleted(toolName: String, result: String, isError: Bool)
    case textChunk(String)
}

// MARK: - Agent Action (stored in Message for UI display)

struct AgentAction: Identifiable, Codable {
    var id: UUID = UUID()
    let toolName: String
    let inputSummary: String
    var status: ActionStatus
    var result: String?
    var isError: Bool

    enum ActionStatus: String, Codable {
        case executing, success, failed
    }
}
