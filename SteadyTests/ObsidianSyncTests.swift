import Foundation
import Testing
@testable import Steady

@Suite("Obsidian Sync Tests")
struct ObsidianSyncTests {
    
    // MARK: - Helpers
    
    private func createTemporaryVault() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let vaultPath = tempDir.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: vaultPath, withIntermediateDirectories: true)
        return vaultPath
    }
    
    private func createSampleSession() -> Session {
        Session(
            id: UUID(),
            intentionId: UUID(),
            startTime: Date(),
            endTime: Date(),
            interruptions: [
                DistractionLog(
                    timestamp: Date(),
                    url: "https://slack.com",
                    category: "Slack",
                    duration: 120,
                    acknowledged: true
                )
            ],
            preSessionEnergy: 7,
            postSessionReflection: "Got stuck on API issue but pushed through.",
            urlClassifications: []
        )
    }
    
    private func createSampleIntention() -> Intention {
        Intention(
            id: UUID(),
            task: "GeoShack",
            whyItMatters: "Important for client",
            plannedDuration: 90,
            scheduledDate: Date(),
            strictness: .focused,
            temptationBundle: nil,
            status: .completed
        )
    }
    
    private func createSampleStats() -> CurrentStateStats {
        CurrentStateStats(
            lastCheckin: Date(),
            currentStreak: 5,
            longestStreak: 12,
            totalCheckins: 42,
            thisMonthCheckins: 15,
            habitStreaks: [
                "Morning Routine": 5,
                "Deep Work": 3
            ],
            currentBlockers: [
                "API documentation unclear"
            ],
            energyLevel: 7
        )
    }
    
    // MARK: - Tests
    
    @Test("Check-in log entry format")
    func testCheckinLogEntryFormat() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        let session = createSampleSession()
        let intention = createSampleIntention()
        
        try await sync.appendCheckin(session: session, intention: intention)
        
        let content = try await sync.readCheckinLog()
        
        // Verify structure
        #expect(content.contains("###"), "Should have timestamp header")
        #expect(content.contains("**Session:** GeoShack (90 min)"), "Should include session info")
        #expect(content.contains("**Energy before:** 7/10"), "Should include energy level")
        #expect(content.contains("**Completed:** Yes"), "Should show completion status")
        #expect(content.contains("**Reflection:** \"Got stuck on API issue but pushed through.\""), "Should include reflection")
        #expect(content.contains("**Distractions:**"), "Should include distractions")
        #expect(content.contains("---"), "Should have separator")
    }
    
    @Test("Reflection journal format")
    func testReflectionJournalFormat() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        
        try await sync.appendReflection(
            question: "What's making GeoShack hard right now?",
            answer: "The API integration feels overwhelming.",
            insight: "Break it into smaller pieces.",
            source: "Pre-session check-in"
        )
        
        let content = try await sync.readReflectionJournal()
        
        // Verify structure
        #expect(content.contains("###"), "Should have date header")
        #expect(content.contains("**Q:** What's making GeoShack hard right now?"), "Should include question")
        #expect(content.contains("**A:** The API integration feels overwhelming."), "Should include answer")
        #expect(content.contains("**Insight:** Break it into smaller pieces."), "Should include insight")
        #expect(content.contains("**Source:** Pre-session check-in"), "Should include source")
        #expect(content.contains("---"), "Should have separator")
    }
    
    @Test("Current state update")
    func testCurrentStateUpdate() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        let stats = createSampleStats()
        
        try await sync.updateCurrentState(stats: stats)
        
        let content = try await sync.readCurrentState()
        
        // Verify structure
        #expect(content.contains("# Current State"), "Should have main heading")
        #expect(content.contains("*Last updated:"), "Should have update timestamp")
        #expect(content.contains("## Stats"), "Should have stats section")
        #expect(content.contains("- Last check-in:"), "Should include last check-in")
        #expect(content.contains("- Current streak: 5 days"), "Should include current streak")
        #expect(content.contains("- Longest streak: 12 days"), "Should include longest streak")
        #expect(content.contains("- Total check-ins: 42"), "Should include total check-ins")
        #expect(content.contains("- This month: 15"), "Should include monthly check-ins")
        #expect(content.contains("## Habit Streaks"), "Should have habit streaks section")
        #expect(content.contains("- Morning Routine: 5 days"), "Should include habit streak")
        #expect(content.contains("## Current Blockers"), "Should have blockers section")
        #expect(content.contains("## Energy"), "Should have energy section")
    }
    
    @Test("File appending")
    func testFileAppending() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        
        // Append first entry
        try await sync.appendReflection(
            question: "First question?",
            answer: "First answer.",
            insight: nil,
            source: "Test"
        )
        
        // Append second entry
        try await sync.appendReflection(
            question: "Second question?",
            answer: "Second answer.",
            insight: "Second insight.",
            source: "Test"
        )
        
        let content = try await sync.readReflectionJournal()
        
        // Verify both entries are present
        #expect(content.contains("First question?"), "Should contain first entry")
        #expect(content.contains("Second question?"), "Should contain second entry")
        
        // Verify order (first should come before second)
        let firstRange = content.range(of: "First question?")!
        let secondRange = content.range(of: "Second question?")!
        #expect(firstRange.lowerBound < secondRange.lowerBound, "First entry should come before second")
    }
    
    @Test("Directory creation")
    func testDirectoryCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let vaultPath = tempDir.appendingPathComponent(UUID().uuidString)
        
        // Ensure vault doesn't exist yet
        #expect(!FileManager.default.fileExists(atPath: vaultPath.path), "Vault should not exist initially")
        
        let sync = ObsidianSync(vaultPath: vaultPath)
        let stats = createSampleStats()
        
        // This should create the directory
        try await sync.updateCurrentState(stats: stats)
        
        // Verify directory was created
        let habitTrackingPath = vaultPath.appendingPathComponent("6. Habit Tracking")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: habitTrackingPath.path, isDirectory: &isDirectory)
        
        #expect(exists, "Directory should exist")
        #expect(isDirectory.boolValue, "Path should be a directory")
        
        // Cleanup
        try? FileManager.default.removeItem(at: vaultPath)
    }
    
    @Test("Next session follow-up formatting")
    func testNextSessionFormatting() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        
        // First follow-up creates header
        try await sync.appendNextSession(followUp: "Research API authentication")
        
        let content1 = try await sync.readNextSession()
        #expect(content1.contains("# Next Session"), "Should have header on first entry")
        #expect(content1.contains("## Follow-ups"), "Should have follow-ups section")
        #expect(content1.contains("- [ ] Research API authentication"), "Should include checkbox item")
        
        // Second follow-up appends
        try await sync.appendNextSession(followUp: "Update documentation")
        
        let content2 = try await sync.readNextSession()
        #expect(content2.contains("- [ ] Research API authentication"), "Should include first item")
        #expect(content2.contains("- [ ] Update documentation"), "Should include second item")
    }
    
    @Test("Conversation summary formatting")
    func testConversationSummaryFormat() async throws {
        let vaultPath = createTemporaryVault()
        let sync = ObsidianSync(vaultPath: vaultPath)
        let intention = createSampleIntention()
        
        try await sync.writeConversationSummary(
            summary: "Discussed challenges with API integration and identified next steps.",
            intention: intention
        )
        
        let content = try await sync.readReflectionJournal()
        
        #expect(content.contains("###"), "Should have date header")
        #expect(content.contains("**Session:** GeoShack"), "Should include session name")
        #expect(content.contains("**Summary:** Discussed challenges"), "Should include summary")
        #expect(content.contains("---"), "Should have separator")
    }
}
