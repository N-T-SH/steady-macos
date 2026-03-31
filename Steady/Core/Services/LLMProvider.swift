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
    
    func classifyURL(
        url: String,
        pageTitle: String,
        intention: Intention
    ) async throws -> URLClassification {
        let prompt = buildClassificationPrompt(url: url, pageTitle: pageTitle, intention: intention)
        
        guard let apiKey = try? KeychainHelper.load(key: config.apiKeyIdentifier) else {
            throw LLMError.noAPIKey
        }
        
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a URL classifier. Respond ONLY with valid JSON in the exact format specified by the user."],
            ["role": "user", "content": prompt]
        ]
        
        let data = try await makeRequest(
            model: config.classificationModel,
            messages: messages,
            apiKey: apiKey,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )
        
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }
        
        return try parseClassificationResponse(content, url: url, pageTitle: pageTitle)
    }
    
    func generateConversationResponse(
        messages: [ConversationTurn],
        context: ConversationContext
    ) async throws -> String {
        guard let apiKey = try? KeychainHelper.load(key: config.apiKeyIdentifier) else {
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
            model: config.conversationModel,
            messages: messageArray,
            apiKey: apiKey,
            temperature: config.temperature,
            maxTokens: config.maxTokens
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
        guard let url = URL(string: "\(config.providerURL)/chat/completions") else {
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
    
    private func buildClassificationPrompt(url: String, pageTitle: String, intention: Intention) -> String {
        return """
        Analyze this URL and determine if it's on-task or off-task for the user's current intention.
        
        User's Intention: \(intention.task)
        Why it matters: \(intention.whyItMatters)
        
        URL to classify: \(url)
        Page Title: \(pageTitle)
        
        Respond with ONLY a JSON object in this exact format (no markdown, no code blocks):
        {
            "onTask": true/false,
            "project": "project name if identifiable, or null if not applicable",
            "category": "one of: coding, design, research, communication, social_media, news, entertainment, other_work, unknown",
            "confidence": 0.0 to 1.0,
            "reasoning": "brief explanation of the classification"
        }
        """
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
            
            return URLClassification(
                url: url,
                pageTitle: pageTitle,
                onTask: classification.onTask,
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
        var prompt = "You are a supportive mindfulness companion helping the user stay focused and intentional with their digital habits. "
        
        if let intention = context.intention {
            prompt += "The user's current intention is: \(intention.task). "
            prompt += "Why it matters to them: \(intention.whyItMatters). "
            prompt += "Their strictness level is: \(intention.strictness.rawValue). "
        }
        
        if let session = context.session {
            let duration = session.endTime?.timeIntervalSince(session.startTime) ?? Date().timeIntervalSince(session.startTime)
            let minutes = Int(duration / 60)
            prompt += "They have been working for \(minutes) minutes. "
        }
        
        if let driftDuration = context.driftDuration {
            let driftMinutes = Int(driftDuration / 60)
            prompt += "They have been drifting for \(driftMinutes) minutes. "
        }
        
        if let classification = context.classification {
            if classification.onTask {
                prompt += "They are currently on a relevant page: \(classification.pageTitle) (\(classification.category.rawValue)). "
            } else {
                prompt += "They are currently off-task on: \(classification.pageTitle) (\(classification.category.rawValue)). "
            }
        }
        
        prompt += "Be brief, warm, and helpful. Use their context to provide personalized support."
        
        return prompt
    }
}
