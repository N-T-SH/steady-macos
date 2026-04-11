import Foundation

/// A user-defined category that maps to one of the three task statuses.
/// Projects are assigned to categories; categories determine the colour
/// shown throughout the app (green / yellow / red).
struct ProjectCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var status: TaskStatus

    init(name: String, status: TaskStatus) {
        self.id     = UUID()
        self.name   = name
        self.status = status
    }
}
