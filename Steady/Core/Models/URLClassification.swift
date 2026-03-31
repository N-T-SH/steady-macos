import Foundation

struct URLClassification: Codable, Equatable {
    let url: String
    let pageTitle: String
    let onTask: Bool
    let project: String?
    let category: URLCategory
    let confidence: Double
    let reasoning: String
    let timestamp: Date
}

enum URLCategory: String, Codable, CaseIterable {
    case coding, design, research, communication
    case socialMedia = "social_media"
    case news, entertainment, otherWork = "other_work", unknown
}
