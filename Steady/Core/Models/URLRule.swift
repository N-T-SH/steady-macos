import Foundation

/// A persisted rule linking a domain to a known project and category.
/// Created automatically when the LLM classifies a new domain,
/// and can be manually edited in the Classification Manager.
struct URLRule: Codable, Identifiable, Equatable {
    let id: UUID
    let domain: String         // e.g. "github.com"
    var projectName: String    // e.g. "Steady macOS"
    var category: URLCategory
    let createdAt: Date
    var updatedAt: Date

    init(domain: String, projectName: String, category: URLCategory) {
        self.id = UUID()
        self.domain = domain
        self.projectName = projectName
        self.category = category
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
