import XCTest
@testable import Steady

@MainActor
final class SessionManagerTests: XCTestCase {
    
    var sessionManager: SessionManager!
    var testIntention: Intention!
    
    override func setUp() {
        super.setUp()
        sessionManager = SessionManager()
        testIntention = Intention(
            id: UUID(),
            task: "Test Task",
            whyItMatters: "Testing is important",
            plannedDuration: 25,
            scheduledDate: Date(),
            strictness: .focused,
            temptationBundle: "Social media",
            status: .planned
        )
    }
    
    override func tearDown() {
        sessionManager = nil
        testIntention = nil
        super.tearDown()
    }
    
    // MARK: - Session Lifecycle Tests
    
    func testSessionLifecycle() async {
        // Initial state should be idle
        XCTAssertEqual(sessionManager.sessionState, .idle)
        XCTAssertNil(sessionManager.activeSession)
        XCTAssertNil(sessionManager.currentIntention)
        
        // Start session
        await sessionManager.startSession(intention: testIntention)
        
        XCTAssertEqual(sessionManager.sessionState, .active)
        XCTAssertNotNil(sessionManager.activeSession)
        XCTAssertEqual(sessionManager.currentIntention?.id, testIntention.id)
        XCTAssertEqual(sessionManager.elapsedTime, 0)
        XCTAssertFalse(sessionManager.isPaused)
        
        // End session
        await sessionManager.endSession(reflection: "Test completed")
        
        // Session should be ended and reset
        XCTAssertEqual(sessionManager.sessionState, .idle)
        XCTAssertNil(sessionManager.currentIntention)
    }
    
    func testStartSessionTwice() async {
        // First session start
        await sessionManager.startSession(intention: testIntention)
        XCTAssertEqual(sessionManager.sessionState, .active)
        
        // Create second intention
        let secondIntention = Intention(
            id: UUID(),
            task: "Second Task",
            whyItMatters: "Second test",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .planned
        )
        
        // Try to start another session while one is active - should be ignored
        let firstSessionId = sessionManager.activeSession?.id
        await sessionManager.startSession(intention: secondIntention)
        
        // Session should still be the first one
        XCTAssertEqual(sessionManager.activeSession?.id, firstSessionId)
        XCTAssertEqual(sessionManager.currentIntention?.id, testIntention.id)
    }
    
    // MARK: - Intention CRUD Tests
    
    func testIntentionCRUD() async {
        // Create and start session with intention
        await sessionManager.startSession(intention: testIntention)
        
        // Verify intention properties are preserved
        XCTAssertEqual(sessionManager.currentIntention?.task, "Test Task")
        XCTAssertEqual(sessionManager.currentIntention?.whyItMatters, "Testing is important")
        XCTAssertEqual(sessionManager.currentIntention?.plannedDuration, 25)
        XCTAssertEqual(sessionManager.currentIntention?.strictness, .focused)
        XCTAssertEqual(sessionManager.currentIntention?.temptationBundle, "Social media")
        
        // Session should have correct intention ID
        XCTAssertEqual(sessionManager.activeSession?.intentionId, testIntention.id)
        
        // End and verify cleanup
        await sessionManager.endSession()
        XCTAssertNil(sessionManager.currentIntention)
    }
    
    // MARK: - Pause/Resume Tests
    
    func testPauseResume() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Initial state
        XCTAssertFalse(sessionManager.isPaused)
        XCTAssertEqual(sessionManager.sessionState, .active)
        
        // Pause
        sessionManager.pauseSession()
        XCTAssertTrue(sessionManager.isPaused)
        XCTAssertEqual(sessionManager.sessionState, .paused)
        
        // Try to pause again - should be idempotent
        sessionManager.pauseSession()
        XCTAssertTrue(sessionManager.isPaused)
        XCTAssertEqual(sessionManager.sessionState, .paused)
        
        // Resume
        sessionManager.resumeSession()
        XCTAssertFalse(sessionManager.isPaused)
        XCTAssertEqual(sessionManager.sessionState, .active)
        
        // Try to resume again - should be idempotent
        sessionManager.resumeSession()
        XCTAssertFalse(sessionManager.isPaused)
        XCTAssertEqual(sessionManager.sessionState, .active)
    }
    
    func testPauseResumeStateTransitions() async {
        // Cannot pause when idle
        sessionManager.pauseSession()
        XCTAssertEqual(sessionManager.sessionState, .idle)
        
        // Cannot resume when idle
        sessionManager.resumeSession()
        XCTAssertEqual(sessionManager.sessionState, .idle)
        
        // Start session
        await sessionManager.startSession(intention: testIntention)
        
        // Pause
        sessionManager.pauseSession()
        XCTAssertEqual(sessionManager.sessionState, .paused)
        
        // Cannot pause when already paused
        sessionManager.pauseSession()
        XCTAssertEqual(sessionManager.sessionState, .paused)
        
        // Resume
        sessionManager.resumeSession()
        XCTAssertEqual(sessionManager.sessionState, .active)
    }
    
    // MARK: - Timer Accuracy Tests
    
    func testTimerStartsOnSessionStart() async {
        await sessionManager.startSession(intention: testIntention)
        
        XCTAssertEqual(sessionManager.elapsedTime, 0)
        
        // Wait a bit and verify timer is working
        try? await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        
        // Timer should have advanced (approximately)
        XCTAssertGreaterThanOrEqual(sessionManager.elapsedTime, 1)
        XCTAssertLessThan(sessionManager.elapsedTime, 3) // Should be close to 1-2 seconds
    }
    
    func testTimerStopsOnPause() async throws {
        await sessionManager.startSession(intention: testIntention)
        
        // Wait for timer to advance
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let elapsedBeforePause = sessionManager.elapsedTime
        
        // Pause
        sessionManager.pauseSession()
        
        // Wait again
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Timer should not have advanced
        XCTAssertEqual(sessionManager.elapsedTime, elapsedBeforePause)
    }
    
    func testTimerResumesCorrectly() async throws {
        await sessionManager.startSession(intention: testIntention)
        
        // Wait and pause
        try await Task.sleep(nanoseconds: 1_000_000_000)
        sessionManager.pauseSession()
        
        let elapsedAtPause = sessionManager.elapsedTime
        
        // Wait during pause
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Resume
        sessionManager.resumeSession()
        
        // Wait after resume
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Total elapsed should be approximately elapsedAtPause + 1 second
        XCTAssertGreaterThan(sessionManager.elapsedTime, elapsedAtPause)
    }
    
    func testFormattedElapsedTime() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Test initial state
        XCTAssertEqual(sessionManager.formattedElapsedTime(), "00:00")
        
        // Simulate elapsed time
        let testIntervals: [(TimeInterval, String)] = [
            (0, "00:00"),
            (30, "00:30"),
            (60, "01:00"),
            (90, "01:30"),
            (3661, "1:01:01")
        ]
        
        for (interval, expected) in testIntervals {
            sessionManager.elapsedTime = interval
            let formatted = sessionManager.formattedElapsedTime()
            
            if interval < 3600 {
                // Minutes:seconds format
                let parts = formatted.split(separator: ":")
                XCTAssertEqual(parts.count, 2, "Format should be MM:SS for durations under 1 hour")
            } else {
                // Hours:minutes:seconds format
                let parts = formatted.split(separator: ":")
                XCTAssertEqual(parts.count, 3, "Format should be H:MM:SS for durations over 1 hour")
            }
        }
    }
    
    func testProgressPercentage() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Test initial progress
        XCTAssertEqual(sessionManager.progressPercentage(), 0, accuracy: 0.001)
        
        // Test halfway (12.5 minutes elapsed, 25 minute planned)
        sessionManager.elapsedTime = 12.5 * 60
        XCTAssertEqual(sessionManager.progressPercentage(), 0.5, accuracy: 0.001)
        
        // Test completion
        sessionManager.elapsedTime = 25 * 60
        XCTAssertEqual(sessionManager.progressPercentage(), 1.0, accuracy: 0.001)
        
        // Test over completion (should cap at 1.0)
        sessionManager.elapsedTime = 30 * 60
        XCTAssertEqual(sessionManager.progressPercentage(), 1.0, accuracy: 0.001)
    }
    
    func testRemainingTime() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Initial remaining time
        let initialRemaining = sessionManager.remainingTime()
        XCTAssertEqual(initialRemaining, 25 * 60, accuracy: 1)
        
        // Halfway
        sessionManager.elapsedTime = 12.5 * 60
        let halfwayRemaining = sessionManager.remainingTime()
        XCTAssertEqual(halfwayRemaining, 12.5 * 60, accuracy: 1)
        
        // Completed
        sessionManager.elapsedTime = 30 * 60
        let completedRemaining = sessionManager.remainingTime()
        XCTAssertEqual(completedRemaining, 0, accuracy: 1)
        
        // Formatted remaining
        sessionManager.elapsedTime = 10 * 60
        XCTAssertEqual(sessionManager.formattedRemainingTime(), "15:00")
    }
    
    // MARK: - Strictness Mode Tests
    
    func testStrictnessModeTransitions() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Default should be focused (from test intention)
        XCTAssertEqual(sessionManager.currentIntention?.strictness, .focused)
        
        // Test setting each mode
        let modes: [StrictnessLevel] = [.quiet, .gentle, .focused, .accountable]
        
        for mode in modes {
            sessionManager.setStrictnessMode(mode)
            // The mode is passed to urlTracker, so we verify no crash
        }
    }
    
    func testStrictnessModeBeforeSession() {
        // Should be able to set strictness even before session starts
        sessionManager.setStrictnessMode(.quiet)
        sessionManager.setStrictnessMode(.accountable)
        // No crash expected
    }
    
    // MARK: - Distraction Logging Tests
    
    func testLogDistraction() async {
        await sessionManager.startSession(intention: testIntention)
        
        // Log a distraction
        sessionManager.logDistraction(reason: "Social media")
        
        XCTAssertEqual(sessionManager.activeSession?.interruptions.count, 1)
        XCTAssertEqual(sessionManager.activeSession?.interruptions.first?.category, "Social media")
        XCTAssertFalse(sessionManager.activeSession?.interruptions.first?.acknowledged ?? true)
        
        // Log another
        sessionManager.logDistraction(reason: "Email notification")
        
        XCTAssertEqual(sessionManager.activeSession?.interruptions.count, 2)
    }
    
    func testAcknowledgeDistraction() async {
        await sessionManager.startSession(intention: testIntention)
        
        sessionManager.logDistraction(reason: "Test distraction")
        
        // Acknowledge
        sessionManager.acknowledgeDistraction(at: 0)
        
        XCTAssertTrue(sessionManager.activeSession?.interruptions.first?.acknowledged ?? false)
    }
    
    func testLogDistractionWhenPaused() async {
        await sessionManager.startSession(intention: testIntention)
        sessionManager.pauseSession()
        
        // Should still be able to log distractions when paused
        sessionManager.logDistraction(reason: "While paused")
        
        XCTAssertEqual(sessionManager.activeSession?.interruptions.count, 1)
    }
    
    func testLogDistractionWhenIdle() {
        // Should not add distractions when idle
        sessionManager.logDistraction(reason: "While idle")
        
        XCTAssertNil(sessionManager.activeSession)
    }
    
    // MARK: - Session End Tests
    
    func testEndSessionWithReflection() async {
        await sessionManager.startSession(intention: testIntention)
        
        let reflection = "Productive session, completed all tasks"
        await sessionManager.endSession(reflection: reflection)
        
        // Check that session was properly ended with reflection
        // Note: After endSession, activeSession is nil, so we can't check reflection directly
        // In a real implementation, we would save to persistence first
    }
    
    func testEndSessionWhilePaused() async {
        await sessionManager.startSession(intention: testIntention)
        sessionManager.pauseSession()
        
        // Should be able to end while paused
        await sessionManager.endSession()
        
        XCTAssertEqual(sessionManager.sessionState, .idle)
        XCTAssertNil(sessionManager.currentIntention)
    }
    
    func testEndSessionTwice() async {
        await sessionManager.startSession(intention: testIntention)
        await sessionManager.endSession()
        
        // Second end should be idempotent
        await sessionManager.endSession()
        
        XCTAssertEqual(sessionManager.sessionState, .idle)
    }
    
    func testEndSessionWhenIdle() async {
        // Should be idempotent when idle
        await sessionManager.endSession()
        XCTAssertEqual(sessionManager.sessionState, .idle)
    }
}
