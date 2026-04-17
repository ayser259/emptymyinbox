import Foundation

public actor DailyBriefingEngine {
    public static let shared = DailyBriefingEngine()

    public func buildPayload(from emails: [EmailListItem], sinceDate: Date?) async -> DailyBriefingPayload {
        let startedAt = Date()
        let includedEmails = await includedAccounts(from: emails)
        let filtered = filterRelevantEmails(from: includedEmails, sinceDate: sinceDate)
        let topItems = Array(filtered.prefix(8))
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        let classificationResult = await classifyEmails(topItems, hasKey: hasKey)
        let briefingItems = classificationResult.items

        Telemetry.event("daily_briefing.generate.completed", metadata: [
            "candidate_count": "\(filtered.count)",
            "included_count": "\(topItems.count)",
            "item_count": "\(briefingItems.count)",
            "has_key": "\(hasKey)",
            "fallback_count": "\(classificationResult.fallbackCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
        ])
        return DailyBriefingPayload(
            generatedAt: Date(),
            sinceDate: sinceDate,
            introText: "I've monitored your selected accounts. Here are the top things to know since you last checked.",
            items: briefingItems
        )
    }

    private func classifyEmails(_ emails: [EmailListItem], hasKey: Bool) async -> (items: [DailyBriefingItem], fallbackCount: Int) {
        guard !emails.isEmpty else { return ([], 0) }
        if !hasKey {
            return (emails.map { item in
                DailyBriefingItem(
                    id: item.id,
                    emailId: item.id,
                    gmailId: item.gmail_id,
                    threadId: nil,
                    accountEmail: item.account_email,
                    sender: item.sender,
                    senderName: item.sender_name,
                    subject: item.subject,
                    snippet: item.snippet,
                    receivedAt: item.received_at,
                    type: classifyType(for: item)
                )
            }, 0)
        }

        let maxConcurrent = 3
        var results = Array<DailyBriefingItem?>(repeating: nil, count: emails.count)
        var fallbackCount = 0

        await withTaskGroup(of: (Int, DailyBriefingItem, Bool).self) { group in
            var nextIndex = 0

            func enqueueTask() {
                guard nextIndex < emails.count else { return }
                let index = nextIndex
                let email = emails[index]
                nextIndex += 1
                group.addTask {
                    let type: BriefingItemType
                    var usedFallback = false
                    do {
                        type = try await LLMProviderRouter.shared.classifyBriefingItem(
                            subject: email.subject,
                            snippet: email.snippet,
                            sender: email.sender
                        )
                    } catch {
                        type = self.classifyType(for: email)
                        usedFallback = true
                    }
                    let item = DailyBriefingItem(
                        id: email.id,
                        emailId: email.id,
                        gmailId: email.gmail_id,
                        threadId: nil,
                        accountEmail: email.account_email,
                        sender: email.sender,
                        senderName: email.sender_name,
                        subject: email.subject,
                        snippet: email.snippet,
                        receivedAt: email.received_at,
                        type: type
                    )
                    return (index, item, usedFallback)
                }
            }

            for _ in 0..<min(maxConcurrent, emails.count) {
                enqueueTask()
            }

            while let (index, item, usedFallback) = await group.next() {
                results[index] = item
                if usedFallback {
                    fallbackCount += 1
                }
                enqueueTask()
            }
        }

        return (results.compactMap { $0 }, fallbackCount)
    }

    private func includedAccounts(from emails: [EmailListItem]) async -> [EmailListItem] {
        var included: [EmailListItem] = []
        for email in emails {
            if await AccountInclusionStore.shared.isIncludedInDailyBriefing(accountEmail: email.account_email) {
                included.append(email)
            }
        }
        return included
    }

    private func filterRelevantEmails(from emails: [EmailListItem], sinceDate: Date?) -> [EmailListItem] {
        emails
            .filter { !$0.is_read }
            .filter { !isNewsletter($0) }
            .filter { email in
                guard let sinceDate else { return true }
                guard let receivedDate = isoDate(from: email.received_at) else { return true }
                return receivedDate >= sinceDate
            }
            .sorted { $0.received_at > $1.received_at }
    }

    private func isNewsletter(_ email: EmailListItem) -> Bool {
        let subject = email.subject.lowercased()
        let sender = email.sender.lowercased()
        let labels = Set(email.labels.map { $0.uppercased() })

        if labels.contains("CATEGORY_PROMOTIONS") || labels.contains("CATEGORY_FORUMS") || labels.contains("CATEGORY_SOCIAL") {
            return true
        }
        if subject.contains("newsletter") || subject.contains("digest") || subject.contains("weekly roundup") {
            return true
        }
        if sender.contains("newsletter") || sender.contains("noreply") || sender.contains("no-reply") {
            return true
        }
        return false
    }

    nonisolated private func classifyType(for email: EmailListItem) -> BriefingItemType {
        let subject = email.subject.lowercased()
        let sender = email.sender.lowercased()
        let snippet = email.snippet.lowercased()

        if subject.contains("invite") || subject.contains("meeting") || sender.contains("calendar") {
            return .calendarInvite
        }
        if subject.contains("urgent")
            || subject.contains("action required")
            || subject.contains("security alert")
            || snippet.contains("immediately") {
            return .urgentNotification
        }
        return .directCommunication
    }

    private func isoDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
