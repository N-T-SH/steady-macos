import Foundation
import AppKit
import ApplicationServices

enum AXBrowser: CustomStringConvertible {
    case chrome, safari, brave, arc, edge, firefox, unknown

    init(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.google.Chrome", "com.google.Chrome.canary":
            self = .chrome
        case "com.apple.Safari":
            self = .safari
        case "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly":
            self = .brave
        case "company.thebrowser.Browser":
            self = .arc
        case "com.microsoft.edgemac", "com.microsoft.edgemac.Beta":
            self = .edge
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            self = .firefox
        default:
            self = .unknown
        }
    }

    var description: String {
        switch self {
        case .chrome:  return "Chrome"
        case .safari:  return "Safari"
        case .brave:   return "Brave"
        case .arc:     return "Arc"
        case .edge:    return "Edge"
        case .firefox: return "Firefox"
        case .unknown: return "unknown"
        }
    }

    var isChromiumBased: Bool {
        switch self {
        case .chrome, .brave, .arc, .edge: return true
        default: return false
        }
    }

    /// The exact application name used in AppleScript `tell application "..."`.
    var appleScriptName: String? {
        switch self {
        case .chrome:  return "Google Chrome"
        case .brave:   return "Brave Browser"
        case .arc:     return "Arc"
        case .edge:    return "Microsoft Edge"
        case .safari:  return "Safari"
        case .firefox: return "Firefox"
        case .unknown: return nil
        }
    }
}

struct AXHelpers {

    static func clearAwakenedPID(_ pid: pid_t) {
        awakenedPIDs.remove(pid)
    }

    static func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
    }

    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    static func getFrontmostBrowserPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return nil }
        let browser = AXBrowser(bundleIdentifier: bundleId)
        guard browser != .unknown else { return nil }
        return app.processIdentifier
    }

    /// Primary entry point — reads the active tab URL from whichever browser is frontmost.
    /// Tries AX tree traversal first (Accessibility permission only, no Automation needed),
    /// then falls back to AppleScript if AX yields nothing.
    static func readCurrentURL(browser: AXBrowser, pid: pid_t) -> (url: String, title: String)? {
        switch browser {
        case .safari:
            // Safari: try AX first, then AppleScript
            return readURLViaAXTree(pid: pid)
                ?? readViaAppleScript(appName: "Safari", script: safariScript())
        case .firefox:
            return readViaAppleScript(appName: "Firefox", script: firefoxScript())
        case .chrome, .brave, .arc, .edge:
            // Primary: AX tree traversal — only needs Accessibility permission
            if let result = readURLViaAXTree(pid: pid) { return result }
            // Fallback: AppleScript (requires Automation permission for the browser)
            if let name = browser.appleScriptName {
                return readViaAppleScript(appName: name, script: chromiumScript(appName: name))
            }
            return nil
        case .unknown:
            return nil
        }
    }

    // MARK: - AppleScript helpers

    private static func readViaAppleScript(appName: String, script: String) -> (url: String, title: String)? {
        // NSAppleScript must run on the main thread for Carbon event loop reliability.
        // Use sync dispatch; callers are always on a background actor thread.
        var output: (url: String, title: String)?
        let block = {
            var errorInfo: NSDictionary?
            guard let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo),
                  let raw = result.stringValue, !raw.isEmpty else {
                if let err = errorInfo {
                    let code = err["NSAppleScriptErrorNumber"] as? Int ?? 0
                    let msg  = err["NSAppleScriptErrorBriefMessage"] as? String ?? "\(err)"
                    if code == -1743 {
                        print("[AXHelpers] ⚠️  Automation permission denied for \(appName). " +
                              "Go to System Settings → Privacy & Security → Automation " +
                              "and enable Steady → \(appName).")
                    } else {
                        print("[AXHelpers] AppleScript error \(code) for \(appName): \(msg)")
                    }
                } else {
                    print("[AXHelpers] AppleScript returned empty result for \(appName)")
                }
                return
            }
            // Split on tab character
            let parts = raw.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else {
                print("[AXHelpers] AppleScript result had no tab separator for \(appName): '\(raw.prefix(80))'")
                return
            }
            let url   = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard url.hasPrefix("http") else {
                print("[AXHelpers] AppleScript URL not HTTP for \(appName): '\(url.prefix(80))'")
                return
            }
            output = (url, title)
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync { block() }
        }
        return output
    }

    private static func chromiumScript(appName: String) -> String {
        """
        tell application "\(appName)"
            if it is running then
                try
                    set t to active tab of front window
                    return (URL of t) & "\t" & (title of t)
                on error e
                    return ""
                end try
            end if
            return ""
        end tell
        """
    }

    private static func safariScript() -> String {
        """
        tell application "Safari"
            if it is running then
                try
                    set t to current tab of front window
                    return (URL of t) & "\t" & (name of t)
                on error
                    return ""
                end try
            end if
            return ""
        end tell
        """
    }

    private static func firefoxScript() -> String {
        """
        tell application "Firefox"
            if it is running then
                try
                    set w to window 1
                    set currentURL to «class curl» of w as string
                    set pageTitle to name of w
                    return currentURL & "\t" & pageTitle
                on error
                    return ""
                end try
            end if
            return ""
        end tell
        """
    }

    // MARK: - AX tree traversal (Accessibility permission only, no Automation needed)

    /// PIDs we've already sent the AX wake signal to, so we don't repeat it every poll.
    private static var awakenedPIDs = Set<pid_t>()

    /// Walks the AX tree of the browser process to find the address bar URL.
    /// Works for Chrome, Arc, Brave, Edge, Safari without requiring Automation permission.
    static func readURLViaAXTree(pid: pid_t) -> (url: String, title: String)? {
        let app = AXUIElementCreateApplication(pid)

        // Quick trust check
        var roleRef: AnyObject?
        let trustCheck = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &roleRef)
        if trustCheck != .success {
            switch trustCheck.rawValue {
            case -25211:
                print("[AXHelpers] AX: permission NOT granted (apiDisabled). " +
                      "Remove and re-add Steady in System Settings → Privacy → Accessibility.")
            case -25204:
                // cannotComplete = Chrome's accessibility tree is dormant.
                // Setting AXEnhancedUserInterface wakes it up; the next poll will succeed.
                if !awakenedPIDs.contains(pid) {
                    awakenedPIDs.insert(pid)
                    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                    print("[AXHelpers] AX: Chrome accessibility was dormant — sent wake signal. " +
                          "Will read URL on next poll (~10s).")
                }
            default:
                print("[AXHelpers] AX: kAXRole failed with error \(trustCheck.rawValue)")
            }
            return nil
        }

        // Get the frontmost window
        var window: AXUIElement?

        var focusedRef: AnyObject?
        let focusedErr = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef)
        if focusedErr == .success, let el = focusedRef {
            window = (el as! AXUIElement)
            print("[AXHelpers] AX: got focused window")
        } else {
            print("[AXHelpers] AX: kAXFocusedWindow error \(focusedErr.rawValue), trying kAXWindows")
            var windowsRef: AnyObject?
            let wErr = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
            if wErr == .success, let wins = windowsRef as? [AXUIElement], let first = wins.first {
                window = first
                print("[AXHelpers] AX: got first window from kAXWindows list (\(wins.count) total)")
            } else {
                print("[AXHelpers] AX: kAXWindows error \(wErr.rawValue), count=\((windowsRef as? [AXUIElement])?.count ?? -1)")
                return nil
            }
        }

        guard let win = window else {
            print("[AXHelpers] AX: window ref is nil after both attempts")
            return nil
        }

        // Get window title (used as page title fallback)
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
        let windowTitle = titleRef as? String ?? ""
        print("[AXHelpers] AX: window title='\(windowTitle.prefix(60))'")

        // 1. Try kAXDocumentAttribute — Chrome/Safari expose the current URL here
        var docRef: AnyObject?
        let docErr = AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &docRef)
        if docErr == .success, let urlStr = docRef as? String, urlStr.hasPrefix("http") {
            print("[AXHelpers] AX: got URL via kAXDocument: \(urlStr.prefix(80))")
            return (urlStr, windowTitle)
        }
        print("[AXHelpers] AX: kAXDocument err=\(docErr.rawValue) val='\((docRef as? String ?? "nil").prefix(60))'")

        // 2. Search toolbar for a text field containing an HTTP URL
        if let url = findAddressBarURL(in: win) {
            print("[AXHelpers] AX: got URL via address bar search: \(url.prefix(80))")
            return (url, windowTitle)
        }

        print("[AXHelpers] AX: tree traversal found no URL")
        return nil
    }

    /// Recursively searches for an AXTextField or AXComboBox whose value looks like an HTTP URL.
    /// Stays shallow (toolbar area) to avoid scanning the entire webpage AX tree.
    private static func findAddressBarURL(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            // Skip the web content area entirely — the URL won't be in there and it's huge
            var subroleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String ?? ""
            if role == "AXScrollArea" || subrole == "AXWebAreaRole" { continue }

            // Check text fields and combo boxes for HTTP URLs
            if role == kAXTextFieldRole as String || role == "AXComboBox" {
                var valueRef: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
                if let val = valueRef as? String, val.hasPrefix("http") {
                    return val
                }
            }

            // Recurse into non-web children
            if let url = findAddressBarURL(in: child, depth: depth + 1) {
                return url
            }
        }
        return nil
    }

    // MARK: - Kept for any remaining callers

    static func readURLFromSafari() -> (url: String, title: String)? {
        readViaAppleScript(appName: "Safari", script: safariScript())
    }

    static func readURLFromChrome(pid: pid_t) -> (url: String, title: String)? {
        readURLViaAXTree(pid: pid)
    }

    static func readURLFromFirefox(pid: pid_t) -> (url: String, title: String)? {
        readViaAppleScript(appName: "Firefox", script: firefoxScript())
    }

    static func getAXValue<T>(element: AXUIElement, attribute: String, type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }
}
