import Foundation
import UIKit
import EventKit
import Contacts

/// Executes iOS phone actions in response to Claude tool calls.
@MainActor
class PhoneActionsService {

    static let shared = PhoneActionsService()
    private let eventStore = EKEventStore()

    // MARK: - Tool Dispatch

    func execute(_ tool: ToolUseBlock) async -> ToolResult {
        switch tool.name {
        case "make_phone_call":       return await makePhoneCall(tool)
        case "send_text_message":     return await sendTextMessage(tool)
        case "compose_email":         return await composeEmail(tool)
        case "create_calendar_event": return await createCalendarEvent(tool)
        case "create_reminder":       return await createReminder(tool)
        case "search_contacts":       return await searchContacts(tool)
        case "open_app":              return await openApp(tool)
        case "web_search":            return await webSearch(tool)
        case "open_maps":             return await openMaps(tool)
        case "set_timer":             return await setTimer(tool)
        case "get_current_datetime":  return getCurrentDatetime()
        case "open_url":              return await openURL(tool)
        default:                      return .failure("Unknown tool: \(tool.name)")
        }
    }

    // MARK: - Phone Call

    private func makePhoneCall(_ tool: ToolUseBlock) async -> ToolResult {
        guard let number = tool.string("phone_number") else {
            return .failure("Missing phone_number parameter")
        }
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let url = URL(string: "tel://\(cleaned)") else {
            return .failure("Invalid phone number format")
        }
        let opened = await UIApplication.shared.open(url)
        let name = tool.string("contact_name").map { " to \($0)" } ?? ""
        return opened
            ? .success("Phone call initiated\(name) at \(number)")
            : .failure("Could not initiate call — device may not support phone calls")
    }

    // MARK: - Text Message

    private func sendTextMessage(_ tool: ToolUseBlock) async -> ToolResult {
        guard let number = tool.string("phone_number"),
              let message = tool.string("message") else {
            return .failure("Missing required parameters: phone_number, message")
        }
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "sms:\(number)&body=\(encoded)") else {
            return .failure("Could not construct SMS URL")
        }
        let opened = await UIApplication.shared.open(url)
        let name = tool.string("contact_name") ?? number
        return opened
            ? .success("Messages app opened with draft to \(name). Tap Send to deliver.")
            : .failure("Could not open Messages app")
    }

    // MARK: - Email

    private func composeEmail(_ tool: ToolUseBlock) async -> ToolResult {
        guard let to = tool.string("to"),
              let subject = tool.string("subject"),
              let body = tool.string("body") else {
            return .failure("Missing required parameters: to, subject, body")
        }
        var components = URLComponents(string: "mailto:\(to)")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let cc = tool.string("cc") {
            items.append(URLQueryItem(name: "cc", value: cc))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            return .failure("Could not construct mailto URL")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? .success("Mail app opened with draft to \(to). Tap Send to deliver.")
            : .failure("Could not open Mail app")
    }

    // MARK: - Calendar Event

    private func createCalendarEvent(_ tool: ToolUseBlock) async -> ToolResult {
        guard let title = tool.string("title"),
              let startStr = tool.string("start_date") else {
            return .failure("Missing required parameters: title, start_date")
        }

        guard let startDate = parseDate(startStr) else {
            return .failure("Could not parse start_date: '\(startStr)'. Use ISO 8601 format like '2026-03-15T14:00:00'")
        }

        // Request calendar access
        do {
            if #available(iOS 17.0, *) {
                try await eventStore.requestFullAccessToEvents()
            } else {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error { cont.resume(throwing: error) }
                        else if !granted { cont.resume(throwing: PermissionError.denied("Calendar")) }
                        else { cont.resume() }
                    }
                }
            }
        } catch {
            return .failure("Calendar access denied. Please grant permission in Settings → Privacy → Calendars.")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate

        if let endStr = tool.string("end_date"), let endDate = parseDate(endStr) {
            event.endDate = endDate
        } else {
            event.endDate = startDate.addingTimeInterval(3600)
        }

        if let location = tool.string("location") {
            event.location = location
        }
        if let notes = tool.string("notes") {
            event.notes = notes
        }
        if tool.bool("all_day") == true {
            event.isAllDay = true
        }

        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return .success("Calendar event '\(title)' created for \(formatter.string(from: startDate))")
        } catch {
            return .failure("Failed to save event: \(error.localizedDescription)")
        }
    }

    // MARK: - Reminder

    private func createReminder(_ tool: ToolUseBlock) async -> ToolResult {
        guard let title = tool.string("title") else {
            return .failure("Missing required parameter: title")
        }

        do {
            if #available(iOS 17.0, *) {
                try await eventStore.requestFullAccessToReminders()
            } else {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    eventStore.requestAccess(to: .reminder) { granted, error in
                        if let error = error { cont.resume(throwing: error) }
                        else if !granted { cont.resume(throwing: PermissionError.denied("Reminders")) }
                        else { cont.resume() }
                    }
                }
            }
        } catch {
            return .failure("Reminders access denied. Please grant permission in Settings → Privacy → Reminders.")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let notes = tool.string("notes") {
            reminder.notes = notes
        }

        if let dueDateStr = tool.string("due_date"), let dueDate = parseDate(dueDateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }

        let priorityStr = tool.string("priority") ?? "none"
        switch priorityStr {
        case "low": reminder.priority = Int(EKReminderPriority.low.rawValue)
        case "medium": reminder.priority = Int(EKReminderPriority.medium.rawValue)
        case "high": reminder.priority = Int(EKReminderPriority.high.rawValue)
        default: reminder.priority = Int(EKReminderPriority.none.rawValue)
        }

        do {
            try eventStore.save(reminder, commit: true)
            return .success("Reminder '\(title)' created successfully")
        } catch {
            return .failure("Failed to save reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Contact Search

    private func searchContacts(_ tool: ToolUseBlock) async -> ToolResult {
        guard let name = tool.string("name") else {
            return .failure("Missing required parameter: name")
        }

        let store = CNContactStore()

        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            return .failure("Contacts access denied. Please grant permission in Settings → Privacy → Contacts.")
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        do {
            let predicate = CNContact.predicateForContacts(matchingName: name)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if contacts.isEmpty {
                return .success("No contacts found matching '\(name)'")
            }

            var results: [String] = []
            for contact in contacts.prefix(5) {
                var parts: [String] = []
                let fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                parts.append(fullName.isEmpty ? "(no name)" : fullName)

                if !contact.organizationName.isEmpty {
                    parts.append("(\(contact.organizationName))")
                }

                for phone in contact.phoneNumbers {
                    parts.append("📞 \(phone.value.stringValue)")
                }
                for email in contact.emailAddresses {
                    parts.append("✉️ \(email.value)")
                }

                results.append(parts.joined(separator: " | "))
            }

            return .success("Found \(contacts.count) contact(s):\n" + results.joined(separator: "\n"))
        } catch {
            return .failure("Contact search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Open App

    private func openApp(_ tool: ToolUseBlock) async -> ToolResult {
        guard let appName = tool.string("app_name") else {
            return .failure("Missing required parameter: app_name")
        }

        let urlScheme = appURLScheme(for: appName)
        guard let url = URL(string: urlScheme) else {
            return .failure("No URL scheme for '\(appName)'")
        }

        let opened = await UIApplication.shared.open(url)
        return opened
            ? .success("Opened \(appName)")
            : .failure("Could not open \(appName). The app may not be installed.")
    }

    private func appURLScheme(for appName: String) -> String {
        switch appName.lowercased().trimmingCharacters(in: .whitespaces) {
        case "settings": return "app-settings:"
        case "maps": return "maps://"
        case "calendar": return "calshow://"
        case "reminders": return "x-apple-reminderkit://"
        case "messages", "sms": return "sms://"
        case "mail": return "mailto:"
        case "safari": return "https://www.apple.com"
        case "camera": return "camera://"
        case "photos": return "photos-redirect://"
        case "music": return "music://"
        case "clock": return "clock-sleep-alarm://"
        case "notes": return "mobilenotes://"
        case "facetime": return "facetime://"
        case "phone": return "tel://"
        case "app store", "appstore": return "itms-apps://itunes.apple.com"
        case "health": return "x-apple-health://"
        case "wallet": return "shoebox://"
        case "weather": return "weather://"
        case "stocks": return "stocks://"
        case "news": return "applenews://"
        case "podcasts": return "pcast://"
        case "books": return "ibooks://"
        case "files": return "shareddocuments://"
        case "contacts": return "contacts://"
        default: return "https://apps.apple.com/search?term=\(appName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appName)"
        }
    }

    // MARK: - Web Search

    private func webSearch(_ tool: ToolUseBlock) async -> ToolResult {
        guard let query = tool.string("query") else {
            return .failure("Missing required parameter: query")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let engine = tool.string("engine") ?? "google"
        let urlString: String
        switch engine {
        case "duckduckgo": urlString = "https://duckduckgo.com/?q=\(encoded)"
        case "bing":       urlString = "https://www.bing.com/search?q=\(encoded)"
        default:           urlString = "https://www.google.com/search?q=\(encoded)"
        }
        guard let url = URL(string: urlString) else {
            return .failure("Could not construct search URL")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? .success("Opened \(engine.capitalized) search for '\(query)'")
            : .failure("Could not open browser")
    }

    // MARK: - Maps

    private func openMaps(_ tool: ToolUseBlock) async -> ToolResult {
        guard let query = tool.string("query") else {
            return .failure("Missing required parameter: query")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let action = tool.string("action") ?? "search"
        let urlString = action == "navigate"
            ? "maps://?daddr=\(encoded)"
            : "maps://?q=\(encoded)"
        guard let url = URL(string: urlString) else {
            return .failure("Could not construct Maps URL")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? .success(action == "navigate" ? "Navigation started to '\(query)'" : "Searching Maps for '\(query)'")
            : .failure("Could not open Maps")
    }

    // MARK: - Timer

    private func setTimer(_ tool: ToolUseBlock) async -> ToolResult {
        guard let minutes = tool.double("duration_minutes") else {
            return .failure("Missing required parameter: duration_minutes")
        }
        let totalSeconds = Int(minutes * 60)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        var urlString = "clock-timer://\(hours)/\(mins)/\(secs)"
        if let label = tool.string("label") {
            let encoded = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? label
            urlString += "?name=\(encoded)"
        }

        // Fallback to clock app if timer URL doesn't work
        if let url = URL(string: urlString), await UIApplication.shared.open(url) {
            return .success("Timer set for \(Int(minutes)) minute\(minutes == 1 ? "" : "s")")
        }

        if let clockURL = URL(string: "clock-sleep-alarm://"), await UIApplication.shared.open(clockURL) {
            return .success("Opened Clock app — please set your timer for \(Int(minutes)) minute\(minutes == 1 ? "" : "s") manually")
        }

        return .failure("Could not open Clock app")
    }

    // MARK: - Current Datetime

    private func getCurrentDatetime() -> ToolResult {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a z"
        let timeZone = TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        return .success("""
        Current date/time: \(formatter.string(from: now))
        ISO 8601: \(isoFormatter.string(from: now))
        Timezone: \(timeZone) (\(TimeZone.current.identifier))
        Day of week: \(Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: now) - 1])
        """)
    }

    // MARK: - Open URL

    private func openURL(_ tool: ToolUseBlock) async -> ToolResult {
        guard var urlString = tool.string("url") else {
            return .failure("Missing required parameter: url")
        }
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString) else {
            return .failure("Invalid URL: \(urlString)")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? .success("Opened \(urlString)")
            : .failure("Could not open URL: \(urlString)")
    }

    // MARK: - Date Parsing

    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }(),
            { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
        ]

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }

        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    // MARK: - Errors

    enum PermissionError: LocalizedError {
        case denied(String)
        var errorDescription: String? {
            if case .denied(let name) = self { return "\(name) permission denied" }
            return nil
        }
    }
}
