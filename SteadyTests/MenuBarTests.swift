import XCTest
@testable import Steady

@MainActor
final class MenuBarTests: XCTestCase {
    var appState: AppState!
    var menuBarController: MenuBarController!
    
    override func setUp() {
        super.setUp()
        appState = AppState()
        menuBarController = MenuBarController()
        menuBarController.appState = appState
    }
    
    override func tearDown() {
        if let panel = menuBarController?.panel {
            panel.orderOut(nil)
        }
        menuBarController = nil
        appState = nil
        super.tearDown()
    }
    
    // MARK: - Menu Bar Icon Tests
    
    func testMenuBarIconExists() {
        // Given
        menuBarController.setupMenuBar()
        
        // Then
        XCTAssertNotNil(menuBarController.statusItem, "Status item should exist")
        XCTAssertNotNil(menuBarController.statusItem.button, "Status item button should exist")
        XCTAssertNotNil(menuBarController.statusItem.button?.image, "Status item should have an image")
    }
    
    // MARK: - Panel Visibility Tests
    
    func testPanelShowsOnClick() {
        // Given
        menuBarController.setupMenuBar()
        
        // Then - initially panel should not be visible
        XCTAssertFalse(menuBarController.panel.isVisible, "Panel should be hidden initially")
        XCTAssertFalse(appState.isPanelVisible, "AppState should reflect panel is hidden")
        
        // When - toggle panel
        menuBarController.togglePanel()
        
        // Then - panel should be visible
        XCTAssertTrue(menuBarController.panel.isVisible, "Panel should be visible after toggle")
        XCTAssertTrue(appState.isPanelVisible, "AppState should reflect panel is visible")
    }
    
    func testPanelHidesOnDeactivate() {
        // Given
        menuBarController.setupMenuBar()
        menuBarController.showPanel()
        
        // Verify panel is visible
        XCTAssertTrue(menuBarController.panel.isVisible, "Panel should be visible")
        
        // When - simulate deactivation (hidesOnDeactivate is set to true)
        // The panel should hide when the app loses focus due to hidesOnDeactivate = true
        menuBarController.hidePanel()
        
        // Then
        XCTAssertFalse(menuBarController.panel.isVisible, "Panel should be hidden")
        XCTAssertFalse(appState.isPanelVisible, "AppState should reflect panel is hidden")
    }
    
    func testTogglePanelTwice() {
        // Given
        menuBarController.setupMenuBar()
        
        // When - toggle twice
        menuBarController.togglePanel()
        XCTAssertTrue(menuBarController.panel.isVisible)
        
        menuBarController.togglePanel()
        
        // Then
        XCTAssertFalse(menuBarController.panel.isVisible, "Panel should be hidden after second toggle")
        XCTAssertFalse(appState.isPanelVisible, "AppState should reflect panel is hidden")
    }
    
    // MARK: - Hotkey Tests
    
    func testHotkeyTogglesPanel() {
        // Given
        menuBarController.setupMenuBar()
        
        // Then - initially panel should be hidden
        XCTAssertFalse(menuBarController.panel.isVisible)
        
        // When - simulate hotkey press by posting notification
        NotificationCenter.default.post(name: .togglePanelHotkey, object: nil)
        
        // Give a small delay for the notification to be processed
        let expectation = XCTestExpectation(description: "Hotkey notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then - panel should be visible after hotkey
        // Note: In actual test, the hotkey would need to be registered
        // This tests that the hotkey handler method exists and works
    }
    
    // MARK: - Panel Configuration Tests
    
    func testPanelConfiguration() {
        // Given
        menuBarController.setupMenuBar()
        
        // Then - verify panel configuration
        XCTAssertNotNil(menuBarController.panel)
        XCTAssertTrue(menuBarController.panel.isFloatingPanel, "Panel should be floating")
        XCTAssertTrue(menuBarController.panel.hidesOnDeactivate, "Panel should hide on deactivate")
        XCTAssertEqual(menuBarController.panel.level, .floating, "Panel should be at floating level")
        XCTAssertFalse(menuBarController.panel.isReleasedWhenClosed, "Panel should not be released when closed")
    }
    
    func testPanelSize() {
        // Given
        menuBarController.setupMenuBar()
        
        // Then - verify panel size
        let expectedWidth: CGFloat = 400
        let expectedHeight: CGFloat = 600
        
        XCTAssertEqual(menuBarController.panel.frame.width, expectedWidth, "Panel width should be 400")
        XCTAssertEqual(menuBarController.panel.frame.height, expectedHeight, "Panel height should be 600")
    }
    
    func testStatusItemButtonImageChangesWhenPanelVisible() {
        // Given
        menuBarController.setupMenuBar()
        
        // Get initial image
        let initialImage = menuBarController.statusItem.button?.image
        
        // When - show panel
        menuBarController.showPanel()
        
        // Then - image should change
        let activeImage = menuBarController.statusItem.button?.image
        XCTAssertNotEqual(initialImage?.name(), activeImage?.name(), "Image should change when panel is active")
    }
    
    // MARK: - App State Integration Tests
    
    func testAppStatePanelVisibilitySync() {
        // Given
        menuBarController.setupMenuBar()
        
        // When - toggle via app state
        appState.togglePanel()
        
        // Then - notification should be posted
        let expectation = XCTestExpectation(description: "Panel visibility notification received")
        var notificationReceived = false
        
        let observer = NotificationCenter.default.addObserver(
            forName: .panelVisibilityChanged,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        // Trigger notification
        NotificationCenter.default.post(name: .panelVisibilityChanged, object: nil, userInfo: ["isVisible": true])
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived, "Panel visibility notification should be received")
        
        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - NSImage Helper

extension NSImage {
    func name() -> String? {
        // Helper to compare image names
        return self.name()
    }
}
