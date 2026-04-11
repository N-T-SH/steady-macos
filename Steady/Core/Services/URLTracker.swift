import Foundation

protocol URLTrackerDelegate: AnyObject {
    func urlTracker(_ tracker: URLTracker, didDetectURL url: String, title: String)
    func urlTracker(_ tracker: URLTracker, didClassifyURL classification: URLClassification)
    func urlTracker(_ tracker: URLTracker, didDetectOffTask classification: URLClassification)
    func urlTracker(_ tracker: URLTracker, didDiscoverNewRule domain: String, projectName: String, category: URLCategory)
    func urlTracker(_ tracker: URLTracker, didUpdateActivityWatchStatus available: Bool)
}

actor URLTracker {
    weak var delegate: URLTrackerDelegate?

    private var timer: Timer?
    private var lastActivityKey: String?    // dedup: url for web, "app://App|title" for native
    private var driftStartTime: Date?
    private var llmProvider: LLMProvider?
    private var currentIntention: Intention?
    private var knownRules: [URLRule] = []
    private var knownProjects: [String] = []
    /// Maps project name → TaskStatus derived from user-assigned project categories.
    private var projectStatusMap: [String: TaskStatus] = [:]
    /// Maps URLCategory rawValue → user-overridden TaskStatus.
    private var urlCategoryOverrideMap: [String: TaskStatus] = [:]

    // ActivityWatch bucket cache
    private var awWebBuckets: [String] = []
    private var awWindowBucket: String? = nil
    private var awBucketsLoadedAt: Date = .distantPast
    private var awAvailable: Bool? = nil

    private let awSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 2.0
        cfg.timeoutIntervalForResource = 2.0
        return URLSession(configuration: cfg)
    }()

    var isTracking: Bool = false
    var pollingInterval: TimeInterval = 10.0
    var gracePeriod: TimeInterval = 120.0

    func setDelegate(_ delegate: URLTrackerDelegate?) {
        self.delegate = delegate
    }

    func updateKnownRules(_ rules: [URLRule]) {
        self.knownRules = rules
    }

    func updateKnownProjects(_ projects: [String]) {
        self.knownProjects = projects
    }

    func updateProjectCategories(_ categories: [ProjectCategory], assignments: [String: String],
                                  urlCategoryOverrides: [String: TaskStatus] = [:]) {
        var map: [String: TaskStatus] = [:]
        for (project, catName) in assignments {
            if let cat = categories.first(where: { $0.name == catName }) {
                // Custom category
                map[project] = cat.status
            } else if let urlCat = URLCategory(rawValue: catName) {
                // URLCategory rawValue — respect any user override for that category
                map[project] = urlCategoryOverrides[catName] ?? urlCat.defaultTaskStatus
            }
        }
        self.projectStatusMap        = map
        self.urlCategoryOverrideMap  = urlCategoryOverrides
    }

    func updateIntention(_ intention: Intention?) {
        self.currentIntention = intention
        if intention == nil { driftStartTime = nil }
    }

    func startTracking(llmProvider: LLMProvider, knownRules: [URLRule] = [], knownProjects: [String] = []) {
        guard !isTracking else {
            print("[URLTracker] already tracking — skipping")
            return
        }
        self.llmProvider = llmProvider
        self.knownRules = knownRules
        self.knownProjects = knownProjects
        self.isTracking = true

        print("[URLTracker] startTracking — ActivityWatch backend (web + window watchers)")

        let interval = pollingInterval
        Task { @MainActor in
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                Task { [weak self] in await self?.pollCurrentActivity() }
            }
            await self.storeTimer(t)
            print("[URLTracker] poll timer scheduled every \(interval)s")
        }

        Task { await pollCurrentActivity() }
    }

    private func storeTimer(_ t: Timer) { timer = t }

    func stopTracking() {
        isTracking = false
        timer?.invalidate()
        timer = nil
        lastActivityKey = nil
        driftStartTime = nil
    }

    // MARK: - Poll

    private func pollCurrentActivity() async {
        guard isTracking else { return }
        guard let result = await pollViaActivityWatch() else { return }
        handleNewActivity(url: result.url, title: result.title)
    }

    private func handleNewActivity(url: String, title: String) {
        // Deduplicate: web events by URL, app events by url+title (window switches matter)
        let key = url.hasPrefix("app://") ? "\(url)|\(title)" : url
        delegate?.urlTracker(self, didDetectURL: url, title: title)
        guard key != lastActivityKey else { return }
        lastActivityKey = key
        driftStartTime = nil
        print("[URLTracker] new activity: \(url.prefix(80)) | \(title.prefix(60))")
        Task { await classifyAndNotify(url: url, title: title) }
    }

    // MARK: - ActivityWatch

    private var awLastFailedAt: Date? = nil
    private let awFailureBackoff: TimeInterval = 60.0  // poll every 60s when AW is down

    private func pollViaActivityWatch() async -> (url: String, title: String)? {
        // When AW is known unavailable, back off to reduce connection-refused noise
        if awAvailable == false, let lastFail = awLastFailedAt,
           Date().timeIntervalSince(lastFail) < awFailureBackoff {
            return nil
        }

        // Refresh bucket list every 5 minutes
        let needsRefresh = (awWebBuckets.isEmpty && awWindowBucket == nil)
            || Date().timeIntervalSince(awBucketsLoadedAt) > 300
        if needsRefresh {
            guard let buckets = await fetchAWBuckets() else {
                awLastFailedAt = Date()
                if awAvailable != false {
                    awAvailable = false
                    delegate?.urlTracker(self, didUpdateActivityWatchStatus: false)
                    print("[URLTracker] ActivityWatch not running. Install from https://activitywatch.net and install the browser extension.")
                }
                return nil
            }
            awWebBuckets = buckets.web
            awWindowBucket = buckets.window
            awBucketsLoadedAt = Date()
            if awAvailable != true {
                awAvailable = true
                awLastFailedAt = nil
                delegate?.urlTracker(self, didUpdateActivityWatchStatus: true)
                print("[URLTracker] ActivityWatch connected — \(buckets.web.count) web bucket(s), window: \(buckets.window ?? "none")")
            }
        }

        // Fetch latest window event to know which app is active
        let windowEvent = awWindowBucket.flatMap { _ in () } != nil
            ? await fetchLatestWindowEvent(bucket: awWindowBucket!)
            : nil

        // Fetch latest web event across all web buckets
        var latestWeb: (url: String, title: String, ts: Date)? = nil
        for bucket in awWebBuckets {
            guard let ev = await fetchLatestWebEvent(bucket: bucket) else { continue }
            if latestWeb == nil || ev.ts > latestWeb!.ts { latestWeb = ev }
        }

        if let win = windowEvent {
            if isBrowserApp(win.appName) {
                // Active app is a browser — use the web event's URL if available
                if let web = latestWeb { return (web.url, web.title) }
            } else {
                // Active app is a native app — synthesize an app:// activity
                let encoded = win.appName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? win.appName
                return ("app://\(encoded)", win.windowTitle)
            }
        }

        // Fallback: whatever web event we have
        return latestWeb.map { ($0.url, $0.title) }
    }

    private let browserApps: Set<String> = [
        "Google Chrome", "Chrome", "Chromium",
        "Safari", "Firefox", "Firefox Developer Edition",
        "Brave Browser", "Arc", "Microsoft Edge",
        "Opera", "Vivaldi", "Waterfox"
    ]

    private func isBrowserApp(_ name: String) -> Bool {
        browserApps.contains(name)
    }

    private func fetchAWBuckets() async -> (web: [String], window: String?)? {
        guard let url = URL(string: "http://localhost:5600/api/0/buckets/") else { return nil }
        do {
            let (data, resp) = try await awSession.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let keys = dict.keys.sorted()
            let web = keys.filter { $0.contains("aw-watcher-web") }
            let window = keys.first { $0.contains("aw-watcher-window") }
            guard !web.isEmpty || window != nil else { return nil }
            return (web, window)
        } catch { return nil }
    }

    private func fetchLatestWebEvent(bucket: String) async -> (url: String, title: String, ts: Date)? {
        guard let endpoint = URL(string: "http://localhost:5600/api/0/buckets/\(bucket)/events?limit=1") else { return nil }
        do {
            let (data, resp) = try await awSession.data(from: endpoint)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let events = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let ev = events.first,
                  let evData = ev["data"] as? [String: Any],
                  let pageURL = evData["url"] as? String,
                  pageURL.hasPrefix("http"),
                  let timestamp = ev["timestamp"] as? String else { return nil }
            let title = evData["title"] as? String ?? ""
            let ts = ISO8601DateFormatter.shared.date(from: timestamp) ?? .distantPast
            return (pageURL, title, ts)
        } catch {
            print("[URLTracker] AW web parse error (\(bucket)): \(error)")
            return nil
        }
    }

    private func fetchLatestWindowEvent(bucket: String) async -> (appName: String, windowTitle: String, ts: Date)? {
        guard let endpoint = URL(string: "http://localhost:5600/api/0/buckets/\(bucket)/events?limit=1") else { return nil }
        do {
            let (data, resp) = try await awSession.data(from: endpoint)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let events = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let ev = events.first,
                  let evData = ev["data"] as? [String: Any],
                  let appName = evData["app"] as? String,
                  let timestamp = ev["timestamp"] as? String else { return nil }
            let title = evData["title"] as? String ?? ""
            let ts = ISO8601DateFormatter.shared.date(from: timestamp) ?? .distantPast
            return (appName, title, ts)
        } catch {
            print("[URLTracker] AW window parse error: \(error)")
            return nil
        }
    }

    // MARK: - Classification

    private func classifyAndNotify(url: String, title: String) async {
        // Rule lookup key: host for web URLs, full app:// for native apps
        let ruleKey = url.hasPrefix("app://")
            ? url
            : (URL(string: url)?.host ?? url)

        if let rule = knownRules.first(where: { $0.domain == ruleKey }) {
            // Priority: project assignment → URL category override → hardcoded default
            let taskStatus = projectStatusMap[rule.projectName]
                ?? urlCategoryOverrideMap[rule.category.rawValue]
                ?? rule.category.defaultTaskStatus
            let classification = URLClassification(
                url: url, pageTitle: title,
                taskStatus: taskStatus,
                project: rule.projectName,
                category: rule.category,
                confidence: 1.0,
                reasoning: "Matched saved rule",
                timestamp: Date()
            )
            delegate?.urlTracker(self, didClassifyURL: classification)
            if taskStatus == .onTask { driftStartTime = nil }
            return
        }

        guard let llmProvider = llmProvider else { return }

        do {
            let classification = try await llmProvider.classifyActivity(
                url: url, title: title,
                intention: currentIntention,
                knownRules: knownRules,
                knownProjects: knownProjects
            )
            // Apply 3-level priority: project assignment → URL category override → LLM result
            let effectiveStatus = classification.project.flatMap { projectStatusMap[$0] }
                ?? urlCategoryOverrideMap[classification.category.rawValue]
                ?? classification.taskStatus
            let finalClassification: URLClassification
            if effectiveStatus != classification.taskStatus {
                finalClassification = URLClassification(
                    url: classification.url, pageTitle: classification.pageTitle,
                    taskStatus: effectiveStatus,
                    project: classification.project, category: classification.category,
                    confidence: classification.confidence, reasoning: classification.reasoning,
                    timestamp: classification.timestamp
                )
            } else {
                finalClassification = classification
            }

            delegate?.urlTracker(self, didClassifyURL: finalClassification)

            if let project = finalClassification.project, !project.isEmpty {
                delegate?.urlTracker(self, didDiscoverNewRule: ruleKey, projectName: project, category: finalClassification.category)
            }

            if currentIntention != nil && !finalClassification.onTask {
                if driftStartTime == nil { driftStartTime = Date() }
                if Date().timeIntervalSince(driftStartTime!) > gracePeriod {
                    delegate?.urlTracker(self, didDetectOffTask: finalClassification)
                }
            } else {
                driftStartTime = nil
            }
        } catch {
            print("[URLTracker] classification error: \(error)")
        }
    }
}

// MARK: - ISO8601 helper

private extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
