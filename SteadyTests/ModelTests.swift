import Foundation
import XCTest

@testable import Steady

class ModelTests: XCTestCase {
    
    // MARK: - Intention Tests
    
    func testIntentionEncodingDecoding() throws {
        let intention = Intention(
            id: UUID(),
            task: "Write unit tests",
            whyItMatters: "Ensure code quality",
            plannedDuration: 60,
            scheduledDate: Date(),
            strictness: .focused,
            temptationBundle: nil,
            status: .planned
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(intention)
        let decoded = try decoder.decode(Intention.self, from: data)
        
        XCTAssertEqual(intention.id, decoded.id)
        XCTAssertEqual(intention.task, decoded.task)
        XCTAssertEqual(intention.whyItMatters, decoded.whyItMatters)
        XCTAssertEqual(intention.plannedDuration, decoded.plannedDuration)
        XCTAssertEqual(intention.strictness, decoded.strictness)
        XCTAssertEqual(intention.status, decoded.status)
        XCTAssertEqual(intention.temptationBundle, decoded.temptationBundle)
    }
    
    func testIntentionEquality() {
        let id = UUID()
        let date = Date()
        
        let intention1 = Intention(
            id: id,
            task: "Task",
            whyItMatters: "Why",
            plannedDuration: 30,
            scheduledDate: date,
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        let intention2 = Intention(
            id: id,
            task: "Task",
            whyItMatters: "Why",
            plannedDuration: 30,
            scheduledDate: date,
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        XCTAssertEqual(intention1, intention2)
    }
    
    func testStrictnessLevelRawValues() {
        XCTAssertEqual(StrictnessLevel.quiet.rawValue, "quiet")
        XCTAssertEqual(StrictnessLevel.gentle.rawValue, "gentle")
        XCTAssertEqual(StrictnessLevel.focused.rawValue, "focused")
        XCTAssertEqual(StrictnessLevel.accountable.rawValue, "accountable")
    }
    
    func testStrictnessLevelCaseIterable() {
        let allCases = StrictnessLevel.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.quiet))
        XCTAssertTrue(allCases.contains(.gentle))
        XCTAssertTrue(allCases.contains(.focused))
        XCTAssertTrue(allCases.contains(.accountable))
    }
    
    func testIntentionStatusRawValues() {
        XCTAssertEqual(IntentionStatus.planned.rawValue, "planned")
        XCTAssertEqual(IntentionStatus.active.rawValue, "active")
        XCTAssertEqual(IntentionStatus.completed.rawValue, "completed")
        XCTAssertEqual(IntentionStatus.skipped.rawValue, "skipped")
    }
    
    // MARK: - Session Tests
    
    func testSessionEncodingDecoding() throws {
        let session = Session(
            id: UUID(),
            intentionId: UUID(),
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 8,
            postSessionReflection: nil,
            urlClassifications: []
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(Session.self, from: data)
        
        XCTAssertEqual(session.id, decoded.id)
        XCTAssertEqual(session.intentionId, decoded.intentionId)
        XCTAssertEqual(session.preSessionEnergy, decoded.preSessionEnergy)
        XCTAssertNil(decoded.endTime)
    }
    
    func testDistractionLogEncodingDecoding() throws {
        let log = DistractionLog(
            timestamp: Date(),
            url: "https://example.com",
            category: "social",
            duration: 300,
            acknowledged: false
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(log)
        let decoded = try decoder.decode(DistractionLog.self, from: data)
        
        XCTAssertEqual(log.url, decoded.url)
        XCTAssertEqual(log.category, decoded.category)
        XCTAssertEqual(log.duration, decoded.duration)
        XCTAssertEqual(log.acknowledged, decoded.acknowledged)
    }
    
    func testSessionWithDistractions() throws {
        let distraction = DistractionLog(
            timestamp: Date(),
            url: "https://twitter.com",
            category: "social_media",
            duration: 120,
            acknowledged: true
        )
        
        let session = Session(
            id: UUID(),
            intentionId: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            interruptions: [distraction],
            preSessionEnergy: 7,
            postSessionReflection: "Good session",
            urlClassifications: []
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(Session.self, from: data)
        
        XCTAssertEqual(decoded.interruptions.count, 1)
        XCTAssertEqual(decoded.interruptions.first?.url, "https://twitter.com")
    }
    
    // MARK: - URLClassification Tests
    
    func testURLClassificationEncodingDecoding() throws {
        let classification = URLClassification(
            url: "https://github.com",
            pageTitle: "GitHub",
            onTask: true,
            project: "Steady",
            category: .coding,
            confidence: 0.95,
            reasoning: "Code repository",
            timestamp: Date()
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(classification)
        let decoded = try decoder.decode(URLClassification.self, from: data)
        
        XCTAssertEqual(classification.url, decoded.url)
        XCTAssertEqual(classification.pageTitle, decoded.pageTitle)
        XCTAssertEqual(classification.onTask, decoded.onTask)
        XCTAssertEqual(classification.project, decoded.project)
        XCTAssertEqual(classification.category, decoded.category)
        XCTAssertEqual(classification.confidence, decoded.confidence)
        XCTAssertEqual(classification.reasoning, decoded.reasoning)
    }
    
    func testURLCategoryRawValues() {
        XCTAssertEqual(URLCategory.coding.rawValue, "coding")
        XCTAssertEqual(URLCategory.design.rawValue, "design")
        XCTAssertEqual(URLCategory.research.rawValue, "research")
        XCTAssertEqual(URLCategory.communication.rawValue, "communication")
        XCTAssertEqual(URLCategory.socialMedia.rawValue, "social_media")
        XCTAssertEqual(URLCategory.news.rawValue, "news")
        XCTAssertEqual(URLCategory.entertainment.rawValue, "entertainment")
        XCTAssertEqual(URLCategory.otherWork.rawValue, "other_work")
        XCTAssertEqual(URLCategory.unknown.rawValue, "unknown")
    }
    
    func testURLCategoryCaseIterable() {
        let allCases = URLCategory.allCases
        XCTAssertEqual(allCases.count, 9)
    }
    
    // MARK: - ConversationTurn Tests
    
    func testConversationTurnEncodingDecoding() throws {
        let turn = ConversationTurn(
            timestamp: Date(),
            role: .user,
            content: "Hello",
            context: nil
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(turn)
        let decoded = try decoder.decode(ConversationTurn.self, from: data)
        
        XCTAssertEqual(turn.role, decoded.role)
        XCTAssertEqual(turn.content, decoded.content)
    }
    
    func testMessageRoleRawValues() {
        XCTAssertEqual(MessageRole.system.rawValue, "system")
        XCTAssertEqual(MessageRole.user.rawValue, "user")
        XCTAssertEqual(MessageRole.assistant.rawValue, "assistant")
    }
    
    func testConversationContextWithIntention() throws {
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .quiet,
            temptationBundle: nil,
            status: .planned
        )
        
        let context = ConversationContext(
            intention: intention,
            session: nil,
            driftDuration: nil,
            classification: nil
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(context)
        let decoded = try decoder.decode(ConversationContext.self, from: data)
        
        XCTAssertNotNil(decoded.intention)
        XCTAssertEqual(decoded.intention?.task, "Test")
    }
    
    // MARK: - LLMConfig Tests
    
    func testLLMConfigDefaultValues() {
        let config = LLMConfig.default
        
        XCTAssertEqual(config.providerURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(config.apiKeyIdentifier, "steady-openrouter-key")
        XCTAssertEqual(config.classificationModel, "google/gemini-flash-2.0")
        XCTAssertEqual(config.conversationModel, "anthropic/claude-haiku-4-5")
        XCTAssertEqual(config.maxTokens, 1000)
        XCTAssertEqual(config.temperature, 0.7)
    }
    
    func testLLMConfigEncodingDecoding() throws {
        let config = LLMConfig(
            providerURL: "https://api.openai.com",
            apiKeyIdentifier: "test-key",
            classificationModel: "gpt-4",
            conversationModel: "gpt-3.5",
            maxTokens: 2000,
            temperature: 0.5
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(LLMConfig.self, from: data)
        
        XCTAssertEqual(config.providerURL, decoded.providerURL)
        XCTAssertEqual(config.apiKeyIdentifier, decoded.apiKeyIdentifier)
        XCTAssertEqual(config.classificationModel, decoded.classificationModel)
        XCTAssertEqual(config.conversationModel, decoded.conversationModel)
        XCTAssertEqual(config.maxTokens, decoded.maxTokens)
        XCTAssertEqual(config.temperature, decoded.temperature)
    }
    
    func testLLMConfigEquality() {
        let config1 = LLMConfig.default
        let config2 = LLMConfig.default
        
        XCTAssertEqual(config1, config2)
    }
    
    // MARK: - Integration Tests
    
    func testFullWorkflowEncoding() throws {
        let intention = Intention(
            id: UUID(),
            task: "Complete project",
            whyItMatters: "Important deadline",
            plannedDuration: 120,
            scheduledDate: Date(),
            strictness: .accountable,
            temptationBundle: nil,
            status: .active
        )
        
        let urlClassification = URLClassification(
            url: "https://stackoverflow.com",
            pageTitle: "Stack Overflow",
            onTask: true,
            project: "Steady",
            category: .coding,
            confidence: 0.98,
            reasoning: "Programming Q&A site",
            timestamp: Date()
        )
        
        let session = Session(
            id: UUID(),
            intentionId: intention.id,
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 9,
            postSessionReflection: nil,
            urlClassifications: [urlClassification]
        )
        
        let context = ConversationContext(
            intention: intention,
            session: session,
            driftDuration: 300,
            classification: urlClassification
        )
        
        let turn = ConversationTurn(
            timestamp: Date(),
            role: .assistant,
            content: "You seem focused!",
            context: context
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(turn)
        let decoded = try decoder.decode(ConversationTurn.self, from: data)
        
        XCTAssertNotNil(decoded.context)
        XCTAssertNotNil(decoded.context?.intention)
        XCTAssertNotNil(decoded.context?.session)
        XCTAssertNotNil(decoded.context?.classification)
        XCTAssertEqual(decoded.context?.intention?.task, "Complete project")
        XCTAssertEqual(decoded.context?.classification?.category, .coding)
    }
}
