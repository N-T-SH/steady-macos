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
    @Published var urlClassifications: [URLClassification] = []
    
    private var timer: Timer?
    private var pauseStartTime: Date?
    private var totalPausedTime: TimeInterval = 0
    private var urlTracker: URLTracker?
    private let notificationManager = NotificationManager.shared
    private var llmProvider: LLMProvider?
    
    enum SessionState: String, Codable {
        case idle
        case active
        case paused
        case ending
    }
    
    init() {}
    
    func configure(llmProvider: LLMProvider) {
        self.llmProvider = llmProvider
    }
    
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
        
        startTimer()
        
        // Start URL tracking if LLM provider is available
        if let llmProvider = llmProvider {
            let tracker = URLTracker()
            self.urlTracker = tracker
            await tracker.startTracking(intention: intention, llmProvider: llmProvider)
        }
        
        // Schedule session start notification
        await notificationManager.scheduleSessionStart(intention: intention)
    }
    
    func pauseSession() async {
        guard sessionState == .active else { return }
        
        sessionState = .paused
        isPaused = true
        pauseStartTime = Date()
        stopTimer()
        
        // Stop URL tracking while paused
        if let tracker = urlTracker {
            await tracker.stopTracking()
        }
    }
    
    func resumeSession() async {
        guard sessionState == .paused, let pauseStart = pauseStartTime else { return }
        
        let pauseDuration = Date().timeIntervalSince(pauseStart)
        totalPausedTime += pauseDuration
        
        sessionState = .active
        isPaused = false
        pauseStartTime = nil
        
        startTimer()
        
        // Resume URL tracking
        if let tracker = urlTracker, let intention = currentIntention, let llmProvider = llmProvider {
            await tracker.startTracking(intention: intention, llmProvider: llmProvider)
        }
    }
    
    func endSession(reflection: String? = nil) async {
        guard sessionState == .active || sessionState == .paused else { return }
        
        sessionState = .ending
        stopTimer()
        
        if let pauseStart = pauseStartTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        
        // Stop URL tracking
        if let tracker = urlTracker {
            await tracker.stopTracking()
            self.urlTracker = nil
        }
        
        if var session = activeSession {
            session.endTime = Date()
            session.postSessionReflection = reflection
            session.urlClassifications = urlClassifications
            self.activeSession = session
            
            // Send session complete notification
            await notificationManager.sendSessionComplete(session: session)
        }
        
        // Clear notifications for this session
        if let session = activeSession {
            await notificationManager.clearNotifications(for: session.id)
        }
        
        sessionState = .idle
        currentIntention = nil
        pauseStartTime = nil
        totalPausedTime = 0
        urlClassifications = []
    }
    
    func logDistraction(reason: String) {
        guard sessionState == .active || sessionState == .paused else { return }
        
        let distraction = DistractionLog(
            timestamp: Date(),
            url: nil,
            category: reason,
            duration: 0,
            acknowledged: false
        )
        
        if var session = activeSession {
            session.interruptions.append(distraction)
            self.activeSession = session
        }
    }
    
    func acknowledgeDistraction(at index: Int) {
        guard var session = activeSession,
              index < session.interruptions.count else { return }
        
        session.interruptions[index].acknowledged = true
        self.activeSession = session
    }
    
    func handleOffTaskClassification(_ classification: URLClassification) async {
        guard sessionState == .active else { return }
        
        urlClassifications.append(classification)
        
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
            
            // Send drift alert based on strictness level
            switch currentIntention?.strictness ?? .gentle {
            case .quiet:
                break
            case .gentle:
                await notificationManager.sendDriftAlert(classification: classification)
            case .focused:
                await notificationManager.sendDriftAlert(classification: classification)
            case .accountable:
                await notificationManager.sendDriftAlert(classification: classification)
            }
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateElapsedTime() {
        guard let session = activeSession else { return }
        let totalTime = Date().timeIntervalSince(session.startTime)
        elapsedTime = totalTime - totalPausedTime
    }
    
    func formattedElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    func remainingTime() -> TimeInterval? {
        guard let intention = currentIntention else { return nil }
        let plannedSeconds = TimeInterval(intention.plannedDuration * 60)
        return max(0, plannedSeconds - elapsedTime)
    }
    
    func formattedRemainingTime() -> String {
        guard let remaining = remainingTime() else { return "--:--" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func progressPercentage() -> Double {
        guard let intention = currentIntention, intention.plannedDuration > 0 else { return 0 }
        let plannedSeconds = TimeInterval(intention.plannedDuration * 60)
        return min(1.0, elapsedTime / plannedSeconds)
    }
    
    deinit {
        timer?.invalidate()
    }
}
