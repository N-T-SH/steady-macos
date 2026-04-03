import Foundation

struct ConversationTurn: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let role: MessageRole
    let content: String
    let context: ConversationContext?

    init(id: UUID = UUID(), timestamp: Date, role: MessageRole, content: String, context: ConversationContext?) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.context = context
    }
}

enum MessageRole: String, Codable {
    case system, user, assistant
}

struct ConversationContext: Codable, Equatable {
    let intention: Intention?
    let session: Session?
    let driftDuration: TimeInterval?
    let classification: URLClassification?
    /// Actual captured activity to show the LLM — never fabricate beyond this list.
    var recentActivity: [URLClassification]

    init(
        intention: Intention?,
        session: Session?,
        driftDuration: TimeInterval?,
        classification: URLClassification?,
        recentActivity: [URLClassification] = []
    ) {
        self.intention = intention
        self.session = session
        self.driftDuration = driftDuration
        self.classification = classification
        self.recentActivity = recentActivity
    }
}
