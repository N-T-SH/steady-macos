import SwiftUI
import Combine

// MARK: - App State

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
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to panel visibility changes
        $isPanelVisible
            .dropFirst()
            .sink { [weak self] isVisible in
                self?.handlePanelVisibilityChange(isVisible)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Management
    
    func startSession(intention: Intention) {
        currentIntention = intention
        activeSession = Session(
            id: UUID(),
            intentionId: intention.id,
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 5,
            postSessionReflection: nil,
            urlClassifications: []
        )
        
        // Add system message about session start
        let systemMessage = ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: "Starting session: \(intention.task)",
            context: ConversationContext(
                intention: intention,
                session: activeSession,
                driftDuration: nil,
                classification: nil
            )
        )
        addConversationTurn(systemMessage)
    }
    
    func endSession(reflection: String?) {
        guard var session = activeSession else { return }
        
        session.endTime = Date()
        session.postSessionReflection = reflection
        sessionHistory.append(session)
        
        // Add system message about session end
        let duration = session.duration
        let formattedDuration = formatDuration(duration)
        let message = reflection != nil 
            ? "Session completed in \(formattedDuration). Reflection recorded."
            : "Session completed in \(formattedDuration)."
        
        let systemMessage = ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: message,
            context: ConversationContext(
                intention: session.intention,
                session: nil,
                driftDuration: nil,
                classification: nil
            )
        )
        addConversationTurn(systemMessage)
        
        activeSession = nil
        currentIntention = nil
    }
    
    // MARK: - Distraction Logging
    
    func logDistraction(url: String?, category: String) {
        guard var session = activeSession else { return }
        
        let log = DistractionLog(
            timestamp: Date(),
            url: url,
            category: category,
            duration: 0,
            acknowledged: false
        )
        
        session.interruptions.append(log)
        distractionCount += 1
        activeSession = session
        
        // Notify about distraction
        let message = "Detected \(category) distraction"
        
        let systemMessage = ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: message,
            context: ConversationContext(
                intention: session.intention,
                session: session,
                driftDuration: nil,
                classification: nil
            )
        )
        addConversationTurn(systemMessage)
    }
    
    // MARK: - Conversation Management
    
    func addConversationTurn(_ turn: ConversationTurn) {
        conversations.append(turn)
        
        // Limit conversation history to last 100 messages
        if conversations.count > 100 {
            conversations.removeFirst(conversations.count - 100)
        }
    }
    
    func sendUserMessage(_ content: String) {
        let turn = ConversationTurn(
            timestamp: Date(),
            role: .user,
            content: content,
            context: ConversationContext(
                intention: currentIntention,
                session: activeSession,
                driftDuration: nil,
                classification: nil
            )
        )
        addConversationTurn(turn)
    }
    
    func clearConversations() {
        conversations.removeAll()
    }
    
    // MARK: - Panel Visibility
    
    func togglePanel() {
        isPanelVisible.toggle()
    }
    
    func showPanel() {
        isPanelVisible = true
    }
    
    func hidePanel() {
        isPanelVisible = false
    }
    
    private func handlePanelVisibilityChange(_ isVisible: Bool) {
        isMenuBarIconActive = isVisible
        NotificationCenter.default.post(
            name: .panelVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": isVisible]
        )
    }
    
    // MARK: - Utility
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - URL Classification
    
    func recordClassification(_ classification: URLClassification) {
        lastClassification = classification
        
        if !classification.onTask {
            logDistraction(url: classification.url, category: classification.category.rawValue)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let panelVisibilityChanged = Notification.Name("PanelVisibilityChanged")
}

// MARK: - Session Extension

extension Session {
    var intention: Intention? {
        // This would need to be fetched from a store in real implementation
        return nil
    }
    
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
}
