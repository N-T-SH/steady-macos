import Foundation

struct Intention: Codable, Identifiable, Equatable {
    let id: UUID
    let task: String
    let whyItMatters: String
    let plannedDuration: Int
    let scheduledDate: Date
    let strictness: StrictnessLevel
    let temptationBundle: String?
    var status: IntentionStatus
}

enum StrictnessLevel: String, Codable, CaseIterable {
    case quiet, gentle, focused, accountable
}

enum IntentionStatus: String, Codable {
    case planned, active, completed, skipped
}
