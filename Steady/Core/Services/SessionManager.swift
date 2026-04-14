import Foundation
import Combine
import SwiftUI

@MainActor
class SessionManager: ObservableObject {
    @Published var activeSession: Session?
    @Published var currentIntention: Intention?
    @Published var elapsedTime: TimeInterval = 0
    @Published var isPaused: Bool = false
    @Published var sessionState: SessionState = .idle
    @Published var urlClassifications: [URLClassification] = []    // current session slice
    @Published var allActivityToday: [URLClassification] = []      // all activity since app launch
    @Published var activityWatchConnected: Bool? = nil             // nil = not yet checked

    private var elapsedTimer: Timer?
    private var pauseStartTime: Date?
    private var totalPausedTime: TimeInterval = 0
    private var urlTracker: URLTracker?
    private var llmProvider: LLMProvider?

    enum SessionState: String, Codable {
        case idle, active, paused, ending
    }

    init() {}

    func configure(llmProvider: LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - Always-on tracking

    /// Start continuous URL tracking regardless of session state.
    /// Safe to call multiple times — won't create duplicate trackers.
    func startContinuousTracking() async {
        guard urlTracker == nil else {
            print("[SessionManager] startContinuousTracking — tracker already running")
            return
        }
        guard let llmProvider = llmProvider else {
            print("[SessionManager] startContinuousTracking — no llmProvider configured")
            return
        }
        print("[SessionManager] startContinuousTracking — creating URLTracker")
        let tracker = URLTracker()
        self.urlTracker = tracker
        await tracker.setDelegate(self)
        // Remove any stale domain-level rules for sites that need per-page classification.
        LocalStore.shared.purgeURLRules(forDomains: URLTracker.dynamicContentDomains)
        let rules = LocalStore.shared.urlRules
        let projects = LocalStore.shared.intentions.map { $0.task }
        await tracker.startTracking(llmProvider: llmProvider, knownRules: rules, knownProjects: projects)
        // Populate the active-project set immediately so deleted projects are filtered from day one.
        let activities = LocalStore.shared.activities
        let userProjects = LocalStore.shared.projects
        await tracker.updateProjectConfig(activities: activities, projects: userProjects)
    }

    /// Reassign a captured activity to a different project/category.
    /// Updates in-memory log, persists a URL rule, and refreshes the tracker.
    func reclassify(classificationAt timestamp: Date, project: String) {
        guard let idx = allActivityToday.firstIndex(where: { $0.timestamp == timestamp }) else { return }
        let old = allActivityToday[idx]
        // Effective status: use project's assigned category if available, else keep original
        let taskStatus = LocalStore.shared.taskStatus(forProject: project) ?? old.taskStatus
        let updated = URLClassification(
            url: old.url, pageTitle: old.pageTitle,
            taskStatus: taskStatus,
            project: project,
            category: old.category,
            confidence: 1.0,
            reasoning: "User classified",
            timestamp: old.timestamp
        )
        allActivityToday[idx] = updated

        let ruleKey = old.url.hasPrefix("app://") ? old.url : (URL(string: old.url)?.host ?? old.url)
        LocalStore.shared.addProjectIfNeeded(project)
        LocalStore.shared.saveURLRule(domain: ruleKey, projectName: project, category: old.category)

        if let tracker = urlTracker {
            let rules = LocalStore.shared.urlRules
            let projects = LocalStore.shared.intentions.map { $0.task }
            Task {
                await tracker.updateKnownRules(rules)
                await tracker.updateKnownProjects(projects)
            }
        }
    }

    func updateProjectConfig() async {
        guard let tracker = urlTracker else { return }
        let activities = LocalStore.shared.activities
        let projects   = LocalStore.shared.projects
        await tracker.updateProjectConfig(activities: activities, projects: projects)
    }

    // MARK: - Session lifecycle

    func startSession(intention: Intention) async {
        guard sessionState == .idle else { return }

        let session = Session(
            id: UUID(),
            intentionId: intention.id,
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 5,
            postSessionReflection: nil,
            urlClassifications: []
        )

        self.activeSession = session
        self.currentIntention = intention
        self.sessionState = .active
        self.elapsedTime = 0
        self.totalPausedTime = 0
        self.urlClassifications = []

        startElapsedTimer()

        // Update intention context on the already-running tracker.
        // If tracking hasn't started yet (e.g. permission just granted), start it now.
        if let tracker = urlTracker {
            await tracker.updateIntention(intention)
        } else {
            await startContinuousTracking()
            if let tracker = urlTracker {
                await tracker.updateIntention(intention)
            }
        }

    }

    func pauseSession() async {
        guard sessionState == .active else { return }
        sessionState = .paused
        isPaused = true
        pauseStartTime = Date()
        stopElapsedTimer()
        // Tracker keeps running — we still capture activity while paused
    }

    func resumeSession() async {
        guard sessionState == .paused, let pauseStart = pauseStartTime else { return }
        totalPausedTime += Date().timeIntervalSince(pauseStart)
        sessionState = .active
        isPaused = false
        pauseStartTime = nil
        startElapsedTimer()
        // Tracker is already running
    }

    func endSession(reflection: String? = nil) async {
        guard sessionState == .active || sessionState == .paused else { return }
        sessionState = .ending
        stopElapsedTimer()

        if let pauseStart = pauseStartTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }

        // Remove intention context from tracker — it keeps running for passive tracking
        if let tracker = urlTracker {
            await tracker.updateIntention(nil)
        }

        if var session = activeSession {
            session.endTime = Date()
            session.postSessionReflection = reflection
            session.urlClassifications = urlClassifications
            self.activeSession = session
        }

        sessionState = .idle
        currentIntention = nil
        pauseStartTime = nil
        totalPausedTime = 0
        urlClassifications = []
    }

    func logDistraction(reason: String) {
        guard sessionState == .active || sessionState == .paused else { return }
        let distraction = DistractionLog(timestamp: Date(), url: nil, category: reason, duration: 0, acknowledged: false)
        if var session = activeSession {
            session.interruptions.append(distraction)
            self.activeSession = session
        }
    }

    func handleOffTaskClassification(_ classification: URLClassification) {
        guard sessionState == .active else { return }

        if !classification.onTask {
            let distraction = DistractionLog(
                timestamp: Date(),
                url: classification.url,
                category: classification.category.rawValue,
                duration: 0,
                acknowledged: false
            )
            if var session = activeSession {
                session.interruptions.append(distraction)
                self.activeSession = session
            }
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedTime() {
        guard let session = activeSession else { return }
        elapsedTime = Date().timeIntervalSince(session.startTime) - totalPausedTime
    }

    func formattedElapsedTime() -> String {
        let h = Int(elapsedTime) / 3600
        let m = (Int(elapsedTime) % 3600) / 60
        let s = Int(elapsedTime) % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return String(format: "%ds", s)
    }

    deinit { elapsedTimer?.invalidate() }
}

// MARK: - URLTrackerDelegate

extension SessionManager: URLTrackerDelegate {
    nonisolated func urlTracker(_ tracker: URLTracker, didDetectURL url: String, title: String) {}

    nonisolated func urlTracker(_ tracker: URLTracker, didClassifyURL classification: URLClassification) {
        print("[SessionManager] classified: \(URL(string: classification.url)?.host ?? classification.url) — \(classification.category.rawValue), onTask=\(classification.onTask), project=\(classification.project ?? "nil")")
        Task { @MainActor in
            // Always accumulate in the daily log
            self.allActivityToday.append(classification)
            // Also accumulate in the session slice if a session is active
            if self.sessionState == .active || self.sessionState == .paused {
                self.urlClassifications.append(classification)
            }
        }
    }

    nonisolated func urlTracker(_ tracker: URLTracker, didDetectOffTask classification: URLClassification) {
        Task { @MainActor in
            self.handleOffTaskClassification(classification)
        }
    }

    nonisolated func urlTracker(_ tracker: URLTracker, didDiscoverNewRule domain: String, projectName: String, category: URLCategory) {
        Task { @MainActor in
            LocalStore.shared.saveURLRule(domain: domain, projectName: projectName, category: category)
            if let tracker = self.urlTracker {
                let rules = LocalStore.shared.urlRules
                await tracker.updateKnownRules(rules)
            }
        }
    }

    nonisolated func urlTracker(_ tracker: URLTracker, didUpdateActivityWatchStatus available: Bool) {
        Task { @MainActor in
            self.activityWatchConnected = available
        }
    }
}
