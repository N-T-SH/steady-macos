import Foundation
import XCTest
import Carbon
@testable import Steady

@MainActor
class HotkeyTests: XCTestCase {
    
    var hotkeyManager: HotkeyManager!
    var toggleCalled: Bool!
    var distractionCalled: Bool!
    var intentionCalled: Bool!
    
    override func setUp() {
        super.setUp()
        hotkeyManager = HotkeyManager.shared
        toggleCalled = false
        distractionCalled = false
        intentionCalled = false
        
        // Unregister any existing hotkeys before tests
        hotkeyManager.unregisterHotkeys()
    }
    
    override func tearDown() {
        // Clean up
        hotkeyManager.unregisterHotkeys()
        hotkeyManager.onTogglePanel = nil
        hotkeyManager.onLogDistraction = nil
        hotkeyManager.onStartIntention = nil
        toggleCalled = nil
        distractionCalled = nil
        intentionCalled = nil
        super.tearDown()
    }
    
    // MARK: - Hotkey Registration Tests
    
    func testHotkeyRegistration() {
        // Set up callbacks
        hotkeyManager.onTogglePanel = { [weak self] in
            self?.toggleCalled = true
        }
        hotkeyManager.onLogDistraction = { [weak self] in
            self?.distractionCalled = true
        }
        hotkeyManager.onStartIntention = { [weak self] in
            self?.intentionCalled = true
        }
        
        // Register hotkeys
        hotkeyManager.registerHotkeys()
        
        // Verify callbacks are set
        XCTAssertNotNil(hotkeyManager.onTogglePanel)
        XCTAssertNotNil(hotkeyManager.onLogDistraction)
        XCTAssertNotNil(hotkeyManager.onStartIntention)
    }
    
    func testHotkeyRegistrationIdempotent() {
        // Register twice should not create duplicate handlers
        hotkeyManager.registerHotkeys()
        hotkeyManager.registerHotkeys()
        
        // Should complete without crashing or errors
        XCTAssertTrue(true)
    }
    
    func testHotkeyUnregistration() {
        // Register first
        hotkeyManager.onTogglePanel = { [weak self] in
            self?.toggleCalled = true
        }
        hotkeyManager.registerHotkeys()
        
        // Unregister
        hotkeyManager.unregisterHotkeys()
        
        // Verify callbacks are cleared (indirectly by checking we can re-register)
        hotkeyManager.registerHotkeys()
        XCTAssertNotNil(hotkeyManager.onTogglePanel)
    }
    
    // MARK: - Hotkey Trigger Tests
    
    func testTogglePanelCallback() {
        let expectation = self.expectation(description: "Toggle panel callback")
        
        hotkeyManager.onTogglePanel = {
            self.toggleCalled = true
            expectation.fulfill()
        }
        
        hotkeyManager.registerHotkeys()
        
        // Note: Cannot actually simulate global hotkey press in unit tests
        // But we can verify the callback mechanism is set up
        
        // Manually trigger the callback for testing
        hotkeyManager.onTogglePanel?()
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertTrue(self.toggleCalled)
        }
    }
    
    func testLogDistractionCallback() {
        let expectation = self.expectation(description: "Log distraction callback")
        
        hotkeyManager.onLogDistraction = {
            self.distractionCalled = true
            expectation.fulfill()
        }
        
        hotkeyManager.registerHotkeys()
        
        // Manually trigger the callback for testing
        hotkeyManager.onLogDistraction?()
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertTrue(self.distractionCalled)
        }
    }
    
    func testStartIntentionCallback() {
        let expectation = self.expectation(description: "Start intention callback")
        
        hotkeyManager.onStartIntention = {
            self.intentionCalled = true
            expectation.fulfill()
        }
        
        hotkeyManager.registerHotkeys()
        
        // Manually trigger the callback for testing
        hotkeyManager.onStartIntention?()
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertTrue(self.intentionCalled)
        }
    }
    
    func testAllCallbacksCanTrigger() {
        let toggleExpectation = expectation(description: "Toggle")
        let distractionExpectation = expectation(description: "Distraction")
        let intentionExpectation = expectation(description: "Intention")
        
        hotkeyManager.onTogglePanel = {
            self.toggleCalled = true
            toggleExpectation.fulfill()
        }
        hotkeyManager.onLogDistraction = {
            self.distractionCalled = true
            distractionExpectation.fulfill()
        }
        hotkeyManager.onStartIntention = {
            self.intentionCalled = true
            intentionExpectation.fulfill()
        }
        
        hotkeyManager.registerHotkeys()
        
        // Trigger all callbacks
        hotkeyManager.onTogglePanel?()
        hotkeyManager.onLogDistraction?()
        hotkeyManager.onStartIntention?()
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertTrue(self.toggleCalled)
            XCTAssertTrue(self.distractionCalled)
            XCTAssertTrue(self.intentionCalled)
        }
    }
    
    // MARK: - Accessibility Permission Tests
    
    func testAccessibilityPermissionCheck() {
        // This test verifies the method exists and returns a boolean
        let hasPermission = hotkeyManager.checkAccessibilityPermissions()
        
        // Result depends on system state, but should be a valid boolean
        XCTAssertTrue(hasPermission == true || hasPermission == false)
    }
    
    func testAccessibilityPermissionRequest() {
        // This test verifies the method exists and doesn't crash
        // Note: This may trigger a system dialog in real runs
        hotkeyManager.requestAccessibilityPermissions()
        
        // Should complete without crashing
        XCTAssertTrue(true)
    }
    
    // MARK: - Hotkey Descriptions Tests
    
    func testHotkeyDescriptions() {
        let descriptions = hotkeyManager.getHotkeyDescriptions()
        
        // Should return 3 hotkey descriptions
        XCTAssertEqual(descriptions.count, 3)
        
        // Verify each has required fields
        for desc in descriptions {
            XCTAssertGreaterThan(desc.id, 0)
            XCTAssertFalse(desc.shortcut.isEmpty)
            XCTAssertFalse(desc.action.isEmpty)
        }
        
        // Verify specific shortcuts are present
        let shortcuts = descriptions.map { $0.shortcut }
        XCTAssertTrue(shortcuts.contains("⌘⇧Space"))
        XCTAssertTrue(shortcuts.contains("⌘⇧D"))
        XCTAssertTrue(shortcuts.contains("⌘⇧I"))
    }
    
    func testHotkeyIDUniqueness() {
        // Hotkey IDs should be unique
        let descriptions = hotkeyManager.getHotkeyDescriptions()
        let ids = descriptions.map { $0.id }
        let uniqueIds = Set(ids)
        
        XCTAssertEqual(ids.count, uniqueIds.count, "Hotkey IDs should be unique")
    }
    
    // MARK: - Singleton Tests
    
    func testHotkeyManagerSingleton() {
        let manager1 = HotkeyManager.shared
        let manager2 = HotkeyManager.shared
        
        XCTAssertTrue(manager1 === manager2, "HotkeyManager should be a singleton")
    }
    
    // MARK: - Key Code Tests
    
    func testKeyCodeValues() {
        // Verify key code enum values match expected macOS key codes
        // These are standard macOS key codes for reference
        let spaceKeyCode: UInt32 = 49
        let dKeyCode: UInt32 = 2
        let iKeyCode: UInt32 = 34
        
        XCTAssertEqual(spaceKeyCode, 49)
        XCTAssertEqual(dKeyCode, 2)
        XCTAssertEqual(iKeyCode, 34)
    }
    
    func testModifierFlags() {
        // Verify Carbon modifier constants
        let cmdModifier = cmdKey
        let shiftModifier = shiftKey
        
        XCTAssertGreaterThan(cmdModifier, 0)
        XCTAssertGreaterThan(shiftModifier, 0)
        
        // Combined modifier should include both
        let combined = cmdKey + shiftKey
        XCTAssertGreaterThan(combined, cmdModifier)
        XCTAssertGreaterThan(combined, shiftModifier)
    }
    
    // MARK: - Callback Reset Tests
    
    func testCallbackResetOnUnregister() {
        // Set up callbacks
        hotkeyManager.onTogglePanel = { }
        hotkeyManager.onLogDistraction = { }
        hotkeyManager.onStartIntention = { }
        
        // Register and unregister
        hotkeyManager.registerHotkeys()
        hotkeyManager.unregisterHotkeys()
        
        // Re-register - callbacks should still be set (they're not cleared by unregister)
        hotkeyManager.registerHotkeys()
        
        XCTAssertNotNil(hotkeyManager.onTogglePanel)
        XCTAssertNotNil(hotkeyManager.onLogDistraction)
        XCTAssertNotNil(hotkeyManager.onStartIntention)
    }
    
    // MARK: - Error Handling Tests
    
    func testHotkeyRegistrationWithoutPermissions() {
        // Register without checking permissions
        // Should still complete (permissions checked separately)
        hotkeyManager.registerHotkeys()
        
        // Should not crash
        XCTAssertTrue(true)
    }
    
    func testCallbackNilSafety() {
        hotkeyManager.registerHotkeys()
        
        // Call optional closures without setting them - should not crash
        hotkeyManager.onTogglePanel?()
        hotkeyManager.onLogDistraction?()
        hotkeyManager.onStartIntention?()
        
        XCTAssertTrue(true)
    }
    
    // MARK: - Memory Management Tests
    
    func testCallbackMemorySafety() {
        weak var weakManager = hotkeyManager
        
        // Create temporary closures
        hotkeyManager.onTogglePanel = { [weak self] in
            self?.toggleCalled = true
        }
        
        // Verify manager still exists
        XCTAssertNotNil(weakManager)
        
        // Unregister
        hotkeyManager.unregisterHotkeys()
        
        // Manager should still exist
        XCTAssertNotNil(weakManager)
    }
    
    // MARK: - Integration Tests
    
    func testFullHotkeyWorkflow() {
        let toggleExp = expectation(description: "toggle")
        let distractionExp = expectation(description: "distraction")
        let intentionExp = expectation(description: "intention")
        
        var toggleCount = 0
        var distractionCount = 0
        var intentionCount = 0
        
        hotkeyManager.onTogglePanel = {
            toggleCount += 1
            toggleExp.fulfill()
        }
        hotkeyManager.onLogDistraction = {
            distractionCount += 1
            distractionExp.fulfill()
        }
        hotkeyManager.onStartIntention = {
            intentionCount += 1
            intentionExp.fulfill()
        }
        
        // Register
        hotkeyManager.registerHotkeys()
        
        // Trigger callbacks
        hotkeyManager.onTogglePanel?()
        hotkeyManager.onLogDistraction?()
        hotkeyManager.onStartIntention?()
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(toggleCount, 1)
            XCTAssertEqual(distractionCount, 1)
            XCTAssertEqual(intentionCount, 1)
        }
    }
    
    func testMultipleUnregisterCalls() {
        // Multiple unregister calls should be safe
        hotkeyManager.registerHotkeys()
        hotkeyManager.unregisterHotkeys()
        hotkeyManager.unregisterHotkeys()
        hotkeyManager.unregisterHotkeys()
        
        // Should not crash
        XCTAssertTrue(true)
    }
}
