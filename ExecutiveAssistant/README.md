# Executive Assistant — iPhone App

An intelligent iPhone executive assistant powered by **Claude claude-opus-4-6**. The app listens to your daily life through the microphone, lets you upload files and photos, and — in Agent Mode — takes direct actions on your phone through voice or text commands. Includes dedicated **ADD/ADHD support features** to help manage executive dysfunction.

---

## Features

### Voice & Conversation
- **Continuous microphone listening** via AVAudioEngine + SFSpeechRecognizer
- Real-time speech-to-text transcription shown as you speak
- 3-second silence detection auto-triggers send
- Upload photos (up to 5) and files (PDF, text, images)

### AI Assistant (Claude claude-opus-4-6)
- Powered by Anthropic's Claude claude-opus-4-6 via Messages API
- **Streaming responses** for real-time output (non-agent mode)
- **5 personality modes**: Executive, ADHD Coach, Concise, Detailed, Friendly
- Configurable context window (4–50 messages)
- Vision support — images sent as base64 content blocks

### Agent Mode — Take Actions on Your Phone
When enabled, Claude autonomously executes chains of actions to complete requests:

| Tool | What it Does |
|---|---|
| `make_phone_call` | Opens the iOS dialer — iOS confirms before dialing |
| `send_text_message` | Opens Messages pre-filled — user taps Send |
| `compose_email` | Opens Mail pre-filled — user taps Send |
| `create_calendar_event` | Creates event in Calendar via EventKit |
| `create_reminder` | Creates reminder in Reminders via EventKit |
| `search_contacts` | Looks up phone/email from your Contacts |
| `open_app` | Opens any built-in app (Settings, Maps, Music, etc.) |
| `web_search` | Searches Google/DuckDuckGo/Bing in Safari |
| `open_maps` | Searches or navigates in Apple Maps |
| `set_timer` | Opens Clock app with timer pre-set |
| `get_current_datetime` | Returns date/time/timezone for scheduling |
| `open_url` | Opens any URL in Safari |

**Example:** *"Call Sarah and remind me to follow up tomorrow"*
→ search_contacts("Sarah") → make_phone_call("415-555-0192") → create_reminder("Follow up with Sarah", tomorrow 9am)

### ADD/ADHD Support
Designed specifically for executive dysfunction:

- **ADHD Coach personality** — short responses, one action at a time, time estimates, encouragement, Pomodoro suggestions
- **Overwhelm SOS** — prominent red button on Home and Focus screens; Claude responds with ONE clear next action
- **Focus Mode tab**:
  - Large current-task display (tap to edit)
  - Pomodoro ring timer with configurable duration (15–60 min)
  - Work/break session tracking with haptic feedback on completion
  - Focus task checklist — tap to complete with strikethrough animation
  - **Quick Capture** — one tap to listen, Claude organizes the thought as [Task]/[Reminder]/[Note]
  - Rotating evidence-based ADD tips
- **"Save as Focus Tasks"** — appears on Claude responses with numbered lists; extracts steps into the Focus checklist
- **Body-double-friendly** — keep the app listening while you work

---

## Setup

### Requirements
- Xcode 15+, iOS 17.0+
- Real iPhone (or Simulator with mic)
- Anthropic API key — [console.anthropic.com](https://console.anthropic.com)

### Steps
1. Open `ExecutiveAssistant.xcodeproj` in Xcode
2. Set your **Development Team** in Signing & Capabilities
3. Build & run on device
4. **Settings → API Key → Add** your `sk-ant-...` key
5. Optionally enable **Agent Mode** in Settings

### Permissions Required
| Permission | Reason |
|---|---|
| Microphone | Voice capture for transcription |
| Speech Recognition | Convert audio to text |
| Photo Library | Attach photos to conversations |
| Camera | Capture documents/whiteboards |
| Calendar Full Access | Create calendar events (Agent Mode) |
| Reminders Full Access | Create reminders (Agent Mode) |
| Contacts | Look up phone numbers/emails (Agent Mode) |

---

## Project Structure

```
ExecutiveAssistant/
├── ExecutiveAssistant.xcodeproj/
└── ExecutiveAssistant/
    ├── App/
    │   ├── ExecutiveAssistantApp.swift
    │   └── Info.plist
    ├── Models/
    │   ├── Message.swift               Message, Conversation, AttachmentItem
    │   ├── ConversationStore.swift     State management, agent tasks, ADD features
    │   └── AgentTool.swift             JSONValue, tool definitions, AgentAction
    ├── Services/
    │   ├── ClaudeService.swift         Anthropic API + SSE streaming
    │   ├── AgentService.swift          Tool-use agent loop (max 10 iterations)
    │   ├── AudioService.swift          AVAudioEngine + SFSpeechRecognizer
    │   ├── FileService.swift           Image compression, PDF extraction
    │   └── PhoneActionsService.swift   iOS actions (EventKit, Contacts, URL schemes)
    └── Views/
        ├── ContentView.swift           5-tab container
        ├── HomeView.swift              Dashboard, Overwhelm SOS, quick actions
        ├── ConversationView.swift      Chat UI + AgentActionCards
        ├── FocusView.swift             Pomodoro + task checklist + Quick Capture
        ├── HistoryView.swift           Searchable conversation history
        └── SettingsView.swift          API key, agent, ADD/focus settings
```

---

## Architecture

```
Voice/Text input
       ↓
ConversationStore.sendMessage()
  ├─ agentModeEnabled → AgentService.runAgent()
  │     Tool-use loop (up to 10 iterations):
  │       Claude API (non-streaming) + tools
  │       "tool_use" → PhoneActionsService.execute() → iOS action
  │       Progress callbacks → AgentActionCards in UI
  │       "end_turn" → done
  └─ standard mode → ClaudeService.sendMessage(stream: true)
        SSE chunks → real-time text in chat bubble

ADD Flow:
  Overwhelm SOS → sendOverwhelmSOS() → single-action response
  Claude numbered list → "Save as Focus Tasks" → extractTasksFromLastResponse()
      → focusTasks[] → FocusView checklist
  Quick Capture mic → sendQuickCapture() → [Reminder]/[Task]/[Note] response
```

---

## API Integration

**Regular chat** — SSE streaming:
```
POST /v1/messages  { stream: true, model, system, messages }
event: content_block_delta → delta.text chunks
```

**Agent mode** — tool use loop:
```
POST /v1/messages  { tools: [...12 tools...], model, system, messages }
→ stop_reason "tool_use"  → execute tools → append tool_result → repeat
→ stop_reason "end_turn"  → final response
```
