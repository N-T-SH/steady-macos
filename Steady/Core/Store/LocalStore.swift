import Foundation

/// JSON-backed persistence for Intention, Session, and URLRule data.
/// All methods run on the MainActor so callers never need to hop.
@MainActor
class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published var intentions: [Intention] = []
    @Published var sessions: [Session] = []
    @Published var urlRules: [URLRule] = []
    @Published var projectCategories: [ProjectCategory] = []
    /// Maps project name → category name.
    @Published var projectAssignments: [String: String] = [:]
    /// User overrides for auto-generated URLCategory statuses (rawValue → TaskStatus).
    @Published var urlCategoryOverrides: [String: TaskStatus] = [:]

    private let intentionsURL: URL
    private let sessionsURL: URL
    private let urlRulesURL: URL
    private let projectCategoriesURL: URL
    private let projectAssignmentsURL: URL
    private let urlCategoryOverridesURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Steady", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        intentionsURL           = dir.appendingPathComponent("intentions.json")
        sessionsURL             = dir.appendingPathComponent("sessions.json")
        urlRulesURL             = dir.appendingPathComponent("url_rules.json")
        projectCategoriesURL    = dir.appendingPathComponent("project_categories.json")
        projectAssignmentsURL   = dir.appendingPathComponent("project_assignments.json")
        urlCategoryOverridesURL = dir.appendingPathComponent("url_category_overrides.json")
        load()
    }

    // MARK: - Lookup

    func intention(for id: UUID) -> Intention? {
        intentions.first { $0.id == id }
    }

    func rule(for domain: String) -> URLRule? {
        urlRules.first { $0.domain == domain }
    }

    // MARK: - Write

    func save(intention: Intention) {
        if let idx = intentions.firstIndex(where: { $0.id == intention.id }) {
            intentions[idx] = intention
        } else {
            intentions.append(intention)
        }
        persist(intentions, to: intentionsURL)
    }

    func save(session: Session) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persist(sessions, to: sessionsURL)
    }

    func save(urlRule: URLRule) {
        if let idx = urlRules.firstIndex(where: { $0.id == urlRule.id }) {
            urlRules[idx] = urlRule
        } else {
            urlRules.append(urlRule)
        }
        persist(urlRules, to: urlRulesURL)
    }

    func saveURLRule(domain: String, projectName: String, category: URLCategory) {
        if let idx = urlRules.firstIndex(where: { $0.domain == domain }) {
            var updated = urlRules[idx]
            updated.projectName = projectName
            updated.category = category
            updated.updatedAt = Date()
            urlRules[idx] = updated
        } else {
            urlRules.append(URLRule(domain: domain, projectName: projectName, category: category))
        }
        persist(urlRules, to: urlRulesURL)
    }

    func deleteIntention(_ id: UUID) {
        intentions.removeAll { $0.id == id }
        persist(intentions, to: intentionsURL)
    }

    func deleteURLRule(_ id: UUID) {
        urlRules.removeAll { $0.id == id }
        persist(urlRules, to: urlRulesURL)
    }

    // MARK: - Project Categories

    func save(projectCategory: ProjectCategory) {
        if let idx = projectCategories.firstIndex(where: { $0.id == projectCategory.id }) {
            projectCategories[idx] = projectCategory
        } else {
            projectCategories.append(projectCategory)
        }
        persist(projectCategories, to: projectCategoriesURL)
    }

    func deleteProjectCategory(id: UUID) {
        guard let cat = projectCategories.first(where: { $0.id == id }) else { return }
        // Clear assignments pointing to this category
        for (project, catName) in projectAssignments where catName == cat.name {
            projectAssignments.removeValue(forKey: project)
        }
        projectCategories.removeAll { $0.id == id }
        persist(projectCategories, to: projectCategoriesURL)
        persist(projectAssignments, to: projectAssignmentsURL)
    }

    func assignCategory(toProject project: String, categoryName: String?) {
        if let name = categoryName {
            projectAssignments[project] = name
        } else {
            projectAssignments.removeValue(forKey: project)
        }
        persist(projectAssignments, to: projectAssignmentsURL)
    }

    /// Effective TaskStatus for a project, falling back to nil when unassigned.
    /// Resolution order: custom category name → URLCategory rawValue → nil.
    func taskStatus(forProject project: String) -> TaskStatus? {
        guard let catName = projectAssignments[project] else { return nil }
        if let cat = projectCategories.first(where: { $0.name == catName }) {
            return cat.status
        }
        if let urlCat = URLCategory(rawValue: catName) {
            return effectiveStatus(for: urlCat)
        }
        return nil
    }

    // MARK: - URL Category Overrides

    /// Override the default TaskStatus for an auto-generated URLCategory.
    func setURLCategoryOverride(_ category: URLCategory, status: TaskStatus) {
        urlCategoryOverrides[category.rawValue] = status
        persist(urlCategoryOverrides, to: urlCategoryOverridesURL)
    }

    /// Effective TaskStatus for a URLCategory, respecting any user override.
    func effectiveStatus(for urlCategory: URLCategory) -> TaskStatus {
        urlCategoryOverrides[urlCategory.rawValue] ?? urlCategory.defaultTaskStatus
    }

    /// All unique project names across intentions and URL rules.
    var allProjectNames: [String] {
        let fromIntentions = intentions.map { $0.task }
        let fromRules = urlRules.map { $0.projectName }
        return Array(Set(fromIntentions + fromRules)).filter { !$0.isEmpty }.sorted()
    }

    func renameProject(from oldName: String, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty, oldName != newName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        for i in urlRules.indices where urlRules[i].projectName == oldName {
            urlRules[i].projectName = trimmed
            urlRules[i].updatedAt = Date()
        }
        persist(urlRules, to: urlRulesURL)
        for i in intentions.indices where intentions[i].task == oldName {
            intentions[i] = Intention(
                id: intentions[i].id,
                task: trimmed,
                whyItMatters: intentions[i].whyItMatters,
                scheduledDate: intentions[i].scheduledDate,
                strictness: intentions[i].strictness,
                temptationBundle: intentions[i].temptationBundle,
                status: intentions[i].status
            )
        }
        persist(intentions, to: intentionsURL)
    }

    func deleteProject(_ name: String) {
        urlRules.removeAll { $0.projectName == name }
        persist(urlRules, to: urlRulesURL)
        intentions.removeAll { $0.task == name }
        persist(intentions, to: intentionsURL)
    }

    // MARK: - Private

    private func load() {
        if let data = try? Data(contentsOf: intentionsURL) {
            intentions = (try? JSONDecoder().decode([Intention].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: sessionsURL) {
            sessions = (try? JSONDecoder().decode([Session].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: urlRulesURL) {
            urlRules = (try? JSONDecoder().decode([URLRule].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: projectCategoriesURL) {
            projectCategories = (try? JSONDecoder().decode([ProjectCategory].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: projectAssignmentsURL) {
            projectAssignments = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        if let data = try? Data(contentsOf: urlCategoryOverridesURL) {
            urlCategoryOverrides = (try? JSONDecoder().decode([String: TaskStatus].self, from: data)) ?? [:]
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
