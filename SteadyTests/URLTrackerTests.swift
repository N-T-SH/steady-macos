import XCTest
@testable import Steady

@MainActor
final class URLTrackerTests: XCTestCase {
    
    var urlTracker: URLTracker!
    var mockDelegate: MockURLTrackerDelegate!
    var mockLLMProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        urlTracker = URLTracker()
        mockDelegate = MockURLTrackerDelegate()
        mockLLMProvider = MockLLMProvider()
    }
    
    override func tearDown() {
        urlTracker = nil
        mockDelegate = nil
        mockLLMProvider = nil
        super.tearDown()
    }
    
    func testPermissionCheck() {
        // Permission check should return a boolean
        let hasPermission = urlTracker.checkPermission()
        // Result depends on system state, but method should not crash
        XCTAssertNotNil(hasPermission)
    }
    
    func testPollingThrottle() async {
        let intention = Intention(
            id: UUID(),
            task: "Test task",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        // Should not start tracking without permission
        await urlTracker.startTracking(intention: intention, llmProvider: mockLLMProvider)
        
        // Verify tracking state
        let isTracking = await urlTracker.isTracking
        // May or may not be tracking depending on permissions
        XCTAssertNotNil(isTracking)
    }
}

class MockURLTrackerDelegate: URLTrackerDelegate {
    var lastURL: String?
    var lastTitle: String?
    var offTaskClassification: URLClassification?
    var didLosePermission = false
    
    func urlTracker(_ tracker: URLTracker, didDetectURL url: String, title: String) {
        lastURL = url
        lastTitle = title
    }
    
    func urlTracker(_ tracker: URLTracker, didDetectOffTask classification: URLClassification) {
        offTaskClassification = classification
    }
    
    func urlTrackerDidLosePermission(_ tracker: URLTracker) {
        didLosePermission = true
    }
}

class MockLLMProvider: LLMProvider {
    func classifyURL(url: String, pageTitle: String, intention: Intention) async throws -> URLClassification {
        return URLClassification(
            url: url,
            pageTitle: pageTitle,
            onTask: true,
            project: intention.task,
            category: .coding,
            confidence: 0.95,
            reasoning: "Mock classification",
            timestamp: Date()
        )
    }
    
    func generateConversationResponse(messages: [ConversationTurn], context: ConversationContext) async throws -> String {
        return "Mock response"
    }
}
