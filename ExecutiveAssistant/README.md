# Executive Assistant — iOS App

An intelligent iPhone executive assistant powered by Claude claude-opus-4-6. The app listens to your daily life through the microphone, transcribes speech in real-time, and allows you to upload files and photos for context-aware AI assistance.

## Features

### Voice Listening
- **Continuous microphone listening** using AVAudioEngine + Apple's SFSpeechRecognizer
- Real-time speech-to-text transcription displayed as you speak
- Automatic silence detection (3-second pause triggers send)
- Audio level visualization waveform
- Background audio mode enabled

### AI Assistant (Claude claude-opus-4-6)
- Powered by Anthropic's Claude claude-opus-4-6 model via the Messages API
- Streaming responses for real-time output
- Configurable **personality modes**: Executive, Concise, Detailed, Friendly
- Configurable **context window** (4–50 messages)
- System prompt tailored for executive assistance

### File & Photo Upload
- **Photo Library** picker (up to 5 images at once) via PhotosUI
- **Document picker** supporting PDF, text, and image files
- Images sent as base64-encoded vision content to Claude
- PDF text extraction via PDFKit
- Large image auto-compression

### Conversation Management
- Persistent conversation history (stored in UserDefaults)
- Auto-titling from first user message
- Full-text search across conversations
- Swipe-to-delete with confirmation
- Grouped by date (Today, Yesterday, etc.)

### User Interface
- Tab-based navigation: Home · Assistant · History · Settings
- **Home dashboard** with quick actions, status card, recent conversations
- **Conversation view** with iMessage-style chat bubbles, typing indicator
- **History view** with search and grouped dates
- **Settings** with API key management, connection test, personality/context config
- Error banner overlay for API failures
- Dark mode compatible

## Project Structure

```
ExecutiveAssistant/
├── ExecutiveAssistant.xcodeproj/
│   └── project.pbxproj
└── ExecutiveAssistant/
    ├── App/
    │   ├── ExecutiveAssistantApp.swift   # @main entry point
    │   └── Info.plist                    # Permissions + config
    ├── Views/
    │   ├── ContentView.swift             # Tab container + error banner
    │   ├── HomeView.swift                # Dashboard
    │   ├── ConversationView.swift        # Chat UI + input area
    │   ├── HistoryView.swift             # Conversation list
    │   └── SettingsView.swift            # API key + preferences
    ├── Models/
    │   ├── Message.swift                 # Message, Conversation, AttachmentItem
    │   └── ConversationStore.swift       # ObservableObject state + logic
    ├── Services/
    │   ├── ClaudeService.swift           # Anthropic API + streaming
    │   ├── AudioService.swift            # AVAudioEngine + SFSpeechRecognizer
    │   └── FileService.swift             # Image/PDF processing
    ├── Assets.xcassets/                  # App icon + accent color
    └── LaunchScreen.storyboard
```

## Setup Instructions

### Requirements
- Xcode 15+
- iOS 17.0+ deployment target
- iPhone or Simulator with microphone support
- Anthropic API key (get one at https://console.anthropic.com)

### Steps
1. Open `ExecutiveAssistant.xcodeproj` in Xcode
2. Set your development team in **Signing & Capabilities**
3. Build and run on device or simulator
4. On first launch, go to **Settings → API Key → Add**
5. Enter your `sk-ant-...` API key and tap Save
6. Return to Home and tap **Start Listening** or go to **Assistant**

### Permissions Requested
| Permission | Reason |
|---|---|
| Microphone | Continuous voice capture for real-time transcription |
| Speech Recognition | Convert speech audio to text via Apple's on-device + server models |
| Photo Library | Select photos/documents to share with the assistant |
| Camera | Capture documents/whiteboards for analysis |

## Architecture

- **SwiftUI** throughout for declarative UI
- **Combine** for reactive data flow between AudioService → ConversationStore → Views
- **@EnvironmentObject** (`ConversationStore`) shared across all views
- **@AppStorage** for persistent user settings
- **URLSession** for direct Anthropic API calls with SSE streaming
- **AVAudioEngine** tap for raw audio buffers → speech recognition
- **PhotosUI** `PhotosPicker` for modern photo selection API

## API Integration

The app uses the Anthropic Messages API with SSE streaming:

```
POST https://api.anthropic.com/v1/messages
Headers:
  x-api-key: <your-key>
  anthropic-version: 2023-06-01
  Content-Type: application/json

Body:
  model: claude-opus-4-6
  max_tokens: 4096
  stream: true
  system: <personality prompt>
  messages: [{ role, content: [text/image blocks] }]
```

Images are sent as base64-encoded `image` content blocks. PDFs are extracted to text and sent as text blocks.
