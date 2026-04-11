import AppKit
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cancel any previously scheduled system notifications (from older app versions)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        setupServices()

        menuBarController = MenuBarController()
        menuBarController.appState = appState
        menuBarController.setupMenuBar()

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkeys()
    }

    // MARK: - Service Initialization

    private func setupServices() {
        // Build LLM config from UserDefaults (PreferencesView writes these keys)
        var config = LLMConfig.default
        if let url = UserDefaults.standard.string(forKey: "llm.providerURL"), !url.isEmpty {
            config.providerURL = url
        }
        if let model = UserDefaults.standard.string(forKey: "llm.classificationModel"), !model.isEmpty {
            config.classificationModel = model
        }
        if let model = UserDefaults.standard.string(forKey: "llm.conversationModel"), !model.isEmpty {
            config.conversationModel = model
        }

        let llmProvider = LLMProvider(config: config)
        let conversationEngine = ConversationEngine(llmProvider: llmProvider)
        let sessionManager = SessionManager()
        sessionManager.configure(llmProvider: llmProvider)

        appState.configure(sessionManager: sessionManager, conversationEngine: conversationEngine, llmProvider: llmProvider)

        // Register global hotkeys
        setupHotkeys()

        // ActivityWatch provides tracking — no special macOS permissions needed
    }

    private func setupHotkeys() {
        let manager = HotkeyManager.shared

        manager.onTogglePanel = { [weak self] in
            DispatchQueue.main.async {
                self?.menuBarController.togglePanel()
            }
        }

        manager.onLogDistraction = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.appState.sessionManager?.sessionState == .active else { return }
                self.appState.logDistraction(url: nil, category: "Manual")
                NotificationCenter.default.post(name: .steadyShowLogDistraction, object: nil)
            }
        }

        manager.onStartIntention = { [weak self] in
            DispatchQueue.main.async {
                self?.menuBarController.showPanel()
            }
        }

        manager.registerHotkeys()
    }

}

extension Notification.Name {
    static let steadyShowLogDistraction = Notification.Name("SteadyShowLogDistraction")
}
