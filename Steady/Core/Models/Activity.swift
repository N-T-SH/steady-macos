import Foundation

/// A unified activity type that replaces the old `ProjectCategory` + `urlCategoryOverrides` system.
/// Default activities (isDefault == true) correspond to built-in `URLCategory` values and can be
/// renamed or deleted. Deleted default activities fall back to the URLCategory's hardcoded status.
/// Custom activities are user-defined with `urlCategoryRaw == nil`.
struct Activity: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var status: TaskStatus
    /// For built-in activities: the corresponding `URLCategory` rawValue. nil for custom activities.
    var urlCategoryRaw: String?

    var isDefault: Bool { urlCategoryRaw != nil }

    init(id: UUID = UUID(), name: String, status: TaskStatus, urlCategoryRaw: String? = nil) {
        self.id             = id
        self.name           = name
        self.status         = status
        self.urlCategoryRaw = urlCategoryRaw
    }
}

/// An explicit user-managed project or quest.
/// Projects are auto-discovered from LLM activity classifications and can be tagged
/// in todos and chat messages with the #project-name syntax.
struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Optional activity name this project is associated with.
    /// When set, the project's status colour is derived from that activity.
    var activityName: String?

    init(id: UUID = UUID(), name: String, activityName: String? = nil) {
        self.id           = id
        self.name         = name
        self.activityName = activityName
    }
}
