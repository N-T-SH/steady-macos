import Foundation

enum LLMError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(Error)
    case apiError(String)
    case noAPIKey
}

struct LLMResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

actor LLMProvider {
    private let config: LLMConfig
    private let urlSession: URLSession

    init(config: LLMConfig, urlSession: URLSession = URLSession.shared) {
        self.config = config
        self.urlSession = urlSession
    }

    /// Merges stored config with live UserDefaults values so settings
    /// changes take effect immediately without an app restart.
    private var liveConfig: LLMConfig {
        let ud = UserDefaults.standard
        var c = config
        if let v = ud.string(forKey: "llm.providerURL"), !v.isEmpty       { c.providerURL = v }
        if let v = ud.string(forKey: "llm.conversationModel"), !v.isEmpty  { c.conversationModel = v }
        if let v = ud.string(forKey: "llm.classificationModel"), !v.isEmpty { c.classificationModel = v }
        return c
    }
    
    // MARK: - Infographic generation

    func generateInfographic(stats: FocusStats) async throws -> InfographicSpec {
        let live = liveConfig
        guard let apiKey = try? KeychainHelper.load(key: live.apiKeyIdentifier) else {
            throw LLMError.noAPIKey
        }

        let recentDots = stats.recentChecks.map { s -> String in
            switch s { case .onTask: return "●"; case .drift: return "◐"; case .goofingOff: return "○" }
        }.joined(separator: "")
        let prompt = """
        You are generating a small header card for a macOS focus-productivity app called Steady. \
        The card replaces the app logo/name — it must be informative, motivating, and fit in a single short row (≈50 px tall). \
        No markdown. No prose. Return ONLY valid JSON.

        Current user stats:
        - Total activity events today: \(stats.totalEvents)
        - On-task: \(stats.onTaskEvents)/\(stats.totalEvents) (\(stats.onTaskPercent)%), Drift: \(stats.driftEvents), Goofing off: \(stats.goofingOffEvents)
        - Estimated focus time: \(stats.focusMinutes) min
        - Sessions today: \(stats.sessionCount)
        - Longest focus block: \(stats.longestBlockMinutes) min
        - Top project: \(stats.topProject ?? "none")
        - Top category: \(stats.topCategory ?? "unknown")
        - Current session duration: \(stats.currentSessionMinutes.map { "\($0) min" } ?? "no active session")
        - Time of day: \(stats.timeOfDay)
        - Minutes since last distraction: \(stats.minutesSinceLastDistraction.map { "\($0)" } ?? "n/a")
        - Last 10 checks (oldest→newest): \(recentDots.isEmpty ? "no data yet" : recentDots)

        Pick the SINGLE most interesting / motivating card from this list of 20+ concepts. \
        Vary your choice — do not always default to focus_time. Consider what is most relevant \
        given the time of day, session state, and recent trend:

        1.  focus_time_today        — total focus minutes today as a big stat
        2.  on_task_percent         — on-task % as a big stat with trend note in subtitle
        3.  longest_block           — longest uninterrupted focus block
        4.  session_count           — number of sessions completed today
        5.  top_project             — most-worked project + time estimate in subtitle
        6.  distraction_count       — off-task events; frame positively if low
        7.  streak_note             — encouraging note about today's consistency
        8.  quiet_hours             — time since last distraction as a big stat
        9.  deep_work_time          — time in coding/design/research specifically
        10. momentum_dots           — last 10 checks as colored dots with a short label
        11. focus_split_bar         — focus vs drift horizontal bar
        12. multi_quick             — 3 small stats: focus time, on-task %, sessions
        13. project_time_pair       — labelValue: top project + time on it
        14. session_progress        — current session time + intention label in subtitle
        15. daily_comparison        — compare today's % to a contextual benchmark
        16. category_highlight      — dominant category today (e.g. "Mostly coding")
        17. morning_warmup          — if early in day and few events, encourage getting started
        18. afternoon_check         — if afternoon, summarise morning in a multiStat
        19. distraction_resilience  — how quickly user returns after going off-task
        20. focus_quality_bar       — bar split by on-task categories vs off-task
        21. event_count             — total events with on-task count in subtitle
        22. best_hour               — most productive recent check as a note
        23. encouragement           — best stat of the day, warmly framed
        24. project_split_bar       — time split across top 2 projects (if data exists)
        25. zero_distractions       — celebrate if distractionCount == 0

        Output format — pick ONE cardType and fill only its fields. Omit unused fields entirely.

        stat:
        {"cardType":"stat","label":"<3–4 word label>","value":"<concise value>","subtitle":"<optional 1-line note>","accent":"green"|"purple"|"red"|null}

        multiStat (2–3 items):
        {"cardType":"multiStat","items":[{"label":"<label>","value":"<value>"},…]}

        barSplit (2–3 segments, ratios must sum to 1.0):
        {"cardType":"barSplit","barTitle":"<short title>","segments":[{"label":"<l>","ratio":<r>,"color":"green"|"purple"|"red"|"gray"},…]}

        dotRow (up to 12 dots):
        {"cardType":"dotRow","dotTitle":"<short title>","dots":["green"|"purple"|"red"|"gray",…]}

        labelValue (exactly 2 rows):
        {"cardType":"labelValue","rows":[{"label":"<l>","value":"<v>"},{"label":"<l>","value":"<v>"}]}

        Rules:
        - All text must be short: labels ≤ 15 chars, values ≤ 10 chars, subtitle ≤ 40 chars.
        - Use "green" for positive stats, "purple" for drift/warnings, "red" for goofing-off nudges.
        - If there is no activity data yet, use concept 17 (morning_warmup) with a stat card.
        - Return ONLY the JSON object. No explanation, no markdown fences.
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": "You output only valid JSON. No prose, no markdown."],
            ["role": "user", "content": prompt]
        ]

        let model = live.classificationModel.isEmpty ? live.conversationModel : live.classificationModel
        guard !model.isEmpty else { throw LLMError.noAPIKey }

        let data = try await makeRequest(
            model: model, messages: messages, apiKey: apiKey,
            temperature: 0.7, maxTokens: 200
        )
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        let clean = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = clean.data(using: .utf8) else { throw LLMError.invalidResponse }
        return try JSONDecoder().decode(InfographicSpec.self, from: jsonData)
    }

    func extractIntent(from conversationText: String) async throws -> String? {
        let live = liveConfig
        guard let apiKey = try? KeychainHelper.load(key: live.apiKeyIdentifier) else {
            throw LLMError.noAPIKey
        }
        let prompt = """
        Based on this conversation, what specific work task is the user trying to focus on?

        \(conversationText)

        If the user has clearly stated a work task, return ONLY a short task title (2–5 words).
        If the conversation is still casual/unclear, return exactly: unclear
        Return only the task name or "unclear". No punctuation, no quotes.
        """
        let messages: [[String: String]] = [["role": "user", "content": prompt]]
        let model = live.classificationModel.isEmpty ? live.conversationModel : live.classificationModel
        guard !model.isEmpty else { throw LLMError.noAPIKey }
        let data = try await makeRequest(model: model, messages: messages, apiKey: apiKey, temperature: 0.1, maxTokens: 20)
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        let raw = response.choices.first?.message.content ?? "unclear"
        // Take only the first non-empty line — guards against models echoing back the prompt
        let firstLine = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let result = firstLine.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        // Reject if empty, too long (model leaked instructions), or contains prompt fragments
        let tooLong = result.count > 50
        let looksLikePrompt = result.lowercased().hasPrefix("the user") || result.lowercased().contains("work task")
        guard !result.isEmpty, !tooLong, !looksLikePrompt else { return nil }
        return result.lowercased() == "unclear" ? nil : result
    }

    /// Classify any activity — web URL (http://...) or native app (app://AppName).
    func classifyActivity(
        url: String,
        title: String,
        intention: Intention?,
        knownRules: [URLRule] = [],
        knownProjects: [String] = []
    ) async throws -> URLClassification {
        let prompt = buildActivityPrompt(
            url: url, title: title,
            intention: intention,
            knownRules: knownRules,
            knownProjects: knownProjects
        )

        let live = liveConfig
        guard let apiKey = try? KeychainHelper.load(key: live.apiKeyIdentifier) else {
            throw LLMError.noAPIKey
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": "You are an activity classifier for a productivity app. Respond ONLY with valid JSON in the exact format specified."],
            ["role": "user", "content": prompt]
        ]

        let data = try await makeRequest(
            model: live.classificationModel,
            messages: messages,
            apiKey: apiKey,
            temperature: live.temperature,
            maxTokens: live.maxTokens
        )

        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        return try parseClassificationResponse(content, url: url, pageTitle: title)
    }
    
    func generateConversationResponse(
        messages: [ConversationTurn],
        context: ConversationContext
    ) async throws -> String {
        let live = liveConfig
        guard let apiKey = try? KeychainHelper.load(key: live.apiKeyIdentifier) else {
            throw LLMError.noAPIKey
        }

        let systemPrompt = buildConversationSystemPrompt(context: context)

        var messageArray: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for turn in messages {
            let role = turn.role.rawValue
            messageArray.append(["role": role, "content": turn.content])
        }

        let data = try await makeRequest(
            model: live.conversationModel,
            messages: messageArray,
            apiKey: apiKey,
            temperature: live.temperature,
            maxTokens: live.maxTokens
        )
        
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func makeRequest(
        model: String,
        messages: [[String: String]],
        apiKey: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> Data {
        let rawBase = liveConfig.providerURL
        let baseURL = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorResponse["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw LLMError.apiError(message)
                }
                throw LLMError.invalidResponse
            }
            
            return data
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.requestFailed(error)
        }
    }
    
    /// Unified prompt for web URLs (http://…) and native app activity (app://AppName).
    private func buildActivityPrompt(
        url: String,
        title: String,
        intention: Intention?,
        knownRules: [URLRule],
        knownProjects: [String]
    ) -> String {
        let isAppActivity = url.hasPrefix("app://")
        let appName = isAppActivity
            ? (url.replacingOccurrences(of: "app://", with: "").removingPercentEncoding ?? url)
            : nil
        let activityLabel = isAppActivity
            ? "App: \(appName ?? url)\nWindow title: \(title)"
            : "URL: \(url)\nPage title: \(title)"

        var prompt = "Classify this computer activity for a productivity tracker.\n\n"

        // Current focus context
        if let intention = intention {
            prompt += "User's current focus: \"\(intention.task)\""
            if !intention.whyItMatters.isEmpty { prompt += " (\(intention.whyItMatters))" }
            prompt += "\n\n"
        }

        // Known projects (from intentions — named projects the user has worked on)
        let allProjects = Array(Set(knownProjects + knownRules.map { $0.projectName }))
            .filter { !$0.isEmpty }
            .sorted()
        if !allProjects.isEmpty {
            prompt += "User's known projects — assign to one if relevant:\n"
            for p in allProjects.prefix(30) { prompt += "  • \(p)\n" }
            prompt += "\n"
        }

        // Domain/app → project examples from URL rules (user-confirmed assignments)
        let examples = knownRules.prefix(20)
        if !examples.isEmpty {
            prompt += "Past activity mappings (use for reference):\n"
            for rule in examples {
                prompt += "  \(rule.domain) → \(rule.projectName) (\(rule.category.rawValue))\n"
            }
            prompt += "\n"
        }

        prompt += "\(activityLabel)\n\n"

        if let intention = intention {
            prompt += """
            Is this activity on-task for "\(intention.task)"? \
            Assign to an existing project above if it matches, or create a concise new project name. \
            If clearly off-task (social media, news, entertainment), set onTask=false.

            """
        } else {
            prompt += """
            Classify productivity: onTask=true for work/learning (coding, design, research, communication, writing), \
            false for leisure (social media, news, entertainment, gaming). \
            Assign to an existing project above if it clearly matches, or create a concise project name for work activity, \
            or null for clearly unproductive activity.

            """
        }

        prompt += """
        Respond with ONLY a JSON object (no markdown, no code blocks):
        {
            "onTask": true or false,
            "project": "project name or null",
            "category": "one of: coding, design, research, communication, social_media, news, entertainment, other_work, unknown",
            "confidence": 0.0 to 1.0,
            "reasoning": "one sentence"
        }
        """
        return prompt
    }

    private func parseClassificationResponse(_ content: String, url: String, pageTitle: String) throws -> URLClassification {
        let cleanContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        struct ClassificationData: Codable {
            let onTask: Bool
            let project: String?
            let category: String
            let confidence: Double
            let reasoning: String
        }
        
        do {
            let data = cleanContent.data(using: .utf8) ?? Data()
            let classification = try JSONDecoder().decode(ClassificationData.self, from: data)

            let category = URLCategory(rawValue: classification.category) ?? .unknown
            // Use the category's default status, with the LLM's onTask as a tiebreaker
            // for unknown categories (where defaultTaskStatus might be wrong).
            let taskStatus: TaskStatus
            if category == .unknown {
                taskStatus = classification.onTask ? .onTask : .goofingOff
            } else {
                taskStatus = category.defaultTaskStatus
            }

            return URLClassification(
                url: url,
                pageTitle: pageTitle,
                taskStatus: taskStatus,
                project: classification.project,
                category: category,
                confidence: classification.confidence,
                reasoning: classification.reasoning,
                timestamp: Date()
            )
        } catch {
            throw LLMError.decodingFailed(error)
        }
    }
    
    private func buildConversationSystemPrompt(context: ConversationContext) -> String {
        var prompt = """
        You are Steady, a macOS menu bar app and AI companion for intentional, focused work. \
        You track the user's computer activity (browser URLs and active apps) via ActivityWatch \
        and classify it as productive or off-task. Only report activity explicitly listed below — \
        never infer, guess, or fabricate URLs, apps, or sites the user may have visited. \
        If no activity data is listed, say so honestly.
        """

        if let intention = context.intention {
            prompt += "\n\nCurrent focus: \"\(intention.task)\"."
            if !intention.whyItMatters.isEmpty {
                prompt += " Why it matters: \(intention.whyItMatters)."
            }
            prompt += " Strictness: \(intention.strictness.rawValue)."
        } else {
            prompt += "\n\nNo active focus session — the user may be deciding what to work on, or browsing passively."
        }

        if let session = context.session {
            let minutes = Int(Date().timeIntervalSince(session.startTime) / 60)
            prompt += "\nFocus session running for \(minutes) minute\(minutes == 1 ? "" : "s")."
        }

        // Include actual tracked activity — only what was genuinely captured
        if !context.recentActivity.isEmpty {
            prompt += "\nRecent captured activity:"
            for c in context.recentActivity {
                let label = c.url.hasPrefix("app://")
                    ? (c.url.replacingOccurrences(of: "app://", with: "").removingPercentEncoding ?? c.url)
                    : (URL(string: c.url)?.host ?? c.url)
                let status = c.onTask ? "on-task" : "off-task (\(c.category.rawValue))"
                let proj = c.project.map { " [\($0)]" } ?? ""
                prompt += "\n  • \(label)\(proj) — \(status)"
            }
        } else {
            prompt += "\nNo activity has been captured yet."
        }

        if let classification = context.classification {
            let label = classification.url.hasPrefix("app://")
                ? (classification.url.replacingOccurrences(of: "app://", with: "").removingPercentEncoding ?? classification.url)
                : (URL(string: classification.url)?.host ?? classification.url)
            let taskStr = classification.onTask ? "on-task" : "off-task"
            prompt += "\nCurrently: \(label) (\(classification.category.rawValue)) — \(taskStr)."
        }

        if let driftDuration = context.driftDuration {
            prompt += "\nHas been off-task for \(Int(driftDuration / 60)) minutes."
        }

        // Include active todos for on-task classification
        if !context.activeTodos.isEmpty {
            prompt += "\n\nActive task list:"
            for todo in context.activeTodos {
                prompt += "\n  • \(todo.text)"
            }
            prompt += "\nUse this task list when deciding if the user's current activity is on-task."
        }

        prompt += "\n\nBe brief, warm, and direct. Only reference activity that is listed above."
        prompt += """


        Tags — append at most ONE tag per category at the very end of your response, never mid-sentence:

        Timer tags:
        • [TIMER:Xm:label] — user explicitly asked for a countdown timer or reminder (e.g. "remind me in 20 min"). \
        The user will see a live countdown.
        • [NUDGE:Xm:label] — you proactively decide a check-in would help (e.g. after a long focus block, or when \
        the user mentions a deadline). The user will only see a calm "I'll check in soon" hint — no countdown.
        Use TIMER only when the user requests it. Use NUDGE sparingly and only when genuinely useful. \
        X must be whole minutes; label is 2–5 words.

        Todo tag:
        • [TODO:task text] — emit this when the user mentions a specific task they need to do or want to track \
        (e.g. "I need to fix the login bug", "remind me to email John", "add error handling to the API"). \
        The task will be added to their to-do list automatically and the list will pop open. \
        Only emit when a clear, actionable task is stated. task text should be concise (under 60 chars). \
        You may append #project-name to the task text to tag it with a project (e.g. [TODO:Fix login bug #steady]).

        Project tagging:
        • Users can mention #project-name anywhere in their messages to refer to or create a project. \
        If you detect the user discussing work related to a specific project or explicitly naming one with #, \
        acknowledge it naturally. Projects auto-register when mentioned with # or detected from activity.
        """

        return prompt
    }
}
