import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var appState = AppState()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup app state
        setupAppState()
        
        // Setup menu bar controller
        menuBarController = MenuBarController()
        menuBarController.appState = appState
        menuBarController.setupMenuBar()
        
        // Hide dock icon (LSUIElement should be set in Info.plist)
        NSApp.setActivationPolicy(.accessory)
        
        // Prevent the app from showing in the dock
        NSApp.hide(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }
    
    private func setupAppState() {
        // Load any persisted state here
        // For now, we'll start fresh
    }
}
