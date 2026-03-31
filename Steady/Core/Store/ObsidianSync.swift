import Foundation

actor ObsidianSync {
    private let vaultPath: URL
    private let fileManager: FileManager
    
    init(vaultPath: URL) {
        self.vaultPath = vaultPath
        self.fileManager = FileManager.default
    }
    
    // MARK: - File Paths
    
    private var habitTrackingPath: URL {
        vaultPath.appendingPathComponent("6. Habit Tracking")
    }
    
    private var checkinLogURL: URL {
        habitTrackingPath.appendingPathComponent("Check-in Log.md")
    }
    
    private var reflectionJournalURL: URL {
        habitTrackingPath.appendingPathComponent("Reflection Journal.md")
    }
    
    private var currentStateURL: URL {
        habitTrackingPath.appendingPathComponent("Current State.md")
    }
    
    private var nextSessionURL: URL {
        habitTrackingPath.appendingPathComponent("Next Session.md")
    }
    
    // MARK: - Directory Management
    
    private func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: habitTrackingPath.path, isDirectory: &isDirectory)
        
        if !exists {
            try fileManager.createDirectory(
                at: habitTrackingPath,
                withIntermediateDirectories: true
            )
        } else if !isDirectory.boolValue {
            throw ObsidianSyncError.pathIsNotDirectory
        }
    }
    
    // MARK: - Write Operations
    
    func appendCheckin(session: Session, intention: Intention) async throws {
        try await ensureDirectoryExists()
        
        let entry = MarkdownFormatter.formatCheckinEntry(
            session: session,
            intention: intention
        )
        
        let existingContent = try? String(contentsOf: checkinLogURL, encoding: .utf8)
        let newContent = (existingContent ?? "") + entry
        
        try newContent.write(to: checkinLogURL, atomically: true, encoding: .utf8)
    }
    
    func appendReflection(
        question: String,
        answer: String,
        insight: String?,
        source: String
    ) async throws {
        try await ensureDirectoryExists()
        
        let entry = MarkdownFormatter.formatReflectionEntry(
            question: question,
            answer: answer,
            insight: insight,
            source: source
        )
        
        let existingContent = try? String(contentsOf: reflectionJournalURL, encoding: .utf8)
        let newContent = (existingContent ?? "") + entry
        
        try newContent.write(to: reflectionJournalURL, atomically: true, encoding: .utf8)
    }
    
    func updateCurrentState(stats: CurrentStateStats) async throws {
        try await ensureDirectoryExists()
        
        let content = MarkdownFormatter.formatCurrentState(stats: stats)
        try content.write(to: currentStateURL, atomically: true, encoding: .utf8)
    }
    
    func appendNextSession(followUp: String) async throws {
        try await ensureDirectoryExists()
        
        let entry = MarkdownFormatter.formatNextSessionEntry(followUp: followUp)
        
        let existingContent = try? String(contentsOf: nextSessionURL, encoding: .utf8)
        let newContent: String
        
        if let existing = existingContent, !existing.isEmpty {
            newContent = existing + "\n" + entry
        } else {
            newContent = "# Next Session\n\n## Follow-ups\n\n" + entry
        }
        
        try newContent.write(to: nextSessionURL, atomically: true, encoding: .utf8)
    }
    
    func writeConversationSummary(
        summary: String,
        intention: Intention
    ) async throws {
        try await ensureDirectoryExists()
        
        let entry = MarkdownFormatter.formatConversationSummary(
            summary: summary,
            intention: intention
        )
        
        let existingContent = try? String(contentsOf: reflectionJournalURL, encoding: .utf8)
        let newContent = (existingContent ?? "") + entry
        
        try newContent.write(to: reflectionJournalURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Read Operations (for testing)
    
    func readCheckinLog() async throws -> String {
        return try String(contentsOf: checkinLogURL, encoding: .utf8)
    }
    
    func readReflectionJournal() async throws -> String {
        return try String(contentsOf: reflectionJournalURL, encoding: .utf8)
    }
    
    func readCurrentState() async throws -> String {
        return try String(contentsOf: currentStateURL, encoding: .utf8)
    }
    
    func readNextSession() async throws -> String {
        return try String(contentsOf: nextSessionURL, encoding: .utf8)
    }
}

// MARK: - Errors

enum ObsidianSyncError: Error {
    case pathIsNotDirectory
    case fileNotFound
    case encodingError
}

// MARK: - Supporting Types

struct CurrentStateStats {
    let lastCheckin: Date
    let currentStreak: Int
    let longestStreak: Int
    let totalCheckins: Int
    let thisMonthCheckins: Int
    let habitStreaks: [String: Int]
    let currentBlockers: [String]
    let energyLevel: Int?
}
