import Foundation

public enum StoryPromptStatus: String, Codable {
    case attempted
    case failed
    case succeeded
}

public struct StoryPromptState: Codable {
    public var status: StoryPromptStatus = .attempted
    public var attempts: Int = 0
    public var lastAttemptAt: Date = .distantPast
    public var lastSuccessAt: Date?
    public var lastError: String?
    public var cooldownUntil: Date?

    public init() {
        self.status = .attempted
        self.attempts = 0
        self.lastAttemptAt = .distantPast
        self.lastSuccessAt = nil
        self.lastError = nil
        self.cooldownUntil = nil
    }

    public init(
        status: StoryPromptStatus,
        attempts: Int,
        lastAttemptAt: Date,
        lastSuccessAt: Date?,
        lastError: String?,
        cooldownUntil: Date?
    ) {
        self.status = status
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.cooldownUntil = cooldownUntil
    }

    public func canAttempt(at date: Date) -> Bool {
        switch status {
        case .succeeded:
            return false
        case .attempted, .failed:
            if let cooldownUntil {
                return date >= cooldownUntil
            }
            return true
        }
    }
}

public enum StoryPromptResult {
    case success
    case failed(reason: String)
    case empty
}

public struct StoryPromptOutcome {
    public let emailId: Int
    public let result: StoryPromptResult
    
    public init(emailId: Int, result: StoryPromptResult) {
        self.emailId = emailId
        self.result = result
    }
}

public struct StoryGenerationBatch {
    public let cards: [InsightCard]
    public let outcomes: [StoryPromptOutcome]
    public let fallbackCount: Int
    
    public init(cards: [InsightCard], outcomes: [StoryPromptOutcome], fallbackCount: Int) {
        self.cards = cards
        self.outcomes = outcomes
        self.fallbackCount = fallbackCount
    }
}

public actor InsightEngine {
    public static let shared = InsightEngine()

    public func selectUnpromptedCandidates(from emails: [EmailListItem], promptStates: [Int: StoryPromptState], now: Date = Date()) async -> [EmailListItem] {
        let candidates = await newsletterCandidates(from: emails)
        return candidates.filter { email in
            guard let state = promptStates[email.id] else { return true }
            return state.canAttempt(at: now)
        }
    }

    public func generateBatch(from candidates: [EmailListItem], limit: Int = 12) async -> StoryGenerationBatch {
        let startedAt = Date()
        let preferenceContext = await preferenceContextText()
        var processableCandidates: [EmailListItem] = []
        processableCandidates.reserveCapacity(limit * 2)
        for email in candidates.prefix(limit * 3) {
            let inferredTheme = inferThemeTag(from: email)
            let shouldProcess = await InterestProfileStore.shared.shouldProcessNewsletter(
                themeTag: inferredTheme,
                sender: email.sender
            )
            if !shouldProcess {
                continue
            }
            processableCandidates.append(email)
            if processableCandidates.count >= limit * 2 {
                break
            }
        }
        guard !processableCandidates.isEmpty else {
            Telemetry.event("insights.generate.skipped", metadata: [
                "candidate_count": "\(candidates.count)",
                "processable_count": "0"
            ])
            return StoryGenerationBatch(cards: [], outcomes: [], fallbackCount: 0)
        }

        struct CandidateGenerationResult {
            let index: Int
            let cards: [InsightCard]
            let outcome: StoryPromptOutcome
            let fallbackUsed: Bool
        }

        let maxConcurrent = 3
        var generationResults: [CandidateGenerationResult] = []
        generationResults.reserveCapacity(processableCandidates.count)

        await withTaskGroup(of: CandidateGenerationResult.self) { group in
            var nextIndex = 0

            func enqueueTask() {
                guard nextIndex < processableCandidates.count else { return }
                let index = nextIndex
                let email = processableCandidates[index]
                nextIndex += 1
                group.addTask {
                    let inferredTheme = self.inferThemeTag(from: email)
                    do {
                        let generations = try await LLMProviderRouter.shared.summarizeNewsletterStories(
                            subject: email.subject,
                            snippet: email.snippet,
                            sender: email.sender,
                            body: nil,
                            preferenceContext: preferenceContext
                        )
                        guard !generations.isEmpty else {
                            return CandidateGenerationResult(
                                index: index,
                                cards: [],
                                outcome: StoryPromptOutcome(emailId: email.id, result: .empty),
                                fallbackUsed: false
                            )
                        }
                        let cards = generations.enumerated().map { itemIndex, generation in
                            InsightCard(
                                id: StableID.emailId(gmailId: "\(email.gmail_id)-story-\(itemIndex)"),
                                emailId: email.id,
                                gmailId: email.gmail_id,
                                accountEmail: email.account_email,
                                sender: email.sender,
                                senderName: email.sender_name,
                                subject: email.subject,
                                summary: generation.summary,
                                keyPoints: generation.keyPoints,
                                theme: NewsletterTheme(tag: generation.themeTag, confidence: generation.confidence)
                            )
                        }
                        return CandidateGenerationResult(
                            index: index,
                            cards: cards,
                            outcome: StoryPromptOutcome(emailId: email.id, result: .success),
                            fallbackUsed: false
                        )
                    } catch {
                        let fallback = self.fallbackGeneration(for: email, themeTag: inferredTheme)
                        let fallbackCard = InsightCard(
                            id: StableID.emailId(gmailId: "\(email.gmail_id)-story-0"),
                            emailId: email.id,
                            gmailId: email.gmail_id,
                            accountEmail: email.account_email,
                            sender: email.sender,
                            senderName: email.sender_name,
                            subject: email.subject,
                            summary: fallback.summary,
                            keyPoints: fallback.keyPoints,
                            theme: NewsletterTheme(tag: fallback.themeTag, confidence: fallback.confidence)
                        )
                        return CandidateGenerationResult(
                            index: index,
                            cards: [fallbackCard],
                            outcome: StoryPromptOutcome(emailId: email.id, result: .failed(reason: error.localizedDescription)),
                            fallbackUsed: true
                        )
                    }
                }
            }

            for _ in 0..<min(maxConcurrent, processableCandidates.count) {
                enqueueTask()
            }

            while let result = await group.next() {
                generationResults.append(result)
                enqueueTask()
            }
        }

        let sortedResults = generationResults.sorted { $0.index < $1.index }
        var cards: [InsightCard] = []
        var outcomes: [StoryPromptOutcome] = []
        var fallbackCount = 0
        for result in sortedResults {
            outcomes.append(result.outcome)
            if result.fallbackUsed {
                fallbackCount += 1
            }
            if cards.count >= limit {
                continue
            }
            let remaining = max(limit - cards.count, 0)
            cards.append(contentsOf: result.cards.prefix(remaining))
        }

        let successCount = outcomes.filter {
            if case .success = $0.result { return true }
            return false
        }.count
        let failedCount = outcomes.filter {
            if case .failed = $0.result { return true }
            return false
        }.count
        let emptyCount = outcomes.filter {
            if case .empty = $0.result { return true }
            return false
        }.count
        Telemetry.event("insights.generate.completed", metadata: [
            "candidate_count": "\(candidates.count)",
            "processable_count": "\(processableCandidates.count)",
            "cards_count": "\(cards.count)",
            "success_count": "\(successCount)",
            "failed_count": "\(failedCount)",
            "empty_count": "\(emptyCount)",
            "fallback_count": "\(fallbackCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
        ])
        return StoryGenerationBatch(cards: cards, outcomes: outcomes, fallbackCount: fallbackCount)
    }

    private func newsletterCandidates(from emails: [EmailListItem]) async -> [EmailListItem] {
        var candidates: [EmailListItem] = []
        let preferredAddress = await AccountInclusionStore.shared.primaryNewsletterAddress()

        for email in emails {
            guard await AccountInclusionStore.shared.isIncludedInNewsletterInsights(accountEmail: email.account_email) else {
                continue
            }
            guard isNewsletter(email) else {
                continue
            }
            if let preferredAddress,
               preferredAddress.caseInsensitiveCompare(email.account_email) != .orderedSame {
                continue
            }
            candidates.append(email)
        }

        return candidates.sorted { $0.received_at > $1.received_at }
    }

    private func isNewsletter(_ email: EmailListItem) -> Bool {
        let labels = Set(email.labels.map { $0.uppercased() })
        if labels.contains("CATEGORY_PROMOTIONS")
            || labels.contains("CATEGORY_FORUMS")
            || labels.contains("CATEGORY_SOCIAL")
            || labels.contains("CATEGORY_UPDATES") {
            return true
        }

        let sender = email.sender.lowercased()
        let subject = email.subject.lowercased()
        return sender.contains("newsletter")
            || sender.contains("noreply")
            || sender.contains("no-reply")
            || subject.contains("newsletter")
            || subject.contains("digest")
            || subject.contains("weekly roundup")
            || sender.contains("substack")
    }

    nonisolated private func inferThemeTag(from email: EmailListItem) -> String {
        let source = "\(email.subject) \(email.snippet)".lowercased()
        if source.contains("product") || source.contains("roadmap") {
            return "ProductMgmt"
        }
        if source.contains("watch") || source.contains("timepiece") {
            return "Watches"
        }
        if source.contains("startup") || source.contains("funding") {
            return "Startups"
        }
        if source.contains("ai") || source.contains("llm") {
            return "AI"
        }
        return "General"
    }

    nonisolated private func fallbackGeneration(for email: EmailListItem, themeTag: String) -> InsightGenerationResult {
        InsightGenerationResult(
            summary: email.snippet.isEmpty ? email.subject : email.snippet,
            keyPoints: [
                String(email.subject.prefix(80)),
                String(email.snippet.prefix(80)),
                "Open full newsletter for full details."
            ],
            themeTag: themeTag,
            confidence: 0.35
        )
    }

    private func preferenceContextText() async -> String {
        let profile = await InterestProfileStore.shared.currentProfile()
        let preferredThemes = profile.themeScores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        let dislikedThemes = profile.themeScores
            .filter { $0.value < 0 }
            .sorted { $0.value < $1.value }
            .prefix(3)
            .map { $0.key }

        let preferredSenders = profile.senderScores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        let dislikedSenders = profile.senderScores
            .filter { $0.value < 0 }
            .sorted { $0.value < $1.value }
            .prefix(3)
            .map { $0.key }

        return """
        preferredThemes=\(preferredThemes.joined(separator: ","))
        dislikedThemes=\(dislikedThemes.joined(separator: ","))
        preferredSenders=\(preferredSenders.joined(separator: ","))
        dislikedSenders=\(dislikedSenders.joined(separator: ","))
        """
    }
}
