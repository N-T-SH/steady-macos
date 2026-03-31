import Foundation

struct ConversationTurn: Codable, Equatable {
    let timestamp: Date
    let role: MessageRole
    let content: String
    let context: ConversationContext?
}

enum MessageRole: String, Codable {
    case system, user, assistant
}

struct ConversationContext: Codable, Equatable {
    let intention: Intention?
    let session: Session?
    let driftDuration: TimeInterval?
    let classification: URLClassification?
}
