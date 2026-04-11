import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var currentIntention: Intention?
    @Published var activeSession: Session?
    @Published var isPanelVisible: Bool = false
    @Published var conversations: [ConversationTurn] = []
    @Published var currentStrictness: StrictnessLevel = .gentle
    @Published var lastClassification: URLClassification?
    @Published var distractionCount: Int = 0
    @Published var sessionHistory: [Session] = []
    @Published var isMenuBarIconActive: Bool = false
    @Published var activeTimers: [FocusTimer] = []
    @Published var showTodoPanel: Bool = false

    var sessionManager: SessionManager?
    var conversationEngine: ConversationEngine?
    var llmProvider: LLMProvider?
    let localStore: LocalStore = .shared

    private var cancellables = Set<AnyCancellable>()

    init() {
        $isPanelVisible
            .dropFirst()
            .sink { [weak self] isVisible in
                self?.handlePanelVisibilityChange(isVisible)
            }
            .store(in: &cancellables)
    }

    func configure(sessionManager: SessionManager, conversationEngine: ConversationEngine, llmProvider: LLMProvider) {
        self.sessionManager = sessionManager
        self.conversationEngine = conversationEngine
        self.llmProvider = llmProvider

        sessionManager.$currentIntention
            .receive(on: RunLoop.main)
            .assign(to: \.currentIntention, on: self)
            .store(in: &cancellables)

        sessionManager.$activeSession
            .receive(on: RunLoop.main)
            .assign(to: \.activeSession, on: self)
            .store(in: &cancellables)

        // ActivityWatch needs no special permission — start tracking immediately
        startContinuousTracking()
    }

    func startContinuousTracking() {
        Task { await sessionManager?.startContinuousTracking() }
    }

    // MARK: - Panel lifecycle

    func panelDidOpen() {
        guard conversations.isEmpty else { return }
        addConversationTurn(ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: "What are you working on?",
            context: nil
        ))
    }

    // MARK: - Session

    private func autoStartSession(task: String) {
        let intention = Intention(
            id: UUID(),
            task: task,
            whyItMatters: "",
            scheduledDate: Date(),
            strictness: currentStrictness,
            temptationBundle: nil,
            status: .active
        )
        currentIntention = intention
        localStore.save(intention: intention)
        Task {
            await sessionManager?.startSession(intention: intention)
        }
    }

    func endSession(reflection: String? = nil) {
        guard let session = activeSession, let intention = currentIntention else { return }

        var completed = session
        completed.endTime = Date()
        completed.postSessionReflection = reflection
        completed.urlClassifications = sessionManager?.urlClassifications ?? []
        localStore.save(session: completed)

        var done = intention
        done.status = .completed
        localStore.save(intention: done)

        sessionHistory.append(completed)

        Task {
            await sessionManager?.endSession(reflection: reflection)
            await conversationEngine?.clearConversation()
        }

        currentIntention = nil
        activeSession = nil

        addConversationTurn(ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: "Session ended. Take a breather — what did you get done?",
            context: nil
        ))
    }

    // MARK: - Conversation

    func addConversationTurn(_ turn: ConversationTurn) {
        conversations.append(turn)
        if conversations.count > 100 {
            conversations.removeFirst(conversations.count - 100)
        }
    }

    // MARK: - Timers

    func addTimer(label: String, minutes: Int, isNudge: Bool = false) {
        let t = FocusTimer(label: label, endsAt: Date().addingTimeInterval(TimeInterval(minutes * 60)), isNudge: isNudge)
        activeTimers.append(t)
    }

    func removeTimer(id: UUID) {
        activeTimers.removeAll { $0.id == id }
    }

    /// Called every second from the UI's TimelineView to fire expired timers.
    func tickTimers() {
        let expired = activeTimers.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        activeTimers.removeAll { $0.isExpired }
        for t in expired {
            let message = t.isNudge
                ? "Hey — \(t.label). How's it going?"
                : "⏱ Time's up: \(t.label)"
            addConversationTurn(ConversationTurn(
                timestamp: Date(), role: .assistant, content: message, context: nil
            ))
        }
        NotificationCenter.default.post(name: .focusTimerExpired, object: nil)
    }

    // MARK: - Todos

    var activeTodos: [TodoItem] { localStore.todos.filter { !$0.isCompleted } }

    func addTodo(text: String) {
        let todo = TodoItem(text: text, order: localStore.todos.count)
        localStore.save(todo: todo)
    }

    func toggleTodo(id: UUID) {
        guard let idx = localStore.todos.firstIndex(where: { $0.id == id }) else { return }
        var todo = localStore.todos[idx]
        if todo.isCompleted { todo.uncomplete() } else { todo.complete() }
        localStore.save(todo: todo)
    }

    func deleteTodo(id: UUID) {
        localStore.deleteTodo(id)
    }

    func reorderTodos(from source: IndexSet, to destination: Int) {
        localStore.reorderTodos(from: source, to: destination)
    }

    /// Scans an AI response for [TODO:text] tags, adds the task, and returns the cleaned response.
    /// Returns true in the second value if a TODO was found (so the panel can auto-open).
    func processTodoTag(in response: String) -> (String, Bool) {
        var result = response
        let todoPattern = #"\[TODO:([^\]]+)\]"#
        guard let range = result.range(of: todoPattern, options: .regularExpression) else {
            return (result, false)
        }
        let tag = String(result[range])
        // "[TODO:" is 6 characters; strip bracket wrapper
        let text = String(tag.dropFirst(6).dropLast()).trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { addTodo(text: text) }
        result = result.replacingCharacters(in: range, with: "")
                       .trimmingCharacters(in: .whitespacesAndNewlines)
        return (result, !text.isEmpty)
    }

    // MARK: - Timer tags

    /// Scans an AI response for [TIMER:Xm:label] or [NUDGE:Xm:label] tags.
    /// Strips the tag from the displayed text and schedules the appropriate timer.
    func processTimerTag(in response: String) -> String {
        var result = response
        // Process both tag types; NUDGE first so overlapping patterns don't confuse the regex
        for (pattern, isNudge) in [(#"\[NUDGE:(\d+)m:([^\]]+)\]"#, true), (#"\[TIMER:(\d+)m:([^\]]+)\]"#, false)] {
            guard let range = result.range(of: pattern, options: .regularExpression) else { continue }
            let tag = String(result[range])
            let inner = tag.dropFirst().dropLast()           // strip [ ]
            let parts = inner.split(separator: ":", maxSplits: 2)
            guard parts.count == 3, let mins = Int(parts[1].dropLast()) else { continue }
            addTimer(label: String(parts[2]), minutes: mins, isNudge: isNudge)
            result = result.replacingCharacters(in: range, with: "")
                           .trimmingCharacters(in: .whitespacesAndNewlines)
            break  // one tag per response
        }
        return result
    }

    func sendUserMessage(_ content: String) {
        var sessionWithLiveData = activeSession
        sessionWithLiveData?.urlClassifications = sessionManager?.urlClassifications ?? []

        let allActivity = sessionManager?.allActivityToday ?? []
        let recentClassification = allActivity.last ?? lastClassification
        let recentActivity = Array(allActivity.suffix(10))
        let context = ConversationContext(
            intention: currentIntention,
            session: sessionWithLiveData,
            driftDuration: nil,
            classification: recentClassification,
            recentActivity: recentActivity,
            activeTodos: activeTodos
        )
        addConversationTurn(ConversationTurn(timestamp: Date(), role: .user, content: content, context: context))

        Task {
            guard let engine = conversationEngine else {
                addConversationTurn(ConversationTurn(
                    timestamp: Date(),
                    role: .assistant,
                    content: "Add your API key in Settings (gear icon) to enable AI responses.",
                    context: context
                ))
                return
            }
            let rawResponse = await engine.continueConversation(userMessage: content, context: context)
            let timerProcessed = processTimerTag(in: rawResponse)
            let (response, addedTodo) = processTodoTag(in: timerProcessed)
            if addedTodo { showTodoPanel = true }
            addConversationTurn(ConversationTurn(timestamp: Date(), role: .assistant, content: response, context: context))

            if sessionManager?.sessionState == .idle {
                await extractAndStartSessionIfReady()
            }
        }
    }

    private func extractAndStartSessionIfReady() async {
        guard let engine = conversationEngine,
              sessionManager?.sessionState == .idle else { return }
        guard conversations.contains(where: { $0.role == .user }) else { return }
        if let task = await engine.extractIntentFromConversation(conversations) {
            autoStartSession(task: task)
        }
    }

    func clearConversations() {
        conversations.removeAll()
    }

    // MARK: - Distraction

    func logDistraction(url: String?, category: String) {
        guard var session = activeSession else { return }
        let log = DistractionLog(timestamp: Date(), url: url, category: category, duration: 0, acknowledged: false)
        session.interruptions.append(log)
        distractionCount += 1
        activeSession = session
    }

    func recordClassification(_ classification: URLClassification) {
        lastClassification = classification
        if !classification.onTask {
            logDistraction(url: classification.url, category: classification.category.rawValue)
        }
    }

    // MARK: - Panel visibility

    func togglePanel() { isPanelVisible.toggle() }
    func showPanel()   { isPanelVisible = true }
    func hidePanel()   { isPanelVisible = false }

    private func handlePanelVisibilityChange(_ isVisible: Bool) {
        isMenuBarIconActive = isVisible
        NotificationCenter.default.post(
            name: .panelVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": isVisible]
        )
    }
}

// MARK: - Focus Timer

struct FocusTimer: Identifiable {
    let id: UUID
    let label: String
    let endsAt: Date
    /// Nudge timers are LLM-initiated — they fire the same way but show no countdown, just a calm acknowledgement.
    let isNudge: Bool

    init(label: String, endsAt: Date, isNudge: Bool = false) {
        self.id = UUID()
        self.label = label
        self.endsAt = endsAt
        self.isNudge = isNudge
    }

    var secondsRemaining: Int { max(0, Int(endsAt.timeIntervalSinceNow)) }
    var isExpired: Bool { endsAt <= Date() }

    var formattedRemaining: String {
        let s = secondsRemaining
        let m = s / 60; let sec = s % 60
        return m > 0 ? "\(m)m \(String(format: "%02d", sec))s" : "\(String(format: "%02d", sec))s"
    }

    /// Human-readable target time, e.g. "at 3:45 PM"
    var formattedTargetTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "at \(f.string(from: endsAt))"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let panelVisibilityChanged = Notification.Name("PanelVisibilityChanged")
    static let focusTimerExpired      = Notification.Name("FocusTimerExpired")
}

// MARK: - Session Extension

extension Session {
    @MainActor var intention: Intention? { LocalStore.shared.intention(for: intentionId) }

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
}
