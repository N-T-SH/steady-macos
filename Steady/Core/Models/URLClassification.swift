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

    var displayName: String {
        switch self {
        case .coding:        return "Coding"
        case .design:        return "Design"
        case .research:      return "Research"
        case .communication: return "Comms"
        case .socialMedia:   return "Social"
        case .news:          return "News"
        case .entertainment: return "Entertainment"
        case .otherWork:     return "Other work"
        case .unknown:       return ""
        }
    }

    /// True for work/learning categories, false for leisure.
    var isProductive: Bool {
        switch self {
        case .coding, .design, .research, .communication, .otherWork: return true
        case .socialMedia, .news, .entertainment, .unknown:            return false
        }
    }
}
