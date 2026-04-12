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
    @Published var currentInfographic: InfographicSpec? = nil

    private var infographicRefreshedAt: Date? = nil
    /// Cached page title fetched from the configured content feed URL.
    private var contentFeedTitle: String? = nil
    private var contentFeedTitleFetchedFor: String? = nil   // URL that produced the cached title

    var sessionManager: SessionManager?
    var conversationEngine: ConversationEngine?
    var llmProvider: LLMProvider?
    let localStore: LocalStore = .shared

    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?

    init() {
        $isPanelVisible
            .dropFirst()
            .sink { [weak self] isVisible in
                self?.handlePanelVisibilityChange(isVisible)
            }
            .store(in: &cancellables)

        // Forward LocalStore changes so views observing AppState re-render immediately
        localStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
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

        // Propagate activity and project config changes to URLTracker in real-time
        localStore.$activities
            .combineLatest(localStore.$projects)
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.sessionManager?.updateProjectConfig() }
            }
            .store(in: &cancellables)

        // ActivityWatch needs no special permission — start tracking immediately
        startContinuousTracking()

        // Show an initial infographic immediately (local, no LLM needed)
        refreshInfographicIfNeeded()
    }

    func startContinuousTracking() {
        Task { await sessionManager?.startContinuousTracking() }
    }

    // MARK: - Panel lifecycle

    func panelDidOpen() {
        refreshInfographicIfNeeded()
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
        startTickTimerIfNeeded()
    }

    func removeTimer(id: UUID) {
        activeTimers.removeAll { $0.id == id }
        if activeTimers.isEmpty { stopTickTimer() }
    }

    private func startTickTimerIfNeeded() {
        guard tickTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickTimers() }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tickTimers() {
        let expired = activeTimers.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        activeTimers.removeAll { $0.isExpired }
        if activeTimers.isEmpty { stopTickTimer() }
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

    var activeTodos: [TodoItem] { localStore.todos.filter { !$0.isCompleted && !$0.isStashed } }
    var completedTodos: [TodoItem] { localStore.todos.filter { $0.isCompleted } }
    var stashedTodos: [TodoItem] { localStore.todos.filter { $0.isStashed && !$0.isCompleted } }

    func addTodo(text: String) {
        let projectName = extractFirstProjectTag(from: text)
        if let name = projectName { localStore.addProjectIfNeeded(name) }
        let todo = TodoItem(text: text, order: localStore.todos.count, projectName: projectName)
        localStore.save(todo: todo)
    }

    /// Extracts the first #project-name tag from text. Returns the project name (without #).
    func extractFirstProjectTag(from text: String) -> String? {
        let pattern = #"#([A-Za-z0-9][A-Za-z0-9\-_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Scans content for #project-name tags, registers any new projects, and returns found names.
    func processProjectHashtags(in content: String) -> [String] {
        let pattern = #"#([A-Za-z0-9][A-Za-z0-9\-_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            let name = String(content[range])
            localStore.addProjectIfNeeded(name)
            return name
        }
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

    func stashTodo(id: UUID) {
        guard let idx = localStore.todos.firstIndex(where: { $0.id == id }) else { return }
        var todo = localStore.todos[idx]
        todo.stash()
        localStore.save(todo: todo)
    }

    func restoreTodo(id: UUID) {
        guard let idx = localStore.todos.firstIndex(where: { $0.id == id }) else { return }
        var todo = localStore.todos[idx]
        todo.isStashed = false
        todo.stashedAt = nil
        localStore.save(todo: todo)
    }

    func purgeOldDoneTodos() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        localStore.todos
            .filter { $0.isCompleted && ($0.completedAt ?? $0.createdAt) < cutoff }
            .forEach { localStore.deleteTodo($0.id) }
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
        // Register any #project-name tags mentioned in the message
        _ = processProjectHashtags(in: content)

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

    // MARK: - Infographic

    func refreshInfographicIfNeeded() {
        let stats = buildFocusStats()

        if stats.totalEvents == 0 {
            // No activity — show content feed card, fetch title if needed
            currentInfographic = buildLocalInfographic(stats: stats)
            Task { await fetchContentFeedCardAndRefresh(stats: stats) }
            return
        }

        // Always rebuild local card immediately from fresh stats
        currentInfographic = buildLocalInfographic(stats: stats)

        // LLM upgrade only every 2 hours (network call)
        let twoHours: TimeInterval = 2 * 60 * 60
        let needsLLMRefresh = infographicRefreshedAt.map { Date().timeIntervalSince($0) >= twoHours } ?? true
        guard needsLLMRefresh, llmProvider != nil else { return }
        Task { await refreshInfographicFromLLM(stats: stats) }
    }

    private func fetchContentFeedCardAndRefresh(stats: FocusStats) async {
        let urlString = UserDefaults.standard.string(forKey: "content.feedURL")
            ?? "https://bookmarkgarden.vercel.app/?item=tweet-2036000729173987338"

        // Only re-fetch if the URL changed
        if contentFeedTitleFetchedFor != urlString {
            contentFeedTitle = await fetchPageTitle(urlString: urlString)
            contentFeedTitleFetchedFor = urlString
        }

        if contentFeedTitle != nil {
            currentInfographic = buildLocalInfographic(stats: stats)
        }

        // Still try LLM upgrade if provider available
        if llmProvider != nil {
            Task { await refreshInfographicFromLLM(stats: stats) }
        }
    }

    private func fetchPageTitle(urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        // Extract <title>…</title>
        guard let start = html.range(of: "<title>", options: .caseInsensitive)?.upperBound,
              let end   = html[start...].range(of: "</title>", options: .caseInsensitive)?.lowerBound
        else { return nil }
        let raw = String(html[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Collapse whitespace runs
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return raw.isEmpty ? nil : raw
    }

    private func refreshInfographicFromLLM(stats: FocusStats) async {
        guard let llm = llmProvider else { return }
        guard let spec = try? await llm.generateInfographic(stats: stats) else { return }
        currentInfographic = spec
        infographicRefreshedAt = Date()
    }

    /// Deterministically pick the most interesting card from local data — no LLM needed.
    private func buildLocalInfographic(stats: FocusStats) -> InfographicSpec {
        // No activity yet — show the content feed card
        if stats.totalEvents == 0 {
            let feedURL = UserDefaults.standard.string(forKey: "content.feedURL")
                ?? "https://bookmarkgarden.vercel.app/?item=tweet-2036000729173987338"
            let title = contentFeedTitle ?? "Open content feed"
            return .stat(label: "content feed", value: title, subtitle: nil, accent: nil, linkURL: feedURL)
        }

        // Active session — show elapsed time + on-task %
        if let sessionMins = stats.currentSessionMinutes {
            let h = sessionMins / 60; let m = sessionMins % 60
            let formatted = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return .stat(label: "In session", value: formatted,
                         subtitle: "\(stats.onTaskPercent)% on-task", accent: "green")
        }

        // Good focus day — show 3-segment bar
        if stats.totalEvents >= 6 && stats.onTaskPercent >= 50 {
            let total    = Double(stats.totalEvents)
            let onRatio  = Double(stats.onTaskEvents)    / total
            let driftRatio = Double(stats.driftEvents)   / total
            let goofRatio  = Double(stats.goofingOffEvents) / total
            var segments: [InfographicSpec.BarSegment] = [
                .init(label: "On-task", ratio: onRatio,    color: "green")
            ]
            if driftRatio > 0 { segments.append(.init(label: "Drift",   ratio: driftRatio, color: "yellow")) }
            if goofRatio  > 0 { segments.append(.init(label: "Off",     ratio: goofRatio,  color: "red")) }
            return .barSplit(title: "Today's focus", segments: segments)
        }

        // Top project known — show it with time
        if let project = stats.topProject, stats.focusMinutes > 0 {
            let h = stats.focusMinutes / 60; let m = stats.focusMinutes % 60
            let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return .labelValue(rows: [
                .init(label: "Working on", value: project),
                .init(label: "Focus time", value: timeStr)
            ])
        }

        // Recent trend as dots
        if stats.recentChecks.count >= 5 {
            let dotColors = stats.recentChecks.map { $0.colorName }
            return .dotRow(title: "Recent activity", dots: dotColors)
        }

        // Default: simple focus time stat
        let focusStr: String
        if stats.focusMinutes >= 60 {
            focusStr = "\(stats.focusMinutes / 60)h \(stats.focusMinutes % 60)m"
        } else {
            focusStr = "\(stats.focusMinutes)m"
        }
        return .stat(label: "Focus today", value: focusStr,
                     subtitle: "\(stats.onTaskPercent)% on-task", accent: stats.onTaskPercent >= 70 ? "green" : nil)
    }

    /// Effective TaskStatus for a classification (mirrors URLTracker's 3-level priority chain).
    private func effectiveStatus(_ c: URLClassification) -> TaskStatus {
        // 1. Project → associated activity
        if let project = c.project,
           let status = localStore.taskStatus(forProject: project) {
            return status
        }
        // 2. URLCategory → activity override
        if let activity = localStore.activities.first(where: { $0.urlCategoryRaw == c.category.rawValue }) {
            return activity.status
        }
        // 3. Stored classification status
        return c.taskStatus
    }

    private func buildFocusStats() -> FocusStats {
        let activity = sessionManager?.allActivityToday ?? []
        let total    = activity.count
        let statuses = activity.map { effectiveStatus($0) }
        let onTask      = statuses.filter { $0 == .onTask     }.count
        let driftCount  = statuses.filter { $0 == .drift      }.count
        let goofCount   = statuses.filter { $0 == .goofingOff }.count
        let pct = total > 0 ? Int(Double(onTask) / Double(total) * 100) : 0
        let focusMins = onTask * 10 / 60

        // Longest contiguous on-task block
        var longest = 0, current = 0
        for s in statuses {
            if s == .onTask { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        let longestMins = longest * 10 / 60

        let projectCounts = Dictionary(grouping: activity.compactMap { $0.project }, by: { $0 })
            .mapValues { $0.count }
        let topProject = projectCounts.max(by: { $0.value < $1.value })?.key

        let catCounts = Dictionary(grouping: activity.map { $0.category.rawValue }, by: { $0 })
            .mapValues { $0.count }
        let topCategory = catCounts.max(by: { $0.value < $1.value })?.key

        let sessionMins: Int? = activeSession.map { Int(Date().timeIntervalSince($0.startTime) / 60) }

        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"

        let lastDistraction = zip(activity, statuses).reversed().first(where: { $0.1 != .onTask })?.0
        let sinceDistraction: Int? = lastDistraction.map { Int(Date().timeIntervalSince($0.timestamp) / 60) }

        let recentChecks = Array(zip(activity, statuses).suffix(10)).map { $0.1 }

        return FocusStats(
            totalEvents: total,
            onTaskEvents: onTask,
            driftEvents: driftCount,
            goofingOffEvents: goofCount,
            onTaskPercent: pct,
            focusMinutes: focusMins,
            sessionCount: sessionHistory.count,
            longestBlockMinutes: longestMins,
            topProject: topProject,
            topCategory: topCategory,
            currentSessionMinutes: sessionMins,
            timeOfDay: timeOfDay,
            minutesSinceLastDistraction: sinceDistraction,
            recentChecks: recentChecks
        )
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
    func showPanel()   { isPanelVisible = true; refreshInfographicIfNeeded() }
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
