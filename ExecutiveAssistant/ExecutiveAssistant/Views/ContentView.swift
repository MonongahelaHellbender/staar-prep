import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home, conversation, history, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            ConversationView()
                .tabItem {
                    Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(Tab.conversation)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(.indigo)
        .overlay(alignment: .top) {
            if let error = store.errorMessage {
                ErrorBannerView(message: error) {
                    store.errorMessage = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: store.errorMessage)
            }
        }
    }
}

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .foregroundColor(.white)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.gradient)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
