import Foundation
import ApplicationServices

enum AXBrowser {
    case chrome, safari, brave, arc, edge, firefox, unknown
    
    init(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.google.Chrome", "com.google.Chrome.canary":
            self = .chrome
        case "com.apple.Safari":
            self = .safari
        case "com.brave.Browser":
            self = .brave
        case "company.thebrowser.Browser":
            self = .arc
        case "com.microsoft.edgemac":
            self = .edge
        case "org.mozilla.firefox":
            self = .firefox
        default:
            self = .unknown
        }
    }
    
    var isChromiumBased: Bool {
        switch self {
        case .chrome, .brave, .arc, .edge:
            return true
        default:
            return false
        }
    }
}

struct AXHelpers {
    
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false] as CFDictionary)
    }
    
    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)
    }
    
    static func getFrontmostBrowserPID() -> pid_t? {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        guard let bundleId = frontmostApp?.bundleIdentifier else { return nil }
        
        let browser = AXBrowser(bundleIdentifier: bundleId)
        guard browser != .unknown else { return nil }
        
        return frontmostApp?.processIdentifier
    }
    
    static func readURLFromChrome(pid: pid_t) -> (url: String, title: String)? {
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try to find the focused UI element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            // Fallback: try to find the frontmost window
            var frontWindow: AnyObject?
            AXUIElementCopyAttributeValue(appElement, kAXFrontmostAttribute as CFString, &frontWindow)
            
            // Try alternative approaches
            return readURLFromChromeViaAppleScript(pid: pid)
        }
        
        // Try to get URL from the element
        var urlValue: AnyObject?
        let urlResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            "AXURL" as CFString,
            &urlValue
        )
        
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        
        let url = urlValue as? String ?? ""
        let title = titleValue as? String ?? ""
        
        guard !url.isEmpty else { return nil }
        return (url, title)
    }
    
    static func readURLFromSafari() -> (url: String, title: String)? {
        let script = """
        tell application "Safari"
            if it is running then
                try
                    set currentURL to URL of current tab of front window
                    set pageTitle to name of current tab of front window
                    return currentURL & "\t" & pageTitle
                on error
                    return ""
                end try
            else
                return ""
            end if
        end tell
        """
        
        var errorInfo: NSDictionary?
        if let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo),
           let stringResult = result.stringValue {
            let components = stringResult.split(separator: "\t", maxSplits: 1)
            if components.count == 2 {
                return (String(components[0]), String(components[1]))
            }
        }
        return nil
    }
    
    static func readURLFromFirefox(pid: pid_t) -> (url: String, title: String)? {
        // Firefox uses a different accessibility structure
        // This is a simplified implementation
        return readURLFromFirefoxViaAppleScript()
    }
    
    static func readURLFromChromeViaAppleScript(pid: pid_t) -> (url: String, title: String)? {
        let script = """
        tell application "Google Chrome"
            if it is running then
                try
                    set currentURL to URL of active tab of front window
                    set pageTitle to title of active tab of front window
                    return currentURL & "\t" & pageTitle
                on error
                    return ""
                end try
            else
                return ""
            end if
        end tell
        """
        
        var errorInfo: NSDictionary?
        if let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo),
           let stringResult = result.stringValue {
            let components = stringResult.split(separator: "\t", maxSplits: 1)
            if components.count == 2 {
                return (String(components[0]), String(components[1]))
            }
        }
        return nil
    }
    
    static func readURLFromFirefoxViaAppleScript() -> (url: String, title: String)? {
        let script = """
        tell application "Firefox"
            if it is running then
                try
                    set currentURL to «class curl» of window 1 as string
                    set pageTitle to name of window 1
                    return currentURL & "\t" & pageTitle
                on error
                    return ""
                end try
            else
                return ""
            end if
        end tell
        """
        
        var errorInfo: NSDictionary?
        if let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo),
           let stringResult = result.stringValue {
            let components = stringResult.split(separator: "\t", maxSplits: 1)
            if components.count == 2 {
                return (String(components[0]), String(components[1]))
            }
        }
        return nil
    }
    
    static func getAXValue<T>(element: AXUIElement, attribute: String, type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        guard result == .success else { return nil }
        return value as? T
    }
}
