import Foundation

/// JSON-backed persistence for Intention, Session, and URLRule data.
/// All methods run on the MainActor so callers never need to hop.
@MainActor
class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published var intentions: [Intention] = []
    @Published var sessions: [Session] = []
    @Published var urlRules: [URLRule] = []
    @Published var todos: [TodoItem] = []

    private let intentionsURL: URL
    private let sessionsURL: URL
    private let urlRulesURL: URL
    private let todosURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Steady", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        intentionsURL = dir.appendingPathComponent("intentions.json")
        sessionsURL   = dir.appendingPathComponent("sessions.json")
        urlRulesURL   = dir.appendingPathComponent("url_rules.json")
        todosURL      = dir.appendingPathComponent("todos.json")
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
        if let data = try? Data(contentsOf: todosURL) {
            todos = (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
