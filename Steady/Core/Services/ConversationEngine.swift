import Foundation

enum ConversationTrigger {
    case urlDrift(URLClassification, TimeInterval)
    case scheduledNudge(Intention)
    case manualRequest
    case sessionComplete(Session)
}

actor ConversationEngine {
    private let llmProvider: LLMProvider
    private var messages: [ConversationTurn] = []
    private let maxHistoryLength: Int
    
    init(llmProvider: LLMProvider, maxHistoryLength: Int = 20) {
        self.llmProvider = llmProvider
        self.maxHistoryLength = maxHistoryLength
    }
    
    func startConversation(
        intention: Intention,
        session: Session,
        trigger: ConversationTrigger
    ) async -> [ConversationTurn] {
        messages = []
        
        let systemPrompt = buildSystemPrompt(intention: intention, session: session, trigger: trigger)
        let systemTurn = ConversationTurn(
            timestamp: Date(),
            role: .system,
            content: systemPrompt,
            context: ConversationContext(intention: intention, session: session, driftDuration: nil, classification: nil)
        )
        messages.append(systemTurn)
        
        let greeting = await generateOpeningMessage(trigger: trigger, intention: intention, session: session)
        let assistantTurn = ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: greeting,
            context: ConversationContext(intention: intention, session: session, driftDuration: nil, classification: nil)
        )
        messages.append(assistantTurn)
        
        return messages
    }
    
    func continueConversation(userMessage: String, context: ConversationContext) async -> String {
        let userTurn = ConversationTurn(
            timestamp: Date(),
            role: .user,
            content: userMessage,
            context: context
        )
        messages.append(userTurn)

        if messages.count > maxHistoryLength {
            messages.removeFirst(messages.count - maxHistoryLength)
        }

        do {
            let response = try await llmProvider.generateConversationResponse(messages: messages, context: context)
            
            let assistantTurn = ConversationTurn(
                timestamp: Date(),
                role: .assistant,
                content: response,
                context: context
            )
            messages.append(assistantTurn)
            
            return response
        } catch {
            return "I'm having trouble connecting right now. Please try again in a moment."
        }
    }
    
    func summarizeForJournal() -> String {
        guard messages.count > 1 else { return "" }
        
        let relevantMessages = messages.filter { $0.role != .system }
        guard !relevantMessages.isEmpty else { return "" }
        
        var summary = "Conversation Summary:\n\n"
        for message in relevantMessages {
            let prefix = message.role == .user ? "You: " : "Steady: "
            summary += "\(prefix)\(message.content)\n\n"
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func getConversationHistory() -> [ConversationTurn] {
        return messages
    }
    
    func clearConversation() {
        messages = []
    }

    /// Tries to extract a clear work task from the conversation so far.
    /// Returns nil if the conversation is still too ambiguous.
    func extractIntentFromConversation(_ turns: [ConversationTurn]) async -> String? {
        let relevant = turns.filter { $0.role != .system }
        guard !relevant.isEmpty else { return nil }
        let text = relevant.map { ($0.role == .user ? "User" : "Steady") + ": " + $0.content }.joined(separator: "\n")
        return try? await llmProvider.extractIntent(from: text)
    }
    
    private func buildSystemPrompt(
        intention: Intention,
        session: Session,
        trigger: ConversationTrigger
    ) -> String {
        var prompt = "You are Steady, a supportive mindfulness companion for focused work. "
        
        prompt += "Current Intention: \(intention.task). Why: \(intention.whyItMatters). "
        prompt += "Strictness Level: \(intention.strictness.rawValue). "
        
        let sessionDuration = session.endTime?.timeIntervalSince(session.startTime) ?? Date().timeIntervalSince(session.startTime)
        let minutes = Int(sessionDuration / 60)
        prompt += "Session running for \(minutes) minutes. "
        
        switch trigger {
        case .urlDrift(let classification, let driftDuration):
            let driftMinutes = Int(driftDuration / 60)
            prompt += "TRIGGER: URL Drift detected. User spent \(driftMinutes) min on \(classification.pageTitle) (\(classification.category.rawValue)). "
            prompt += "On-task: \(classification.onTask ? "Yes" : "No"). "
            if !classification.onTask {
                prompt += "Gently guide them back to their intention. "
            }
        case .scheduledNudge(let int):
            prompt += "TRIGGER: Scheduled check-in. Intention: \(int.task). "
            prompt += "Ask how the session is going and offer support. "
        case .manualRequest:
            prompt += "TRIGGER: User initiated. Respond helpfully to their request. "
        case .sessionComplete(let completedSession):
            prompt += "TRIGGER: Session complete. Duration: \(Int((completedSession.endTime?.timeIntervalSince(completedSession.startTime) ?? 0) / 60)) min. "
            prompt += "Celebrate their progress and invite reflection. "
        }
        
        prompt += "Be warm, brief (1-2 sentences max for nudges, conversational for manual), and personalize to their context."
        
        return prompt
    }
    
    private func generateOpeningMessage(trigger: ConversationTrigger, intention: Intention, session: Session) async -> String {
        switch trigger {
        case .urlDrift(let classification, let driftDuration):
            let driftMinutes = Int(driftDuration / 60)
            if classification.onTask {
                return "I see you're working on \(classification.pageTitle). How's the focus going?"
            } else {
                return "You've been on \(classification.pageTitle) for \(driftMinutes) min. Want to get back to \(intention.task)?"
            }
        case .scheduledNudge:
            return "How's your session going with \(intention.task)?"
        case .manualRequest:
            return "Hi there! I'm here to help with \(intention.task). What do you need?"
        case .sessionComplete:
            return "Great work on \(intention.task)! How did it go?"
        }
    }
}
