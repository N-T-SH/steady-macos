import Foundation

struct Session: Codable, Identifiable, Equatable {
    let id: UUID
    let intentionId: UUID
    let startTime: Date
    var endTime: Date?
    var interruptions: [DistractionLog]
    let preSessionEnergy: Int
    var postSessionReflection: String?
    var urlClassifications: [URLClassification]
}

struct DistractionLog: Codable, Equatable {
    let timestamp: Date
    let url: String?
    let category: String
    let duration: TimeInterval
    var acknowledged: Bool
}
