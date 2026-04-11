import Foundation

// MARK: - Task Status (3-level colour system)

enum TaskStatus: String, Codable, CaseIterable {
    case onTask     = "on_task"
    case drift      = "drift"
    case goofingOff = "goofing_off"

    var displayName: String {
        switch self {
        case .onTask:     return "On-Task"
        case .drift:      return "Drift"
        case .goofingOff: return "Goofing Off"
        }
    }

    /// Colour name compatible with InfographicSpec colour strings.
    var colorName: String {
        switch self {
        case .onTask:     return "green"
        case .drift:      return "yellow"
        case .goofingOff: return "red"
        }
    }
}

// MARK: - URL Classification

struct URLClassification: Codable, Equatable {
    let url: String
    let pageTitle: String
    let taskStatus: TaskStatus
    let project: String?
    let category: URLCategory
    let confidence: Double
    let reasoning: String
    let timestamp: Date

    /// Convenience: true only for fully on-task classifications.
    var onTask: Bool { taskStatus == .onTask }

    init(url: String, pageTitle: String, taskStatus: TaskStatus,
         project: String?, category: URLCategory,
         confidence: Double, reasoning: String, timestamp: Date) {
        self.url        = url
        self.pageTitle  = pageTitle
        self.taskStatus = taskStatus
        self.project    = project
        self.category   = category
        self.confidence = confidence
        self.reasoning  = reasoning
        self.timestamp  = timestamp
    }

    // MARK: Codable – handles legacy JSON that stored onTask: Bool instead of taskStatus

    private enum CodingKeys: String, CodingKey {
        case url, pageTitle, taskStatus, project, category, confidence, reasoning, timestamp
        case onTask   // legacy field
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url,        forKey: .url)
        try c.encode(pageTitle,  forKey: .pageTitle)
        try c.encode(taskStatus, forKey: .taskStatus)
        try c.encodeIfPresent(project,   forKey: .project)
        try c.encode(category,   forKey: .category)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(reasoning,  forKey: .reasoning)
        try c.encode(timestamp,  forKey: .timestamp)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url        = try c.decode(String.self, forKey: .url)
        pageTitle  = try c.decode(String.self, forKey: .pageTitle)
        project    = try c.decodeIfPresent(String.self,      forKey: .project)
        category   = try c.decodeIfPresent(URLCategory.self, forKey: .category) ?? .unknown
        confidence = try c.decodeIfPresent(Double.self,      forKey: .confidence) ?? 1.0
        reasoning  = try c.decodeIfPresent(String.self,      forKey: .reasoning) ?? ""
        timestamp  = try c.decode(Date.self, forKey: .timestamp)

        if let status = try c.decodeIfPresent(TaskStatus.self, forKey: .taskStatus) {
            taskStatus = status
        } else {
            // Migrate from old onTask: Bool field
            let legacyOnTask = try c.decodeIfPresent(Bool.self, forKey: .onTask) ?? true
            taskStatus = legacyOnTask ? .onTask : category.defaultTaskStatus
        }
    }
}

// MARK: - URL Category (used by LLM for activity type classification)

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

    /// Default task status when no project-level category is assigned.
    var defaultTaskStatus: TaskStatus {
        switch self {
        case .coding, .design, .research, .communication, .otherWork: return .onTask
        case .news:                                                    return .drift
        case .socialMedia, .entertainment, .unknown:                   return .goofingOff
        }
    }

    var isProductive: Bool { defaultTaskStatus == .onTask }
}
