import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ConversationView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var inputText: String = ""
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingAttachmentMenu = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages
                if let conversation = store.activeConversation, !conversation.messages.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(conversation.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                                if store.isProcessing {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onChange(of: conversation.messages.count) { _ in
                            withAnimation {
                                proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: store.isProcessing) { processing in
                            if processing {
                                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                            }
                        }
                    }
                } else {
                    EmptyConversationView()
                }

                Divider()

                // Transcription preview
                if store.isListening && !store.transcribedText.isEmpty {
                    TranscriptionPreview()
                }

                // Pending attachments
                if !store.pendingAttachments.isEmpty {
                    AttachmentPreviewStrip()
                }

                // Input Area
                InputArea(
                    inputText: $inputText,
                    isInputFocused: _isInputFocused,
                    showingAttachmentMenu: $showingAttachmentMenu,
                    showingPhotoPicker: $showingPhotoPicker,
                    showingFilePicker: $showingFilePicker
                )
            }
            .navigationTitle(store.activeConversation?.title ?? "Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.newConversation()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Agent mode toggle
                        Button {
                            store.agentModeEnabled.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption.bold())
                                Text("Agent")
                                    .font(.caption.bold())
                            }
                            .foregroundColor(store.agentModeEnabled ? .white : .indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(store.agentModeEnabled ? Color.indigo : Color.indigo.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        ListeningButton()
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotos) { items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let name = "photo_\(Date().timeIntervalSince1970).jpg"
                        let attachment = FileService.processImageData(data, fileName: name)
                        await MainActor.run { store.addAttachment(attachment) }
                    }
                }
                await MainActor.run { selectedPhotos = [] }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .text, .plainText, .image, .jpeg, .png, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        let attachment = FileService.processFileData(data, fileName: url.lastPathComponent, contentType: nil)
                        store.addAttachment(attachment)
                    }
                }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @EnvironmentObject var store: ConversationStore
    let message: Message
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: store.agentModeEnabled ? "bolt.fill" : "sparkles")
                    .font(.caption)
                    .foregroundColor(.indigo)
                    .frame(width: 28, height: 28)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Attachments
                if !message.attachments.isEmpty {
                    AttachmentPreviewInMessage(attachments: message.attachments)
                }

                // Agent action cards
                if let actions = message.agentActions, !actions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(actions) { action in
                            AgentActionCard(action: action)
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                }

                // Text bubble
                if !message.content.isEmpty || message.isStreaming {
                    VStack(alignment: .leading, spacing: 4) {
                        if !message.content.isEmpty {
                            Text(message.content)
                                .font(.body)
                                .foregroundColor(isUser ? .white : .primary)
                        }
                        if message.isStreaming && message.content.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Circle().fill(Color.secondary).frame(width: 5, height: 5).opacity(0.5)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.indigo : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // "Save as Focus Tasks" button for numbered-list responses
                if !isUser && !message.isStreaming && hasNumberedList(message.content) {
                    Button {
                        store.extractTasksFromLastResponse()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption)
                            Text("Save as Focus Tasks")
                                .font(.caption.bold())
                        }
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func hasNumberedList(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        let numbered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.first?.isNumber == true && (trimmed.hasPrefix("1.") || trimmed.hasPrefix("1)") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("2)"))
        }
        return numbered.count >= 2
    }
}

// MARK: - Agent Action Card

struct AgentActionCard: View {
    let action: AgentAction

    var body: some View {
        HStack(spacing: 10) {
            // Tool icon
            Image(systemName: AgentToolDefinition.systemIcon(for: action.toolName))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(AgentToolDefinition.displayName(for: action.toolName))
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(action.inputSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let result = action.result {
                    Text(result)
                        .font(.caption2)
                        .foregroundColor(action.isError ? .red : .green)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Status indicator
            Group {
                switch action.status {
                case .executing:
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.indigo)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(iconColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        switch action.status {
        case .executing: return .indigo
        case .success: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Attachment Preview In Message

struct AttachmentPreviewInMessage: View {
    let attachments: [AttachmentItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    if attachment.type == .image, let data = attachment.data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: attachment.type == .pdf ? "doc.fill" : "doc.text.fill")
                                .font(.title2)
                                .foregroundColor(.indigo)
                            Text(attachment.name)
                                .font(.caption2)
                                .lineLimit(2)
                        }
                        .frame(width: 80, height: 80)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .frame(maxWidth: 260)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @EnvironmentObject var store: ConversationStore
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: store.agentModeEnabled ? "bolt.fill" : "sparkles")
                .font(.caption)
                .foregroundColor(.indigo)
                .frame(width: 28, height: 28)
                .background(Color.indigo.opacity(0.1))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.3 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .onAppear { animating = true }
    }
}

// MARK: - Input Area

struct InputArea: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    @Binding var showingAttachmentMenu: Bool
    @Binding var showingPhotoPicker: Bool
    @Binding var showingFilePicker: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                showingAttachmentMenu = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundColor(.indigo)
                    .frame(width: 36, height: 36)
            }
            .confirmationDialog("Add Attachment", isPresented: $showingAttachmentMenu) {
                Button("Photo Library") { showingPhotoPicker = true }
                Button("Browse Files") { showingFilePicker = true }
                Button("Cancel", role: .cancel) {}
            }

            ZStack(alignment: .leading) {
                if inputText.isEmpty && !store.isListening {
                    Text(store.agentModeEnabled ? "Command or ask anything..." : "Message or ask anything...")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: store.isListening ? $store.transcribedText : $inputText)
                    .focused($isInputFocused)
                    .frame(minHeight: 40, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            if store.isListening || !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.transcribedText.isEmpty {
                Button {
                    if store.isListening {
                        store.stopListening()
                        if !store.transcribedText.isEmpty { store.sendTranscription() }
                    } else {
                        let text = inputText
                        inputText = ""
                        store.sendMessage(text, attachments: store.pendingAttachments)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.indigo)
                }
                .disabled(store.isProcessing)
            } else {
                MicButton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

struct MicButton: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        Button {
            if store.isListening { store.stopListening() }
            else { store.startListening() }
        } label: {
            ZStack {
                Circle()
                    .fill(store.isListening ? Color.red : Color.indigo)
                    .frame(width: 36, height: 36)

                if store.isListening {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 6)
                        .frame(width: 36, height: 36)
                        .scaleEffect(1.6)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: store.isListening)
                }

                Image(systemName: store.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

struct ListeningButton: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        Button {
            if store.isListening { store.stopListening() }
            else { store.startListening() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.isListening ? "waveform" : "mic")
                    .symbolEffect(.variableColor, isActive: store.isListening)
                if store.isListening { Text("Listening").font(.caption.bold()) }
            }
            .foregroundColor(store.isListening ? .red : .indigo)
        }
    }
}

// MARK: - Transcription Preview

struct TranscriptionPreview: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        HStack(spacing: 12) {
            AudioWaveformView(level: 0.5)
                .frame(width: 30, height: 20)

            Text(store.transcribedText.isEmpty ? "Listening..." : store.transcribedText)
                .font(.subheadline)
                .foregroundColor(store.transcribedText.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.transcribedText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.indigo.opacity(0.06))
    }
}

struct AudioWaveformView: View {
    let level: Float
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.indigo)
                    .frame(width: 3)
                    .frame(height: CGFloat.random(in: 8...20))
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.08),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Attachment Preview Strip

struct AttachmentPreviewStrip: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.pendingAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        store.removeAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }
}

struct AttachmentChip: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.type == .image, let data = attachment.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: attachment.type == .pdf ? "doc.fill" : "doc.text.fill")
                    .font(.caption)
                    .foregroundColor(.indigo)
            }

            Text(attachment.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 100)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Empty State

struct EmptyConversationView: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: store.agentModeEnabled ? "bolt.fill" : "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text(store.agentModeEnabled ? "Agent Mode Active" : "Executive Assistant")
                    .font(.title2.bold())

                Text(store.agentModeEnabled
                     ? "I can take actions on your phone.\nTell me what to do."
                     : "Tap the microphone to start listening,\nor type a message below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(store.agentModeEnabled ? agentPrompts : standardPrompts, id: \.self) { prompt in
                    Button {
                        store.sendMessage(prompt)
                    } label: {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.indigo.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private let standardPrompts = [
        "What should I focus on today?",
        "Help me draft a professional email",
        "Summarize my recent conversations",
        "Break this task down into steps"
    ]

    private let agentPrompts = [
        "Call [contact name]",
        "Remind me to review budget at 3pm",
        "Navigate to the nearest coffee shop",
        "Open Settings"
    ]
}
