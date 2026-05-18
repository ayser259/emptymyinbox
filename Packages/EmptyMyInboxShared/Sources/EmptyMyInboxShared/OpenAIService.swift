import Foundation

public struct InsightGenerationResult: Codable {
    public let summary: String
    public let keyPoints: [String]
    public let themeTag: String
    public let confidence: Double
}

private struct InsightGenerationEnvelope: Codable {
    let insights: [InsightGenerationResult]
}

private struct QuickReplyEnvelope: Codable {
    let reply: String
}

public actor OpenAIService {
    public static let shared = OpenAIService()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let retryableStatusCodes: Set<Int> = [408, 409, 425, 429]
    private let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet
    ]

    public func classifyBriefingItem(subject: String, snippet: String, sender: String) async throws -> BriefingItemType {
        let settings = await LLMSettingsStore.shared.currentSettings()
        let inputJSON = encodePromptInput([
            "sender": sender,
            "subject": subject,
            "snippet": snippet
        ])
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedBriefPrompts()
        let prompt = userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)

        let response = try await runChatPrompt(
            feature: "briefing.classify",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: settings.briefModel,
            temperature: 0.0,
            maxTokens: 40,
            schema: Self.briefingTypeSchema
        )

        guard let data = response.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = object["type"] as? String else {
            throw OpenAIServiceError.invalidResponse
        }

        let normalized = typeString.trimmingCharacters(in: .whitespacesAndNewlines)
        return BriefingItemType(rawValue: normalized) ?? .directCommunication
    }

    public func summarizeNewsletterStories(
        subject: String,
        snippet: String,
        sender: String,
        body: String?,
        preferenceContext: String
    ) async throws -> [InsightGenerationResult] {
        let settings = await LLMSettingsStore.shared.currentSettings()
        let selectedStoriesModel = settings.storiesModel
        let inputJSON = encodePromptInput([
            "sender": sender,
            "subject": subject,
            "snippet": snippet,
            "body": body ?? "",
            "preferenceContext": preferenceContext
        ])
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedStoriesPrompts()
        let prompt = userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)

        let response = try await runChatPrompt(
            feature: "stories.summarize",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: selectedStoriesModel,
            temperature: 0.1,
            maxTokens: 500,
            schema: Self.storyInsightsSchema
        )

        guard let data = response.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(InsightGenerationEnvelope.self, from: data) else {
            throw OpenAIServiceError.invalidResponse
        }
        return envelope.insights.map { normalized(result: $0) }
    }

    public func quickReply(
        subject: String,
        sender: String,
        snippet: String,
        body: String,
        userAsk: String
    ) async throws -> String {
        let settings = await LLMSettingsStore.shared.currentSettings()
        let inputJSON = encodePromptInput([
            "sender": sender,
            "subject": subject,
            "snippet": snippet,
            "body": body,
            "quickReplyAsk": userAsk
        ])
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedQuickReplyPrompts()
        let prompt = userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)

        let response = try await runChatPrompt(
            feature: "reply.quick",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: settings.quickReplyModel,
            temperature: 0.5,
            maxTokens: 220,
            schema: Self.quickReplySchema
        )
        return try parseQuickReply(from: response)
    }

    private func runChatPrompt(
        feature: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        schema: [String: Any]? = nil
    ) async throws -> String {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard let apiKey = await LLMSettingsStore.shared.getAPIKey(), !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }
        let defaults = LLMModelCatalog.defaults(for: .openAI)
        let selectedModel = LLMModelCatalog.contains(model, provider: .openAI) ? model : defaults.defaultModel
        Telemetry.event("llm.request.started", metadata: [
            "provider": LLMProvider.openAI.rawValue,
            "feature": feature,
            "model": selectedModel
        ])
        let requestStart = Date()

        var requestBody: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        if let schema {
            requestBody["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "response",
                    "strict": true,
                    "schema": schema
                ]
            ]
        }
        logLLMRequestPayload(
            provider: .openAI,
            feature: feature,
            model: selectedModel,
            requestBody: requestBody
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        var attempts = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw OpenAIServiceError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "unknown"
                    let retryAfter = parseRetryAfterSeconds(from: http)
                    throw OpenAIServiceError.apiStatusError(
                        statusCode: http.statusCode,
                        body: body,
                        retryAfterSeconds: retryAfter
                    )
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    throw OpenAIServiceError.invalidResponse
                }
                Telemetry.event("llm.request.succeeded", metadata: [
                    "provider": LLMProvider.openAI.rawValue,
                    "feature": feature,
                    "model": selectedModel,
                    "attempts": "\(attempts + 1)",
                    "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                ])
                return content
            } catch is CancellationError {
                Telemetry.event("llm.request.cancelled", metadata: [
                    "provider": LLMProvider.openAI.rawValue,
                    "feature": feature,
                    "model": selectedModel,
                    "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                ])
                throw OpenAIServiceError.cancelled
            } catch {
                attempts += 1
                if attempts > settings.maxRetries || !shouldRetry(error: error) {
                    Telemetry.event("llm.request.failed", metadata: [
                        "provider": LLMProvider.openAI.rawValue,
                        "feature": feature,
                        "model": selectedModel,
                        "attempts": "\(attempts)",
                        "error_type": "\(type(of: error))",
                        "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                    ])
                    throw error
                }
                let delaySeconds = retryDelaySeconds(for: error, attempt: attempts)
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }

    private func encodePromptInput(_ payload: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return encoded
    }

    /// Replaces `{{INPUT_JSON}}` in the template; if missing, appends a fenced JSON block so requests stay well-formed.
    private func userPromptWithInputJSON(template: String, inputJSON: String) -> String {
        if template.contains(PluginPromptPlaceholder.inputJSON) {
            return template.replacingOccurrences(of: PluginPromptPlaceholder.inputJSON, with: inputJSON)
        }
        return template + "\n\n```json\n" + inputJSON + "\n```\n"
    }

    private func parseRetryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(retryAfter),
              seconds >= 0 else {
            return nil
        }
        return seconds
    }

    private func shouldRetry(error: Error) -> Bool {
        if let error = error as? OpenAIServiceError {
            switch error {
            case .apiStatusError(let statusCode, _, _):
                return retryableStatusCodes.contains(statusCode) || (500...599).contains(statusCode)
            case .missingAPIKey, .invalidResponse, .apiError:
                return false
            case .cancelled:
                return false
            }
        }
        if let urlError = error as? URLError {
            return retryableURLErrorCodes.contains(urlError.code)
        }
        return false
    }

    private func retryDelaySeconds(for error: Error, attempt: Int) -> TimeInterval {
        if let error = error as? OpenAIServiceError,
           case .apiStatusError(_, _, let retryAfterSeconds) = error,
           let retryAfterSeconds {
            return retryAfterSeconds + Double.random(in: 0.0...0.25)
        }
        let exponential = min(pow(2.0, Double(max(attempt - 1, 0))) * 0.5, 8.0)
        return exponential + Double.random(in: 0.0...0.25)
    }

    private func parseQuickReply(from response: String) throws -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        if let data = trimmed.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(QuickReplyEnvelope.self, from: data) {
            let reply = envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw OpenAIServiceError.invalidResponse
            }
            return reply
        }
        // Backward compatibility for older/custom prompt formats that may still return plain text.
        return trimmed
    }

    private func logLLMRequestPayload(
        provider: LLMProvider,
        feature: String,
        model: String,
        requestBody: [String: Any]
    ) {
        let encodedBody: String
        if let data = try? JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            encodedBody = text
        } else {
            encodedBody = "\(requestBody)"
        }

        let maxChars = 12_000
        let clippedBody = encodedBody.count > maxChars
            ? String(encodedBody.prefix(maxChars)) + "…(truncated)"
            : encodedBody

        logInfo(
            "LLM request payload provider=\(provider.rawValue) feature=\(feature) model=\(model) body=\(clippedBody)",
            category: "LLM"
        )
    }

    private func normalized(result: InsightGenerationResult) -> InsightGenerationResult {
        let cleanTheme = result.themeTag
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
        let clampedConfidence = min(max(result.confidence, 0), 1)
        let points = Array(result.keyPoints.prefix(3))
        let padded = points.count == 3 ? points : points + Array(repeating: "More details in full newsletter.", count: max(0, 3 - points.count))
        return InsightGenerationResult(
            summary: result.summary,
            keyPoints: padded,
            themeTag: cleanTheme.isEmpty ? "General" : cleanTheme,
            confidence: clampedConfidence
        )
    }

    private static let briefingTypeSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "type": [
                "type": "string",
                "enum": ["directCommunication", "calendarInvite", "urgentNotification"]
            ]
        ],
        "required": ["type"],
        "additionalProperties": false
    ]

    private static let singleInsightSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "keyPoints": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 3,
                "maxItems": 3
            ],
            "themeTag": ["type": "string"],
            "confidence": ["type": "number"]
        ],
        "required": ["summary", "keyPoints", "themeTag", "confidence"],
        "additionalProperties": false
    ]

    private static let storyInsightsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "insights": [
                "type": "array",
                "items": singleInsightSchema,
                "minItems": 0,
                "maxItems": 3
            ]
        ],
        "required": ["insights"],
        "additionalProperties": false
    ]

    private static let quickReplySchema: [String: Any] = [
        "type": "object",
        "properties": [
            "reply": ["type": "string"]
        ],
        "required": ["reply"],
        "additionalProperties": false
    ]
}

public enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case apiStatusError(statusCode: Int, body: String, retryAfterSeconds: TimeInterval?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing."
        case .invalidResponse:
            return "The AI response could not be parsed."
        case .apiError(let message):
            return message
        case .apiStatusError(let statusCode, let body, _):
            return "OpenAI status \(statusCode): \(body)"
        case .cancelled:
            return "AI request was cancelled."
        }
    }
}

