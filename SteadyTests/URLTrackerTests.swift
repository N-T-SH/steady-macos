import XCTest
@testable import Steady

@MainActor
final class URLTrackerTests: XCTestCase {

    var urlTracker: URLTracker!
    var mockDelegate: MockURLTrackerDelegate!

    override func setUp() {
        super.setUp()
        urlTracker = URLTracker()
        mockDelegate = MockURLTrackerDelegate()
    }

    override func tearDown() {
        urlTracker = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testInitialState() async {
        let isTracking = await urlTracker.isTracking
        XCTAssertFalse(isTracking)
    }

    func testStopTrackingWhileIdle() async {
        // Stop when not running should be a no-op
        await urlTracker.stopTracking()
        let isTracking = await urlTracker.isTracking
        XCTAssertFalse(isTracking)
    }

    func testUpdateIntentionDoesNotCrash() async {
        let intention = Intention(
            id: UUID(), task: "Test task", whyItMatters: "Testing",
            scheduledDate: Date(), strictness: .gentle, temptationBundle: nil, status: .active
        )
        await urlTracker.updateIntention(intention)
        await urlTracker.updateIntention(nil)
    }
}

class MockURLTrackerDelegate: URLTrackerDelegate {
    var lastURL: String?
    var lastTitle: String?
    var offTaskClassification: URLClassification?
    var activityWatchStatus: Bool? = nil

    func urlTracker(_ tracker: URLTracker, didDetectURL url: String, title: String) {
        lastURL = url; lastTitle = title
    }
    func urlTracker(_ tracker: URLTracker, didClassifyURL classification: URLClassification) {}
    func urlTracker(_ tracker: URLTracker, didDetectOffTask classification: URLClassification) {
        offTaskClassification = classification
    }
    func urlTracker(_ tracker: URLTracker, didDiscoverNewRule domain: String, projectName: String, category: URLCategory) {}
    func urlTracker(_ tracker: URLTracker, didUpdateActivityWatchStatus available: Bool) {
        activityWatchStatus = available
    }
}
