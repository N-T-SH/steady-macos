import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    var isStashed: Bool
    var order: Int
    let createdAt: Date
    var completedAt: Date?
    var stashedAt: Date?
    /// Project name extracted from a #project-name tag in the todo text.
    var projectName: String?

    init(id: UUID = UUID(), text: String, order: Int = 0, projectName: String? = nil) {
        self.id          = id
        self.text        = text
        self.isCompleted = false
        self.isStashed   = false
        self.order       = order
        self.createdAt   = Date()
        self.completedAt = nil
        self.stashedAt   = nil
        self.projectName = projectName
    }

    mutating func complete() {
        isCompleted = true
        completedAt = Date()
    }

    mutating func uncomplete() {
        isCompleted = false
        completedAt = nil
    }

    mutating func stash() {
        isStashed = true
        stashedAt = Date()
    }
}
