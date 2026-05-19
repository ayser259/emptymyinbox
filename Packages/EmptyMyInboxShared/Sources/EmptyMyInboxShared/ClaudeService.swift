import Foundation

private struct ClaudeResponsePayload: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

private struct ClaudeQuickReplyEnvelope: Codable {
    let reply: String
}

public actor ClaudeService {
    public static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let retryableStatusCodes: Set<Int> = [408, 409, 425, 429]
    private let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet
    ]

    public func generateDailyBrief(candidates: DailyBriefCandidates) async throws -> DailyBriefLLMResponse {
        let settings = await LLMSettingsStore.shared.currentSettings()
        let inputJSON = encodePromptJSON(candidates)
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedBriefPrompts()
        let prompt = userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)

        let response = try await runPrompt(
            feature: "briefing.generate",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: settings.briefModel,
            maxTokens: 2500
        )

        let normalizedJSON = normalizeJSONText(response)
        guard let data = normalizedJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DailyBriefLLMResponse.self, from: data) else {
            throw ClaudeServiceError.invalidResponse
        }
        return decoded
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

        let response = try await runPrompt(
            feature: "stories.summarize",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: selectedStoriesModel,
            maxTokens: 1200
        )

        let normalizedJSON = normalizeJSONText(response)
        guard let data = normalizedJSON.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClaudeInsightEnvelope.self, from: data) else {
            throw ClaudeServiceError.invalidResponse
        }
        return envelope.insights.map { normalized(result: $0) }
    }

    public func quickReply(
        subject: String,
        sender: String,
        snippet: String,
        body: String,
        userAsk: String,
        currentDraft: String = "",
        recipientsTo: String = "",
        recipientsCc: String = ""
    ) async throws -> String {
        let settings = await LLMSettingsStore.shared.currentSettings()
        var input: [String: String] = [
            "sender": sender,
            "subject": subject,
            "snippet": snippet,
            "body": body,
            "quickReplyAsk": userAsk
        ]
        if !currentDraft.isEmpty { input["currentDraft"] = currentDraft }
        if !recipientsTo.isEmpty { input["recipientsTo"] = recipientsTo }
        if !recipientsCc.isEmpty { input["recipientsCc"] = recipientsCc }
        let inputJSON = encodePromptInput(input)
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedQuickReplyPrompts()
        let prompt = userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)

        let response = try await runPrompt(
            feature: "reply.quick",
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: settings.quickReplyModel,
            maxTokens: 320
        )
        return try parseQuickReply(from: response)
    }

    private func runPrompt(
        feature: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard let apiKey = await ClaudeAPIKeyStore.shared.readAPIKeyResult().keyValue, !apiKey.isEmpty else {
            throw ClaudeServiceError.missingAPIKey
        }
        let defaults = LLMModelCatalog.defaults(for: .claude)
        let selectedModel = LLMModelCatalog.contains(model, provider: .claude) ? model : defaults.defaultModel
        Telemetry.event("llm.request.started", metadata: [
            "provider": LLMProvider.claude.rawValue,
            "feature": feature,
            "model": selectedModel
        ])
        let requestStart = Date()

        let requestBody: [String: Any] = [
            "model": selectedModel,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        logLLMRequestPayload(
            provider: .claude,
            feature: feature,
            model: selectedModel,
            requestBody: requestBody
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        var attempts = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ClaudeServiceError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "unknown"
                    let retryAfter = parseRetryAfterSeconds(from: http)
                    throw ClaudeServiceError.apiStatusError(
                        statusCode: http.statusCode,
                        body: body,
                        retryAfterSeconds: retryAfter
                    )
                }

                guard let payload = try? JSONDecoder().decode(ClaudeResponsePayload.self, from: data),
                      let text = payload.content.first(where: { $0.type == "text" })?.text else {
                    throw ClaudeServiceError.invalidResponse
                }
                Telemetry.event("llm.request.succeeded", metadata: [
                    "provider": LLMProvider.claude.rawValue,
                    "feature": feature,
                    "model": selectedModel,
                    "attempts": "\(attempts + 1)",
                    "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                ])
                return text
            } catch is CancellationError {
                Telemetry.event("llm.request.cancelled", metadata: [
                    "provider": LLMProvider.claude.rawValue,
                    "feature": feature,
                    "model": selectedModel,
                    "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                ])
                throw ClaudeServiceError.cancelled
            } catch {
                attempts += 1
                if attempts > settings.maxRetries || !shouldRetry(error: error) {
                    var metadata: [String: String] = [
                        "provider": LLMProvider.claude.rawValue,
                        "feature": feature,
                        "model": selectedModel,
                        "attempts": "\(attempts)",
                        "error_type": "\(type(of: error))",
                        "elapsed_ms": "\(Int(Date().timeIntervalSince(requestStart) * 1000))"
                    ]
                    if let claudeError = error as? ClaudeServiceError,
                       case .apiStatusError(let statusCode, let body, _) = claudeError {
                        metadata["status_code"] = "\(statusCode)"
                        metadata["status_body"] = String(body.prefix(240))
                    }
                    Telemetry.event("llm.request.failed", metadata: metadata)
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

    private func encodePromptJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
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

    private func normalizeJSONText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let stripped = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let error = error as? ClaudeServiceError {
            switch error {
            case .apiStatusError(let statusCode, _, _):
                return retryableStatusCodes.contains(statusCode) || (500...599).contains(statusCode)
            case .missingAPIKey, .invalidResponse, .apiError, .cancelled:
                return false
            }
        }
        if let urlError = error as? URLError {
            return retryableURLErrorCodes.contains(urlError.code)
        }
        return false
    }

    private func retryDelaySeconds(for error: Error, attempt: Int) -> TimeInterval {
        if let error = error as? ClaudeServiceError,
           case .apiStatusError(_, _, let retryAfterSeconds) = error,
           let retryAfterSeconds {
            return retryAfterSeconds + Double.random(in: 0.0...0.25)
        }
        let exponential = min(pow(2.0, Double(max(attempt - 1, 0))) * 0.5, 8.0)
        return exponential + Double.random(in: 0.0...0.25)
    }

    private func parseQuickReply(from response: String) throws -> String {
        let normalizedJSON = normalizeJSONText(response)
        if let data = normalizedJSON.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(ClaudeQuickReplyEnvelope.self, from: data) {
            let reply = envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw ClaudeServiceError.invalidResponse
            }
            return reply
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClaudeServiceError.invalidResponse
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
}

private struct ClaudeInsightEnvelope: Codable {
    let insights: [InsightGenerationResult]
}

public enum ClaudeServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case apiStatusError(statusCode: Int, body: String, retryAfterSeconds: TimeInterval?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic Claude API key is missing."
        case .invalidResponse:
            return "The AI response could not be parsed."
        case .apiError(let message):
            return message
        case .apiStatusError(let statusCode, let body, _):
            return "Claude status \(statusCode): \(body)"
        case .cancelled:
            return "AI request was cancelled."
        }
    }
}
