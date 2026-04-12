import Foundation

/// JSON-backed persistence for all Steady app data.
/// All methods run on the MainActor so callers never need to hop.
@MainActor
class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published var intentions: [Intention] = []
    @Published var sessions: [Session] = []
    @Published var urlRules: [URLRule] = []
    @Published var todos: [TodoItem] = []
    /// Unified activity types (default + custom). Replaces projectCategories + urlCategoryOverrides.
    @Published var activities: [Activity] = []
    /// Explicitly managed projects. Auto-populated from LLM detections and #tags.
    @Published var projects: [Project] = []

    private let intentionsURL: URL
    private let sessionsURL: URL
    private let urlRulesURL: URL
    private let todosURL: URL
    private let activitiesURL: URL
    private let projectsURL: URL

    // Legacy URLs — read during migration only, never written
    private let legacyProjectCategoriesURL: URL
    private let legacyProjectAssignmentsURL: URL
    private let legacyURLCategoryOverridesURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Steady", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        intentionsURL    = dir.appendingPathComponent("intentions.json")
        sessionsURL      = dir.appendingPathComponent("sessions.json")
        urlRulesURL      = dir.appendingPathComponent("url_rules.json")
        todosURL         = dir.appendingPathComponent("todos.json")
        activitiesURL    = dir.appendingPathComponent("activities.json")
        projectsURL      = dir.appendingPathComponent("projects.json")
        legacyProjectCategoriesURL    = dir.appendingPathComponent("project_categories.json")
        legacyProjectAssignmentsURL   = dir.appendingPathComponent("project_assignments.json")
        legacyURLCategoryOverridesURL = dir.appendingPathComponent("url_category_overrides.json")
        load()
    }

    // MARK: - Lookup

    func intention(for id: UUID) -> Intention? {
        intentions.first { $0.id == id }
    }

    func rule(for domain: String) -> URLRule? {
        urlRules.first { $0.domain == domain }
    }

    // MARK: - Intentions

    func save(intention: Intention) {
        if let idx = intentions.firstIndex(where: { $0.id == intention.id }) {
            intentions[idx] = intention
        } else {
            intentions.append(intention)
        }
        persist(intentions, to: intentionsURL)
    }

    func deleteIntention(_ id: UUID) {
        intentions.removeAll { $0.id == id }
        persist(intentions, to: intentionsURL)
    }

    // MARK: - Sessions

    func save(session: Session) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persist(sessions, to: sessionsURL)
    }

    // MARK: - URL Rules

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

    func deleteURLRule(_ id: UUID) {
        urlRules.removeAll { $0.id == id }
        persist(urlRules, to: urlRulesURL)
    }

    // MARK: - Todos

    func save(todo: TodoItem) {
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[idx] = todo
        } else {
            todos.append(todo)
        }
        persist(todos, to: todosURL)
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        persist(todos, to: todosURL)
    }

    func reorderTodos(from source: IndexSet, to destination: Int) {
        todos.move(fromOffsets: source, toOffset: destination)
        for i in todos.indices { todos[i].order = i }
        persist(todos, to: todosURL)
    }

    // MARK: - Activities

    func save(activity: Activity) {
        if let idx = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[idx] = activity
        } else {
            activities.append(activity)
        }
        persist(activities, to: activitiesURL)
    }

    func deleteActivity(id: UUID) {
        activities.removeAll { $0.id == id }
        // Orphan any projects that pointed to the deleted activity by name
        let activityNames = Set(activities.map { $0.name })
        for i in projects.indices {
            if let name = projects[i].activityName, !activityNames.contains(name) {
                projects[i].activityName = nil
            }
        }
        persist(activities, to: activitiesURL)
        persist(projects, to: projectsURL)
    }

    // MARK: - Projects

    func save(project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
        persist(projects, to: projectsURL)
    }

    func deleteProject(id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        let name = project.name
        projects.removeAll { $0.id == id }
        urlRules.removeAll { $0.projectName == name }
        intentions.removeAll { $0.task == name }
        persist(projects, to: projectsURL)
        persist(urlRules, to: urlRulesURL)
        persist(intentions, to: intentionsURL)
    }

    /// Adds a project if no project with that name already exists (case-insensitive).
    @discardableResult
    func addProjectIfNeeded(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = projects.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let project = Project(name: trimmed)
        projects.append(project)
        persist(projects, to: projectsURL)
        return project
    }

    // MARK: - Status Resolution

    /// Effective TaskStatus for a URLCategory, applying any activity override.
    func effectiveStatus(for urlCategory: URLCategory) -> TaskStatus {
        if let activity = activities.first(where: { $0.urlCategoryRaw == urlCategory.rawValue }) {
            return activity.status
        }
        return urlCategory.defaultTaskStatus
    }

    /// Effective TaskStatus for a project via its associated activity. Returns nil when unassigned.
    func taskStatus(forProject project: String) -> TaskStatus? {
        guard let p = projects.first(where: { $0.name == project }),
              let actName = p.activityName,
              let activity = activities.first(where: { $0.name == actName }) else { return nil }
        return activity.status
    }

    /// Activity associated with a project, if any.
    func activity(forProject project: String) -> Activity? {
        guard let p = projects.first(where: { $0.name == project }),
              let actName = p.activityName else { return nil }
        return activities.first(where: { $0.name == actName })
    }

    // MARK: - All Project Names

    /// Unique project names across explicit projects, URL rules, and intentions.
    var allProjectNames: [String] {
        let explicit   = projects.map { $0.name }
        let fromRules  = urlRules.map { $0.projectName }
        let fromIntent = intentions.map { $0.task }
        return Array(Set(explicit + fromRules + fromIntent)).filter { !$0.isEmpty }.sorted()
    }

    func renameProject(from oldName: String, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty, oldName != newName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        // Update explicit projects list
        if let idx = projects.firstIndex(where: { $0.name == oldName }) {
            projects[idx].name = trimmed
        }
        persist(projects, to: projectsURL)
        // Update URL rules
        for i in urlRules.indices where urlRules[i].projectName == oldName {
            urlRules[i].projectName = trimmed
            urlRules[i].updatedAt = Date()
        }
        persist(urlRules, to: urlRulesURL)
        // Update intentions
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

    // MARK: - Private Load & Migration

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
        if let data = try? Data(contentsOf: todosURL) {
            todos = (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: activitiesURL) {
            activities = (try? JSONDecoder().decode([Activity].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: projectsURL) {
            projects = (try? JSONDecoder().decode([Project].self, from: data)) ?? []
        }
        migrateIfNeeded()
    }

    private func migrateIfNeeded() {
        if activities.isEmpty { migrateActivities() }
        if projects.isEmpty   { migrateProjects()   }
    }

    private func migrateActivities() {
        // Load legacy data
        var legacyCategories: [LegacyProjectCategory] = []
        var legacyOverrides: [String: TaskStatus] = [:]
        if let data = try? Data(contentsOf: legacyProjectCategoriesURL) {
            legacyCategories = (try? JSONDecoder().decode([LegacyProjectCategory].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: legacyURLCategoryOverridesURL) {
            legacyOverrides = (try? JSONDecoder().decode([String: TaskStatus].self, from: data)) ?? [:]
        }

        // Seed default activities from URLCategory, applying any legacy status overrides
        var seeded: [Activity] = URLCategory.allCases.filter { $0 != .unknown }.map { cat in
            let status = legacyOverrides[cat.rawValue] ?? cat.defaultTaskStatus
            return Activity(name: cat.displayName, status: status, urlCategoryRaw: cat.rawValue)
        }
        // Migrate custom categories as custom activities
        for cat in legacyCategories where !seeded.contains(where: { $0.name == cat.name }) {
            seeded.append(Activity(name: cat.name, status: cat.status))
        }

        activities = seeded
        persist(activities, to: activitiesURL)
    }

    private func migrateProjects() {
        var legacyAssignments: [String: String] = [:]
        var legacyCategories: [LegacyProjectCategory] = []
        if let data = try? Data(contentsOf: legacyProjectAssignmentsURL) {
            legacyAssignments = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        if let data = try? Data(contentsOf: legacyProjectCategoriesURL) {
            legacyCategories = (try? JSONDecoder().decode([LegacyProjectCategory].self, from: data)) ?? []
        }
        guard !legacyAssignments.isEmpty else { return }

        for (projectName, catName) in legacyAssignments {
            var activityName: String? = nil
            if legacyCategories.first(where: { $0.name == catName }) != nil {
                // Custom category migrates to activity with same name
                activityName = catName
            } else if let urlCat = URLCategory(rawValue: catName) {
                // URLCategory maps to the default activity for that category
                activityName = activities.first(where: { $0.urlCategoryRaw == urlCat.rawValue })?.name
            }
            if !projects.contains(where: { $0.name == projectName }) {
                projects.append(Project(name: projectName, activityName: activityName))
            }
        }
        if !projects.isEmpty { persist(projects, to: projectsURL) }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

// MARK: - Legacy types for migration only

private struct LegacyProjectCategory: Codable {
    let id: UUID
    var name: String
    var status: TaskStatus
}
