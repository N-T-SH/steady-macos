import AppKit
import SwiftUI
import Carbon

@MainActor
class MenuBarController: NSObject {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var appState: AppState!
    var hostingController: NSHostingController<ConversationPanel>!
    
    // Panel configuration
    private let panelWidth: CGFloat = 400
    private let panelHeight: CGFloat = 600
    
    // Hotkey support
    private var eventMonitor: Any?
    private var globalHotkey: EventHotKeyRef?

    // Hourly check-in flash
    private var hourlyCheckInTimer: Timer?
    
    func setupMenuBar() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTimerExpired),
            name: .focusTimerExpired, object: nil
        )
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Configure the status item button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Steady")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Setup the panel
        setupPanel()
        
        // Setup hotkey
        setupHotkey()
        
        // Setup event monitor for clicking outside
        setupEventMonitor()

        // Flash the icon once an hour as a gentle check-in prompt
        hourlyCheckInTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.handleTimerExpired() }
        }
    }
    
    private func setupPanel() {
        // Create the panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel properties
        panel.title = "Steady"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Create the hosting controller with ConversationPanel
        let conversationPanel = ConversationPanel(appState: appState)
        hostingController = NSHostingController(rootView: conversationPanel)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        
        // Set the content view
        panel.contentView = hostingController.view
        
        // Don't auto-hide on deactivate — we manage visibility manually
        panel.hidesOnDeactivate = false
    }
    
    private func setupHotkey() {
        // Register Cmd+Shift+Space hotkey
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = FourCharCode(from: "STDY")
        hotKeyID.id = 1
        
        // Register the event handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .togglePanelHotkey, object: nil)
                    }
                }
                return noErr
            },
            1,
            nil,
            nil,
            nil
        )
        
        // Register Cmd+Shift+Space (kVK_Space = 0x31, cmdKey = 0x0100, shiftKey = 0x0200)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &globalHotkey
        )
        
        // Listen for hotkey notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkey),
            name: .togglePanelHotkey,
            object: nil
        )
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.panel.isVisible else { return }
            
            // Check if click is outside the panel
            let clickLocation = NSEvent.mouseLocation
            if !self.panel.frame.contains(clickLocation) {
                // Also check if click is not on the status item
                if let button = self.statusItem.button {
                    let buttonFrameInScreen = button.window?.convertToScreen(button.frame) ?? button.frame
                    if !buttonFrameInScreen.contains(clickLocation) {
                        self.hidePanel()
                    }
                } else {
                    self.hidePanel()
                }
            }
        }
    }
    
    @objc func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    @objc func handleHotkey() {
        togglePanel()
    }

    @objc private func handleTimerExpired() {
        guard let button = statusItem.button else { return }
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak button] timer in
            count += 1
            let isOrange = count % 2 == 1
            button?.contentTintColor = isOrange ? .orange : nil
            button?.image = NSImage(
                systemSymbolName: isOrange ? "waveform.circle.fill" : "waveform",
                accessibilityDescription: "Steady"
            )
            button?.image?.size = NSSize(width: 18, height: 18)
            if count >= 12 { // ~5.4 seconds
                timer.invalidate()
                button?.contentTintColor = nil
            }
        }
    }
    
    func showPanel() {
        positionPanelBelowStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        appState.showPanel()
        updateStatusItemAppearance()
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        appState.hidePanel()
        updateStatusItemAppearance()
    }
    
    private func positionPanelBelowStatusItem() {
        guard let button = statusItem.button, let window = button.window else { return }
        
        let buttonFrame = button.frame
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        
        // Calculate panel position
        var panelX = window.frame.origin.x + buttonFrame.origin.x + (buttonFrame.width / 2) - (panelWidth / 2)
        let panelY = window.frame.origin.y - panelHeight - 5
        
        // Ensure panel stays on screen
        let minX: CGFloat = screenFrame.origin.x + 10
        let maxX = screenFrame.origin.x + screenFrame.width - panelWidth - 10
        
        panelX = max(minX, min(panelX, maxX))
        
        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
    }
    
    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        
        if panel.isVisible {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Steady Active")
        } else {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Steady")
        }
        button.image?.size = NSSize(width: 18, height: 18)
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hourlyCheckInTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let togglePanelHotkey = Notification.Name("TogglePanelHotkey")
}

// MARK: - FourCharCode Helper

extension FourCharCode {
    init(from string: String) {
        var result: FourCharCode = 0
        let characters = Array(string.utf8)
        for i in 0..<Swift.min(4, characters.count) {
            result = result << 8 + FourCharCode(characters[i])
        }
        self = result
    }
}

// MARK: - Virtual Key Codes

let kVK_Space: Int = 0x31
let cmdKey: UInt32 = 0x0100
let shiftKey: UInt32 = 0x0200
