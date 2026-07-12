import Foundation

public actor DailyBriefingEngine {
    public static let shared = DailyBriefingEngine()

    private let maxCandidatesPerBucket = 12

    public func buildPayload(from emails: [EmailListItem], sinceDate: Date?) async -> DailyBriefingPayload {
        let startedAt = Date()
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        guard hasKey else {
            Telemetry.event("daily_briefing.generate.completed", metadata: [
                "candidate_count": "0",
                "item_count": "0",
                "has_key": "false",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
            return emptyPayload(sinceDate: sinceDate)
        }

        let includedEmails = await includedAccounts(from: emails)
        let candidates = buildCandidates(from: includedEmails)
        let candidateCount = candidates.urgentToday.count
            + candidates.criticalReminders.count
            + candidates.unreadFromYesterday.count
            + candidates.receiptsAndTransactions.count

        guard candidateCount > 0 else {
            Telemetry.event("daily_briefing.generate.completed", metadata: [
                "candidate_count": "0",
                "item_count": "0",
                "has_key": "true",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
            return DailyBriefingPayload(
                generatedAt: Date(),
                sinceDate: sinceDate,
                introText: "Your inbox looks clear — no urgent items, reminders, or receipts to highlight today.",
                sections: []
            )
        }

        let emailById = Dictionary(uniqueKeysWithValues: includedEmails.map { ($0.id, $0) })
        do {
            let response = try await LLMProviderRouter.shared.generateDailyBrief(candidates: candidates)
            let payload = DailyBriefMapper.payload(
                from: response,
                emailById: emailById,
                generatedAt: Date(),
                sinceDate: sinceDate
            )
            Telemetry.event("daily_briefing.generate.completed", metadata: [
                "candidate_count": "\(candidateCount)",
                "item_count": "\(payload.items.count)",
                "section_count": "\(payload.sections.count)",
                "has_key": "true",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
            return payload
        } catch {
            logError("Daily brief generation failed: \(error)", category: "Brief")
            Telemetry.event("daily_briefing.generate.failed", metadata: [
                "candidate_count": "\(candidateCount)",
                "error_type": "\(type(of: error))",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
            return DailyBriefingPayload(
                generatedAt: Date(),
                sinceDate: sinceDate,
                introText: "Couldn't generate your brief right now. Try refreshing in a moment.",
                sections: []
            )
        }
    }

    private func emptyPayload(sinceDate: Date?) -> DailyBriefingPayload {
        DailyBriefingPayload(
            generatedAt: Date(),
            sinceDate: sinceDate,
            introText: "Add an API key in Settings to generate your daily executive brief.",
            sections: []
        )
    }

    private func buildCandidates(from emails: [EmailListItem]) -> DailyBriefCandidates {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayLabel = formatter.string(from: today)
        let yesterdayLabel = formatter.string(from: yesterday)

        var urgentToday: [EmailListItem] = []
        var criticalReminders: [EmailListItem] = []
        var unreadFromYesterday: [EmailListItem] = []
        var receipts: [EmailListItem] = []
        var seenIds = Set<Int>()

        for email in emails {
            guard isInInbox(email), let received = isoDate(from: email.received_at) else { continue }
            let receivedDay = calendar.startOfDay(for: received)

            if isReceiptOrTransaction(email), receivedDay >= yesterday {
                append(email, to: &receipts, seen: &seenIds)
            }

            if isReminderCandidate(email), !email.is_read {
                append(email, to: &criticalReminders, seen: &seenIds)
            }

            if calendar.isDate(receivedDay, inSameDayAs: yesterday), !email.is_read, !isNewsletterOrPromo(email) {
                append(email, to: &unreadFromYesterday, seen: &seenIds)
            }

            if calendar.isDateInToday(received), !email.is_read, !isNewsletterOrPromo(email) {
                append(email, to: &urgentToday, seen: &seenIds)
            }
        }

        return DailyBriefCandidates(
            todayDate: todayLabel,
            yesterdayDate: yesterdayLabel,
            urgentToday: mapCandidates(Array(urgentToday.prefix(maxCandidatesPerBucket))),
            criticalReminders: mapCandidates(Array(criticalReminders.prefix(maxCandidatesPerBucket))),
            unreadFromYesterday: mapCandidates(Array(unreadFromYesterday.prefix(maxCandidatesPerBucket))),
            receiptsAndTransactions: mapCandidates(Array(receipts.prefix(maxCandidatesPerBucket)))
        )
    }

    private func append(_ email: EmailListItem, to list: inout [EmailListItem], seen: inout Set<Int>) {
        guard seen.insert(email.id).inserted else { return }
        list.append(email)
    }

    private func mapCandidates(_ emails: [EmailListItem]) -> [DailyBriefEmailCandidate] {
        emails.map { email in
            DailyBriefEmailCandidate(
                emailId: email.id,
                sender: email.sender,
                senderName: email.sender_name,
                subject: email.subject,
                snippet: email.snippet,
                receivedAt: email.received_at,
                isRead: email.is_read,
                labels: email.labels
            )
        }
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

    private func isInInbox(_ email: EmailListItem) -> Bool {
        email.labels.contains { $0.uppercased() == "INBOX" }
    }

    private func isNewsletterOrPromo(_ email: EmailListItem) -> Bool {
        let subject = email.subject.lowercased()
        let labels = Set(email.labels.map { $0.uppercased() })

        if labels.contains("CATEGORY_PROMOTIONS") || labels.contains("CATEGORY_FORUMS") || labels.contains("CATEGORY_SOCIAL") {
            return true
        }
        if subject.contains("newsletter") || subject.contains("digest") || subject.contains("weekly roundup") {
            return true
        }
        if subject.contains("unsubscribe") && !isReceiptOrTransaction(email) {
            return true
        }
        return false
    }

    private func isReceiptOrTransaction(_ email: EmailListItem) -> Bool {
        let subject = email.subject.lowercased()
        let snippet = email.snippet.lowercased()
        let sender = email.sender.lowercased()
        let labels = Set(email.labels.map { $0.uppercased() })

        if labels.contains("CATEGORY_PURCHASES") || labels.contains("CATEGORY_UPDATES") {
            return true
        }

        let keywords = [
            "receipt", "invoice", "order", "payment", "transaction", "charged", "billing",
            "statement", "shipped", "delivery", "refund", "purchase", "subscription",
            "your order", "order confirmation", "payment received", "account activity"
        ]
        if keywords.contains(where: { subject.contains($0) || snippet.contains($0) }) {
            return true
        }
        if sender.contains("billing") || sender.contains("payments") || sender.contains("orders@") {
            return true
        }
        return false
    }

    private func isReminderCandidate(_ email: EmailListItem) -> Bool {
        let subject = email.subject.lowercased()
        let snippet = email.snippet.lowercased()
        let sender = email.sender.lowercased()
        let labels = Set(email.labels.map { $0.uppercased() })

        if labels.contains("CATEGORY_UPDATES") && isReceiptOrTransaction(email) {
            return false
        }
        if sender.contains("calendar") || subject.contains("invite") || subject.contains("invitation") {
            return true
        }
        let keywords = ["reminder", "due", "deadline", "expires", "expiration", "action required", "overdue", "renewal"]
        return keywords.contains { subject.contains($0) || snippet.contains($0) }
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
