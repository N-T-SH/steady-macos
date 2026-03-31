import Foundation
import XCTest

@testable import Steady

// MARK: - Mock URLSession

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = MockURLProtocol.mockResponse {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = MockURLProtocol.mockData {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    override func stopLoading() {}
    
    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
    }
}

// MARK: - LLMProvider Tests

class LLMProviderTests: XCTestCase {
    
    var config: LLMConfig!
    var mockSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        config = LLMConfig(
            providerURL: "https://api.test.com",
            apiKeyIdentifier: "test-api-key",
            classificationModel: "test-classifier",
            conversationModel: "test-conversation",
            maxTokens: 500,
            temperature: 0.5
        )
        
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: configuration)
        
        MockURLProtocol.reset()
        
        // Store a test API key in keychain
        try? KeychainHelper.save(key: config.apiKeyIdentifier, data: "test-api-key-value")
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        try? KeychainHelper.delete(key: config.apiKeyIdentifier)
        super.tearDown()
    }
    
    // MARK: - LLM Request Building Tests
    
    func testLLMRequestBuilding() async throws {
        let mockResponse: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "{\"onTask\": true, \"category\": \"coding\", \"confidence\": 0.95, \"reasoning\": \"Code repository\"}"
                    ]
                ]
            ]
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: mockResponse)
        MockURLProtocol.mockData = responseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Write code",
            whyItMatters: "Ship feature",
            plannedDuration: 60,
            scheduledDate: Date(),
            strictness: .focused,
            temptationBundle: nil,
            status: .active
        )
        
        let classification = try await provider.classifyURL(
            url: "https://github.com/test",
            pageTitle: "GitHub",
            intention: intention
        )
        
        XCTAssertEqual(classification.onTask, true)
        XCTAssertEqual(classification.category, .coding)
        XCTAssertEqual(classification.confidence, 0.95)
        XCTAssertEqual(classification.reasoning, "Code repository")
    }
    
    func testURLClassificationResponseParsing() async throws {
        let mockResponse: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "{\"onTask\": false, \"project\": null, \"category\": \"social_media\", \"confidence\": 0.88, \"reasoning\": \"Social networking site\"}"
                    ]
                ]
            ]
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: mockResponse)
        MockURLProtocol.mockData = responseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Deep work",
            whyItMatters: "Focus",
            plannedDuration: 90,
            scheduledDate: Date(),
            strictness: .accountable,
            temptationBundle: nil,
            status: .active
        )
        
        let classification = try await provider.classifyURL(
            url: "https://twitter.com",
            pageTitle: "Twitter",
            intention: intention
        )
        
        XCTAssertEqual(classification.onTask, false)
        XCTAssertEqual(classification.category, .socialMedia)
        XCTAssertEqual(classification.confidence, 0.88)
        XCTAssertEqual(classification.project, nil)
    }
    
    func testConversationResponseParsing() async throws {
        let mockResponse: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "How can I help you stay focused today?"
                    ]
                ]
            ]
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: mockResponse)
        MockURLProtocol.mockData = responseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Focus",
            whyItMatters: "Important",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        let session = Session(
            id: UUID(),
            intentionId: intention.id,
            startTime: Date(),
            endTime: nil,
            interruptions: [],
            preSessionEnergy: 8,
            postSessionReflection: nil,
            urlClassifications: []
        )
        
        let messages = [
            ConversationTurn(
                timestamp: Date(),
                role: .user,
                content: "Help me focus",
                context: ConversationContext(intention: intention, session: session, driftDuration: nil, classification: nil)
            )
        ]
        
        let context = ConversationContext(intention: intention, session: session, driftDuration: nil, classification: nil)
        let response = try await provider.generateConversationResponse(messages: messages, context: context)
        
        XCTAssertEqual(response, "How can I help you stay focused today?")
    }
    
    // MARK: - Keychain Tests
    
    func testKeychainSaveAndRetrieve() throws {
        let testKey = "test-keychain-key"
        let testData = "test-secret-value-12345"
        
        try KeychainHelper.save(key: testKey, data: testData)
        
        let retrieved = try KeychainHelper.load(key: testKey)
        XCTAssertEqual(retrieved, testData)
        
        try KeychainHelper.delete(key: testKey)
    }
    
    func testKeychainUpdate() throws {
        let testKey = "test-update-key"
        let initialData = "initial-value"
        let updatedData = "updated-value"
        
        try KeychainHelper.save(key: testKey, data: initialData)
        let firstRetrieval = try KeychainHelper.load(key: testKey)
        XCTAssertEqual(firstRetrieval, initialData)
        
        try KeychainHelper.save(key: testKey, data: updatedData)
        let secondRetrieval = try KeychainHelper.load(key: testKey)
        XCTAssertEqual(secondRetrieval, updatedData)
        
        try KeychainHelper.delete(key: testKey)
    }
    
    func testKeychainDelete() throws {
        let testKey = "test-delete-key"
        let testData = "data-to-delete"
        
        try KeychainHelper.save(key: testKey, data: testData)
        XCTAssertTrue(KeychainHelper.exists(key: testKey))
        
        try KeychainHelper.delete(key: testKey)
        XCTAssertFalse(KeychainHelper.exists(key: testKey))
        
        XCTAssertThrowsError(try KeychainHelper.load(key: testKey)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }
    
    func testKeychainItemNotFound() {
        let nonExistentKey = "non-existent-key-12345"
        
        XCTAssertThrowsError(try KeychainHelper.load(key: nonExistentKey)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidJSONHandling() async throws {
        let mockResponse: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "not valid json"
                    ]
                ]
            ]
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: mockResponse)
        MockURLProtocol.mockData = responseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        do {
            _ = try await provider.classifyURL(url: "https://test.com", pageTitle: "Test", intention: intention)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is LLMError)
        }
    }
    
    func testAPIErrorHandling() async {
        let errorResponse: [String: Any] = [
            "error": [
                "message": "Invalid API key provided"
            ]
        ]
        
        do {
            let responseData = try JSONSerialization.data(withJSONObject: errorResponse)
            MockURLProtocol.mockData = responseData
            MockURLProtocol.mockResponse = HTTPURLResponse(
                url: URL(string: "https://api.test.com/chat/completions")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
        } catch {
            XCTFail("Failed to create error data")
            return
        }
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        do {
            _ = try await provider.classifyURL(url: "https://test.com", pageTitle: "Test", intention: intention)
            XCTFail("Should have thrown an error")
        } catch let error as LLMError {
            if case .apiError(let message) = error {
                XCTAssertEqual(message, "Invalid API key provided")
            } else {
                XCTFail("Expected apiError but got \(error)")
            }
        } catch {
            // Other error types are acceptable for HTTP 401
        }
    }
    
    func testNoAPIKeyError() async {
        let configWithoutKey = LLMConfig(
            providerURL: "https://api.test.com",
            apiKeyIdentifier: "non-existent-key-id",
            classificationModel: "test",
            conversationModel: "test",
            maxTokens: 100,
            temperature: 0.5
        )
        
        let provider = LLMProvider(config: configWithoutKey, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        do {
            _ = try await provider.classifyURL(url: "https://test.com", pageTitle: "Test", intention: intention)
            XCTFail("Should have thrown an error")
        } catch let error as LLMError {
            XCTAssertEqual(error, LLMError.noAPIKey)
        } catch {
            XCTFail("Expected LLMError.noAPIKey but got \(error)")
        }
    }
    
    func testRequestFailedError() async {
        MockURLProtocol.mockError = NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network failed"])
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        do {
            _ = try await provider.classifyURL(url: "https://test.com", pageTitle: "Test", intention: intention)
            XCTFail("Should have thrown an error")
        } catch let error as LLMError {
            if case .requestFailed(_) = error {
                // Expected
            } else {
                XCTFail("Expected requestFailed but got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError but got \(error)")
        }
    }
    
    func testEmptyChoicesResponse() async throws {
        let mockResponse: [String: Any] = [
            "choices": []
        ]
        
        let responseData = try JSONSerialization.data(withJSONObject: mockResponse)
        MockURLProtocol.mockData = responseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let provider = LLMProvider(config: config, urlSession: mockSession)
        
        let intention = Intention(
            id: UUID(),
            task: "Test",
            whyItMatters: "Testing",
            plannedDuration: 30,
            scheduledDate: Date(),
            strictness: .gentle,
            temptationBundle: nil,
            status: .active
        )
        
        do {
            _ = try await provider.classifyURL(url: "https://test.com", pageTitle: "Test", intention: intention)
            XCTFail("Should have thrown an error")
        } catch let error as LLMError {
            XCTAssertEqual(error, LLMError.invalidResponse)
        } catch {
            XCTFail("Expected LLMError.invalidResponse but got \(error)")
        }
    }
}

// MARK: - LLMError Equatable Extension

extension LLMError: Equatable {
    public static func == (lhs: LLMError, rhs: LLMError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.noAPIKey, .noAPIKey):
            return true
        case (.requestFailed(_), .requestFailed(_)):
            return true
        case (.decodingFailed(_), .decodingFailed(_)):
            return true
        case (.apiError(let lhsMsg), .apiError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}
