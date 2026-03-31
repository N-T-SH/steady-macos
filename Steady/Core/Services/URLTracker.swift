import Foundation
import ApplicationServices

protocol URLTrackerDelegate: AnyObject {
    func urlTracker(_ tracker: URLTracker, didDetectURL url: String, title: String)
    func urlTracker(_ tracker: URLTracker, didDetectOffTask classification: URLClassification)
    func urlTrackerDidLosePermission(_ tracker: URLTracker)
}

actor URLTracker {
    weak var delegate: URLTrackerDelegate?
    
    private var timer: Timer?
    private var lastURL: String?
    private var driftStartTime: Date?
    private var llmProvider: LLMProvider?
    private var currentIntention: Intention?
    
    var isTracking: Bool = false
    var pollingInterval: TimeInterval = 10.0
    var gracePeriod: TimeInterval = 120.0 // 2 minutes
    
    func startTracking(intention: Intention, llmProvider: LLMProvider) {
        self.currentIntention = intention
        self.llmProvider = llmProvider
        self.isTracking = true
        
        // Check permission first
        if !AXHelpers.checkAccessibilityPermission() {
            delegate?.urlTrackerDidLosePermission(self)
            return
        }
        
        // Start polling timer
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.pollCurrentURL()
            }
        }
        
        // Immediate first poll
        Task {
            await pollCurrentURL()
        }
    }
    
    func stopTracking() {
        isTracking = false
        timer?.invalidate()
        timer = nil
        lastURL = nil
        driftStartTime = nil
    }
    
    func checkPermission() -> Bool {
        return AXHelpers.checkAccessibilityPermission()
    }
    
    private func pollCurrentURL() {
        guard isTracking else { return }
        guard let pid = AXHelpers.getFrontmostBrowserPID() else { return }
        
        // Check permission again
        if !AXHelpers.checkAccessibilityPermission() {
            delegate?.urlTrackerDidLosePermission(self)
            stopTracking()
            return
        }
        
        let browser = AXBrowser(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        
        var result: (url: String, title: String)?
        
        switch browser {
        case .chrome, .brave, .arc, .edge:
            result = AXHelpers.readURLFromChrome(pid: pid)
        case .safari:
            result = AXHelpers.readURLFromSafari()
        case .firefox:
            result = AXHelpers.readURLFromFirefox(pid: pid)
        default:
            return
        }
        
        guard let (url, title) = result else { return }
        
        // Notify delegate of detected URL
        delegate?.urlTracker(self, didDetectURL: url, title: title)
        
        // Check if URL changed
        if url != lastURL {
            lastURL = url
            driftStartTime = nil
            
            // Classify the new URL
            Task {
                await classifyAndNotify(url: url, title: title)
            }
        }
    }
    
    private func classifyAndNotify(url: String, title: String) async {
        guard let llmProvider = llmProvider,
              let intention = currentIntention else { return }
        
        do {
            let classification = try await llmProvider.classifyURL(
                url: url,
                pageTitle: title,
                intention: intention
            )
            
            if !classification.onTask {
                // Start drift tracking
                if driftStartTime == nil {
                    driftStartTime = Date()
                }
                
                let driftDuration = Date().timeIntervalSince(driftStartTime!)
                
                // Only notify if drift exceeds grace period
                if driftDuration > gracePeriod {
                    delegate?.urlTracker(self, didDetectOffTask: classification)
                }
            } else {
                // Reset drift tracking when back on task
                driftStartTime = nil
            }
        } catch {
            print("URL classification error: \(error)")
        }
    }
}
