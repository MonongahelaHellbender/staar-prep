import SwiftUI

@main
struct ExecutiveAssistantApp: App {
    @StateObject private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
