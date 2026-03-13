import SwiftUI

struct FocusView: View {
    @EnvironmentObject var store: ConversationStore
    @StateObject private var timer = PomodoroTimer()
    @State private var newTaskTitle = ""
    @State private var showingAddTask = false
    @State private var isQuickCapturing = false
    @FocusState private var addTaskFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Current Focus Display
                    CurrentFocusCard(timer: timer)

                    // Pomodoro Timer Ring
                    PomodoroRingView(timer: timer)

                    // Action Buttons Row
                    HStack(spacing: 12) {
                        // Overwhelm SOS
                        Button {
                            store.sendOverwhelmSOS()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sos")
                                    .font(.subheadline.bold())
                                Text("Help, I'm stuck")
                                    .font(.subheadline.bold())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red.gradient)
                            .clipShape(Capsule())
                        }

                        // Quick Capture
                        Button {
                            isQuickCapturing = true
                            store.startListening()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: store.isListening && isQuickCapturing ? "stop.fill" : "mic.fill")
                                    .font(.subheadline.bold())
                                Text(store.isListening && isQuickCapturing ? "Stop" : "Quick Capture")
                                    .font(.subheadline.bold())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background((store.isListening && isQuickCapturing ? Color.orange : Color.indigo).gradient)
                            .clipShape(Capsule())
                        }
                        .onChange(of: store.isListening) { listening in
                            if !listening && isQuickCapturing {
                                isQuickCapturing = false
                                let captured = store.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !captured.isEmpty {
                                    store.transcribedText = ""
                                    store.sendQuickCapture(captured)
                                }
                            }
                        }
                    }

                    // Focus Tasks Checklist
                    FocusTasksSection(showingAddTask: $showingAddTask, newTaskTitle: $newTaskTitle, addTaskFocused: _addTaskFocused)

                    // Tips Card
                    ADDTipsCard()

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Focus Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach([15, 20, 25, 30, 45, 60], id: \.self) { mins in
                            Button("\(mins) min Pomodoro") {
                                timer.setDuration(mins)
                            }
                        }
                        Divider()
                        Button("Clear Completed", role: .destructive) {
                            store.clearCompletedTasks()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            timer.setDuration(store.pomodoroDuration)
        }
    }
}

// MARK: - Current Focus Card

struct CurrentFocusCard: View {
    @EnvironmentObject var store: ConversationStore
    @ObservedObject var timer: PomodoroTimer
    @State private var isEditing = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT FOCUS")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .tracking(1)

            if isEditing {
                TextField("What are you working on?", text: $store.currentFocusTask)
                    .font(.title3.bold())
                    .focused($fieldFocused)
                    .onSubmit {
                        isEditing = false
                        timer.taskName = store.currentFocusTask
                    }
            } else {
                Button {
                    isEditing = true
                    fieldFocused = true
                } label: {
                    Text(store.currentFocusTask.isEmpty ? "Tap to set your focus..." : store.currentFocusTask)
                        .font(.title3.bold())
                        .foregroundColor(store.currentFocusTask.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .onTapGesture {
            isEditing = true
            fieldFocused = true
        }
    }
}

// MARK: - Pomodoro Timer Ring

class PomodoroTimer: ObservableObject {
    @Published var timeRemaining: Int = 25 * 60
    @Published var totalTime: Int = 25 * 60
    @Published var isRunning: Bool = false
    @Published var sessionType: SessionType = .work
    @Published var completedSessions: Int = 0
    var taskName: String = ""

    enum SessionType {
        case work, shortBreak, longBreak

        var label: String {
            switch self {
            case .work: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }

        var color: Color {
            switch self {
            case .work: return .indigo
            case .shortBreak: return .green
            case .longBreak: return .teal
            }
        }

        var breakDuration: Int {
            switch self {
            case .work: return 0
            case .shortBreak: return 5 * 60
            case .longBreak: return 15 * 60
            }
        }
    }

    private var timer: Timer?
    private var workDuration: Int = 25 * 60

    func setDuration(_ minutes: Int) {
        workDuration = minutes * 60
        if !isRunning {
            totalTime = workDuration
            timeRemaining = workDuration
        }
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.sessionComplete()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        timeRemaining = sessionType == .work ? workDuration : sessionType.breakDuration
        totalTime = timeRemaining
    }

    private func sessionComplete() {
        pause()
        if sessionType == .work {
            completedSessions += 1
            let isLongBreak = completedSessions % 4 == 0
            sessionType = isLongBreak ? .longBreak : .shortBreak
            let breakDuration = isLongBreak ? 15 * 60 : 5 * 60
            totalTime = breakDuration
            timeRemaining = breakDuration
        } else {
            sessionType = .work
            totalTime = workDuration
            timeRemaining = workDuration
        }
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    var progress: Double {
        totalTime > 0 ? Double(totalTime - timeRemaining) / Double(totalTime) : 0
    }

    var timeString: String {
        let m = timeRemaining / 60
        let s = timeRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct PomodoroRingView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(spacing: 16) {
            // Ring
            ZStack {
                Circle()
                    .stroke(timer.sessionType.color.opacity(0.15), lineWidth: 16)
                    .frame(width: 180, height: 180)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(
                        timer.sessionType.color.gradient,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)

                VStack(spacing: 4) {
                    Text(timer.timeString)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(timer.sessionType.label)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                }
            }

            // Session dots
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < timer.completedSessions % 4 ? timer.sessionType.color : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            // Controls
            HStack(spacing: 24) {
                Button {
                    timer.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                }

                Button {
                    timer.toggle()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(timer.sessionType.color.gradient)
                        .clipShape(Circle())
                        .shadow(color: timer.sessionType.color.opacity(0.4), radius: 8, y: 4)
                }

                Button {
                    timer.sessionComplete_public()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

extension PomodoroTimer {
    func sessionComplete_public() { sessionComplete() }
}

// MARK: - Focus Tasks Section

struct FocusTasksSection: View {
    @EnvironmentObject var store: ConversationStore
    @Binding var showingAddTask: Bool
    @Binding var newTaskTitle: String
    @FocusState var addTaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus Tasks")
                    .font(.headline)
                Spacer()
                if !store.focusTasks.isEmpty {
                    Text("\(store.focusTasks.filter { $0.isCompleted }.count)/\(store.focusTasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    showingAddTask = true
                    addTaskFocused = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.indigo)
                        .font(.title3)
                }
            }

            if showingAddTask {
                HStack {
                    TextField("Add a task...", text: $newTaskTitle)
                        .focused($addTaskFocused)
                        .onSubmit {
                            if !newTaskTitle.isEmpty {
                                store.addFocusTask(newTaskTitle)
                                newTaskTitle = ""
                            }
                            showingAddTask = false
                        }
                    Button("Add") {
                        if !newTaskTitle.isEmpty {
                            store.addFocusTask(newTaskTitle)
                            newTaskTitle = ""
                        }
                        showingAddTask = false
                    }
                    .foregroundColor(.indigo)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }

            if store.focusTasks.isEmpty && !showingAddTask {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No focus tasks yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Ask the assistant to break down a task,\nor tap + to add one manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(store.focusTasks) { task in
                    FocusTaskRow(task: task)
                }
                .onDelete { offsets in
                    store.deleteFocusTasks(at: offsets)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct FocusTaskRow: View {
    @EnvironmentObject var store: ConversationStore
    let task: FocusTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    store.toggleFocusTask(task)
                }
                if !task.isCompleted {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary)

                if let mins = task.estimatedMinutes {
                    Text("~\(mins) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !task.isCompleted {
                Button {
                    store.currentFocusTask = task.title
                } label: {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundColor(.indigo)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ADD Tips Card

struct ADDTipsCard: View {
    @State private var currentTip = Int.random(in: 0..<tips.count)

    private static let tips = [
        "Start with just 2 minutes. Getting started is the hardest part.",
        "If a task takes less than 2 minutes, do it now.",
        "Body doubling works — keep the app open while you work.",
        "Done is better than perfect. Ship it.",
        "Break the task down until the first step is obvious.",
        "Set a timer. Time becomes real when it's counting down.",
        "Reward yourself after completing each Pomodoro.",
        "One tab open. One task. One focus.",
        "If you're stuck, say it out loud to the assistant.",
        "The goal isn't to finish — it's to start."
    ]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.title3)

            Text(Self.tips[currentTip])
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                withAnimation {
                    currentTip = (currentTip + 1) % Self.tips.count
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}
