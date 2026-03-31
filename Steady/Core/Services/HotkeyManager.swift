import Foundation
import Carbon

/// Global hotkey manager using Carbon framework for system-wide keyboard shortcuts
/// Provides quick access to app features without requiring the app to be in focus
class HotkeyManager {
    static let shared = HotkeyManager()
    
    // MARK: - Callbacks
    
    var onTogglePanel: (() -> Void)?
    var onLogDistraction: (() -> Void)?
    var onStartIntention: (() -> Void)?
    
    // MARK: - Properties
    
    private var eventHandler: EventHandlerRef?
    private var registeredHotkeys: [Int: () -> Void] = [:]
    private var hotkeyIDs: [Int: EventHotKeyRef] = [:]
    
    // MARK: - Hotkey IDs
    
    private enum HotkeyID: Int {
        case togglePanel = 1
        case logDistraction = 2
        case startIntention = 3
    }
    
    // MARK: - Key Codes
    
    private enum KeyCode: UInt32 {
        case space = 49
        case d = 2
        case i = 34
        case s = 1
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    deinit {
        unregisterHotkeys()
    }
    
    // MARK: - Registration
    
    /// Register all global hotkeys
    func registerHotkeys() {
        guard eventHandler == nil else { return } // Already registered
        
        // Register event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            guard result == noErr else { return OSStatus(result) }
            
            let id = Int(hotKeyID.id)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            
            DispatchQueue.main.async {
                manager.registeredHotkeys[id]?()
            }
            
            return noErr
        }
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        
        guard handlerResult == noErr else {
            print("Failed to install event handler: \(handlerResult)")
            return
        }
        
        // Register individual hotkeys
        registerHotkey(
            keyCode: KeyCode.space.rawValue,
            modifiers: cmdKey + shiftKey,
            id: HotkeyID.togglePanel.rawValue,
            action: { [weak self] in
                self?.onTogglePanel?()
            }
        )
        
        registerHotkey(
            keyCode: KeyCode.d.rawValue,
            modifiers: cmdKey + shiftKey,
            id: HotkeyID.logDistraction.rawValue,
            action: { [weak self] in
                self?.onLogDistraction?()
            }
        )
        
        registerHotkey(
            keyCode: KeyCode.i.rawValue,
            modifiers: cmdKey + shiftKey,
            id: HotkeyID.startIntention.rawValue,
            action: { [weak self] in
                self?.onStartIntention?()
            }
        )
    }
    
    /// Unregister all hotkeys and clean up
    func unregisterHotkeys() {
        // Unregister individual hotkeys
        for (_, hotkeyRef) in hotkeyIDs {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyIDs.removeAll()
        registeredHotkeys.removeAll()
        
        // Remove event handler
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func registerHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: Int,
        action: @escaping () -> Void
    ) {
        var hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("Stdy")), id: UInt32(id))
        var hotKeyRef: EventHotKeyRef?
        
        let result = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard result == noErr else {
            print("Failed to register hotkey \(id): \(result)")
            return
        }
        
        registeredHotkeys[id] = action
        hotkeyIDs[id] = hotKeyRef
        
        print("Registered hotkey \(id): key=\(keyCode), mods=\(modifiers)")
    }
    
    /// Helper to convert 4-char string to OSType
    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.prefix(4).utf8 {
            result = (result << 8) + UInt32(char)
        }
        return result
    }
    
    // MARK: - Helper Methods
    
    /// Check if accessibility permissions are granted (required for global hotkeys)
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Request accessibility permissions
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Get human-readable description of registered hotkeys
    func getHotkeyDescriptions() -> [(id: Int, shortcut: String, action: String)] {
        return [
            (HotkeyID.togglePanel.rawValue, "⌘⇧Space", "Toggle Panel"),
            (HotkeyID.logDistraction.rawValue, "⌘⇧D", "Log Distraction"),
            (HotkeyID.startIntention.rawValue, "⌘⇧I", "Start Intention")
        ]
    }
}

// MARK: - AppKit Integration Alternative

#if canImport(AppKit)
import AppKit

extension HotkeyManager {
    
    /// Alternative registration using NSEvent global monitors
    /// More reliable but requires app to be active for local shortcuts
    func registerLocalHotkeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = UInt32(event.keyCode)
            
            // Check for Cmd+Shift+Space
            if modifiers == [.command, .shift] && keyCode == KeyCode.space.rawValue {
                self.onTogglePanel?()
                return nil // Consume the event
            }
            
            // Check for Cmd+Shift+D
            if modifiers == [.command, .shift] && keyCode == KeyCode.d.rawValue {
                self.onLogDistraction?()
                return nil
            }
            
            // Check for Cmd+Shift+I
            if modifiers == [.command, .shift] && keyCode == KeyCode.i.rawValue {
                self.onStartIntention?()
                return nil
            }
            
            return event
        }
    }
}
#endif
