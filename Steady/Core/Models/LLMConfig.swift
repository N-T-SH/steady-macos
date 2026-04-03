import Foundation

struct LLMConfig: Codable, Equatable {
    var providerURL: String
    var apiKeyIdentifier: String
    var classificationModel: String
    var conversationModel: String
    var maxTokens: Int
    var temperature: Double
    
    static let `default` = LLMConfig(
        providerURL: "https://openrouter.ai/api/v1",
        apiKeyIdentifier: "steady-openrouter-key",
        classificationModel: "",
        conversationModel: "",
        maxTokens: 1000,
        temperature: 0.7
    )
}
