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
    
    private var timer: Timer?
    private var pauseStartTime: Date?
    private var totalPausedTime: TimeInterval = 0
    private let urlTracker: URLTracker
    private let notificationManager: NotificationManager
    
    enum SessionState: String, Codable {
        case idle
        case active
        case paused
        case ending
    }
    
    init(urlTracker: URLTracker = URLTracker(), 
         notificationManager: NotificationManager = NotificationManager()) {
        self.urlTracker = urlTracker
        self.notificationManager = notificationManager
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
        
        startTimer()
        await urlTracker.startTracking()
        
        notificationManager.scheduleSessionNotification(
            title: "Session Started",
            body: "Focus on: \(intention.task)"
        )
        
        urlTracker.classificationHandler = { [weak self] classification in
            self?.handleURLClassification(classification)
        }
    }
    
    func pauseSession() {
        guard sessionState == .active else { return }
        
        sessionState = .paused
        isPaused = true
        pauseStartTime = Date()
        stopTimer()
        
        notificationManager.scheduleSessionNotification(
            title: "Session Paused",
            body: "Your session is paused. Resume when ready."
        )
    }
    
    func resumeSession() {
        guard sessionState == .paused, let pauseStart = pauseStartTime else { return }
        
        let pauseDuration = Date().timeIntervalSince(pauseStart)
        totalPausedTime += pauseDuration
        
        sessionState = .active
        isPaused = false
        pauseStartTime = nil
        
        startTimer()
        
        notificationManager.scheduleSessionNotification(
            title: "Session Resumed",
            body: "Back to focusing on: \(currentIntention?.task ?? "your task")"
        )
    }
    
    func endSession(reflection: String? = nil) async {
        guard sessionState == .active || sessionState == .paused else { return }
        
        sessionState = .ending
        stopTimer()
        
        if let pauseStart = pauseStartTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        
        await urlTracker.stopTracking()
        
        if var session = activeSession {
            session.endTime = Date()
            session.postSessionReflection = reflection
            session.urlClassifications = urlTracker.getClassifications()
            self.activeSession = session
        }
        
        notificationManager.scheduleSessionNotification(
            title: "Session Complete",
            body: "Great work! Session ended after \(formattedElapsedTime())."
        )
        
        sessionState = .idle
        currentIntention = nil
        pauseStartTime = nil
        totalPausedTime = 0
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
        
        notificationManager.scheduleSessionNotification(
            title: "Distraction Logged",
            body: "Reason: \(reason)"
        )
    }
    
    func acknowledgeDistraction(at index: Int) {
        guard var session = activeSession,
              index < session.interruptions.count else { return }
        
        session.interruptions[index].acknowledged = true
        self.activeSession = session
    }
    
    func setStrictnessMode(_ level: StrictnessLevel) {
        urlTracker.setStrictnessLevel(level)
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
    
    private func handleURLClassification(_ classification: URLClassification) {
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
            
            switch currentIntention?.strictness ?? .gentle {
            case .quiet:
                break
            case .gentle:
                if Int.random(in: 1...3) == 1 {
                    notificationManager.notifyOffTask(classification: classification)
                }
            case .focused:
                notificationManager.notifyOffTask(classification: classification)
            case .accountable:
                notificationManager.notifyOffTask(classification: classification, urgent: true)
            }
        }
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

class URLTracker: ObservableObject {
    var classificationHandler: ((URLClassification) -> Void)?
    
    func startTracking() async {}
    func stopTracking() async {}
    func setStrictnessLevel(_ level: StrictnessLevel) {}
    func getClassifications() -> [URLClassification] { return [] }
}

class NotificationManager: ObservableObject {
    func scheduleSessionNotification(title: String, body: String) {}
    func notifyOffTask(classification: URLClassification, urgent: Bool = false) {}
}
