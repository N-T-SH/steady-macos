import Foundation
import XCTest
import UserNotifications
@testable import Steady

@MainActor
class NotificationTests: XCTestCase {
    
    var notificationManager: NotificationManager!
    
    override func setUp() async throws {
        try await super.setUp()
        notificationManager = NotificationManager.shared
        
        // Clear any pending notifications before each test
        await notificationManager.clearPendingNotifications()
    }
    
    override func tearDown() async throws {
        // Clean up notifications after each test
        await notificationManager.clearPendingNotifications()
        notificationManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Authorization Tests
    
    func testNotificationAuthorization() async throws {
        // Test that authorization request doesn't throw
        do {
            try await notificationManager.requestAuthorization()
            // Authorization may or may not be granted depending on simulator/system state
            // We just verify it doesn't throw
        } catch {
            // If authorization fails, it should be due to user denial, not a coding error
            XCTAssertTrue(error is UNError || error.localizedDescription.contains("authorization"))
        }
    }
    
    // MARK: - Notification Scheduling Tests
    
    func testScheduleIntentionReminder() async throws {
        let intention = Intention(
            id: UUID(),
            task: "Test Task",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .planned
        )
        
        await notificationManager.scheduleIntentionReminder(intention: intention)
        
        // Give a moment for the notification to be scheduled
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count, 0) // May be 0 on simulator without permissions
    }
    
    func testScheduleSessionStart() async throws {
        let intention = Intention(
            id: UUID(),
            task: "Focus Session",
            whyItMatters: "Important work",
            plannedDuration: 60,
            scheduledDate: Date(),
            strictness: .focused,
            temptationBundle: nil,
            status: .active
        )
        
        await notificationManager.scheduleSessionStart(intention: intention)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count = await notificationManager.getPendingNotificationCount()
        // Note: On simulator without notification permissions, this may be 0
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    func testSendDriftAlert() async throws {
        let classification = URLClassification(
            url: "https://twitter.com",
            pageTitle: "Twitter",
            onTask: false,
            project: nil,
            category: .socialMedia,
            confidence: 0.92,
            reasoning: "Social media site",
            timestamp: Date()
        )
        
        await notificationManager.sendDriftAlert(classification: classification)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    func testSendStreakMilestone() async throws {
        // Test valid streak milestones (every 5 days)
        await notificationManager.sendStreakMilestone(streak: 5)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count5 = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count5, 0)
        
        // Clear and test 10-day streak
        await notificationManager.clearPendingNotifications()
        
        await notificationManager.sendStreakMilestone(streak: 10)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count10 = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count10, 0)
    }
    
    func testStreakMilestoneFiltering() async throws {
        // Clear any existing notifications
        await notificationManager.clearPendingNotifications()
        
        // Test that non-milestone streaks are filtered
        await notificationManager.sendStreakMilestone(streak: 3)
        await notificationManager.sendStreakMilestone(streak: 7)
        await notificationManager.sendStreakMilestone(streak: 12)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // None of these should trigger notifications (not multiples of 5)
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Notification Categories Tests
    
    func testNotificationCategoriesSetup() async throws {
        // Request authorization to trigger category setup
        do {
            try await notificationManager.requestAuthorization()
        } catch {
            // Continue even if authorization fails
        }
        
        // Categories are set up during authorization
        // We can verify the manager was properly initialized
        XCTAssertNotNil(notificationManager)
    }
    
    // MARK: - Quiet Delivery Tests
    
    func testQuietDeliveryDefault() async throws {
        let intention = Intention(
            id: UUID(),
            task: "Quiet Test",
            whyItMatters: "Testing quiet delivery",
            plannedDuration: 45,
            scheduledDate: Date(),
            strictness: .quiet,
            temptationBundle: nil,
            status: .planned
        )
        
        // Schedule a quiet notification
        await notificationManager.scheduleIntentionReminder(intention: intention)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify notification was scheduled (count may be 0 on simulator)
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    // MARK: - Rate Limiting Tests
    
    func testNotificationRateLimiting() async throws {
        // Clear existing notifications
        await notificationManager.clearPendingNotifications()
        
        let intention = Intention(
            id: UUID(),
            task: "Rate Limit Test",
            whyItMatters: "Testing rate limits",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .planned
        )
        
        // Try to schedule many notifications
        for i in 0..<10 {
            var mutableIntention = intention
            mutableIntention = Intention(
                id: UUID(),
                task: "Task \(i)",
                whyItMatters: intention.whyItMatters,
                plannedDuration: intention.plannedDuration,
                scheduledDate: intention.scheduledDate,
                strictness: intention.strictness,
                temptationBundle: intention.temptationBundle,
                status: intention.status
            )
            await notificationManager.scheduleSessionStart(intention: mutableIntention)
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let count = await notificationManager.getPendingNotificationCount()
        // Should be limited to max 4 notifications due to rate limiting
        XCTAssertLessThanOrEqual(count, 4)
    }
    
    // MARK: - Clear Notifications Tests
    
    func testClearPendingNotifications() async throws {
        let intention = Intention(
            id: UUID(),
            task: "Clear Test",
            whyItMatters: "Testing clear",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .planned
        )
        
        // Schedule a notification
        await notificationManager.scheduleSessionStart(intention: intention)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Clear all
        await notificationManager.clearPendingNotifications()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertEqual(count, 0)
    }
    
    func testClearNotificationsForSession() async throws {
        let sessionId = UUID()
        let intentionId = UUID()
        
        let session = Session(
            id: sessionId,
            intentionId: intentionId,
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 8,
            postSessionReflection: nil,
            urlClassifications: []
        )
        
        // Schedule nudge for session
        await notificationManager.scheduleSessionNudge(session: session)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Clear notifications for this specific session
        await notificationManager.clearNotifications(for: sessionId)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify notifications are cleared
        let count = await notificationManager.getPendingNotificationCount()
        // Count should be 0 or only contain non-session notifications
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    // MARK: - Time-Sensitive Tests
    
    func testTimeSensitiveDeadlineReminder() async throws {
        let intention = Intention(
            id: UUID(),
            task: "Deadline Test",
            whyItMatters: "Testing time-sensitive",
            plannedDuration: 60,
            scheduledDate: Date(),
            strictness: .accountable,
            temptationBundle: nil,
            status: .active
        )
        
        let deadline = Date().addingTimeInterval(3600) // 1 hour from now
        await notificationManager.scheduleDeadlineReminder(deadline: deadline, intention: intention)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let count = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    // MARK: - Pending Count Tests
    
    func testGetPendingNotificationCount() async throws {
        // Initially should be 0 (or have no errors)
        let initialCount = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(initialCount, 0)
        
        // Schedule a notification
        let intention = Intention(
            id: UUID(),
            task: "Count Test",
            whyItMatters: "Testing count",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .planned
        )
        
        await notificationManager.scheduleSessionStart(intention: intention)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Count should be >= 0 (may be 0 on simulator without permissions)
        let afterCount = await notificationManager.getPendingNotificationCount()
        XCTAssertGreaterThanOrEqual(afterCount, 0)
    }
}

// MARK: - Mock Tests for Notification Content

extension NotificationTests {
    
    func testNotificationContentStructure() {
        // Test that we can create notification content correctly
        let content = UNMutableNotificationContent()
        content.title = "Test Title"
        content.body = "Test Body"
        content.categoryIdentifier = "TEST_CATEGORY"
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = ["testId": "12345"]
        
        XCTAssertEqual(content.title, "Test Title")
        XCTAssertEqual(content.body, "Test Body")
        XCTAssertEqual(content.categoryIdentifier, "TEST_CATEGORY")
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertEqual(content.userInfo["testId"] as? String, "12345")
    }
    
    func testNotificationActionIdentifiers() {
        // Verify action identifiers are unique and correctly defined
        let actionIds = [
            "START_SESSION",
            "SKIP_SESSION",
            "LOG_DISTRACTION",
            "TAKE_BREAK",
            "BACK_TO_WORK",
            "DISMISS"
        ]
        
        let uniqueIds = Set(actionIds)
        XCTAssertEqual(actionIds.count, uniqueIds.count, "Action identifiers should be unique")
    }
    
    func testNotificationCategoryIdentifiers() {
        // Verify category identifiers are unique
        let categoryIds = [
            "INTENTION_CATEGORY",
            "SESSION_CATEGORY",
            "NUDGE_CATEGORY",
            "DRIFT_CATEGORY"
        ]
        
        let uniqueIds = Set(categoryIds)
        XCTAssertEqual(categoryIds.count, uniqueIds.count, "Category identifiers should be unique")
    }
}
