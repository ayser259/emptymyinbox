import Foundation

enum LLMPromptEncoding {
    static func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return encoded
    }

    static func userPromptWithInputJSON(template: String, inputJSON: String) -> String {
        if template.contains(PluginPromptPlaceholder.inputJSON) {
            return template.replacingOccurrences(of: PluginPromptPlaceholder.inputJSON, with: inputJSON)
        }
        return template + "\n\n```json\n" + inputJSON + "\n```\n"
    }
}
