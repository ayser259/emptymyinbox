import Foundation

public enum LLMModelCatalog {
    public static let openAIModels = ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1", "gpt-4o"]
    public static let claudeModels = ["claude-haiku-4-5", "claude-sonnet-4-6"]

    public static func models(for provider: LLMProvider) -> [String] {
        switch provider {
        case .openAI:
            return openAIModels
        case .claude:
            return claudeModels
        }
    }

    public static func contains(_ model: String, provider: LLMProvider) -> Bool {
        models(for: provider).contains(model)
    }

    public static func defaults(for provider: LLMProvider) -> (defaultModel: String, initialPassModel: String, proModel: String) {
        switch provider {
        case .openAI:
            return ("gpt-4o-mini", "gpt-4o-mini", "gpt-4.1")
        case .claude:
            return ("claude-sonnet-4-6", "claude-haiku-4-5", "claude-sonnet-4-6")
        }
    }
}
