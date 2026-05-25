//
//  ReplyRecipientResolver.swift
//  EmptyMyInboxShared
//

import Foundation

/// Computes reply / reply-all recipient sets from a Gmail message and account identity.
public enum ReplyRecipientResolver {

    public static func resolve(
        original: GmailMessage,
        accountEmail: String,
        mode: ReplyMode,
        gmailService: GmailAPIService = .shared
    ) -> ReplyRecipientSet {
        let headers = gmailService.extractHeaders(from: original.payload)
        return resolve(headers: headers, accountEmail: accountEmail, mode: mode)
    }

    public static func resolve(
        email: EmailDetail,
        mode: ReplyMode,
        gmailMessage: GmailMessage? = nil,
        gmailService: GmailAPIService = .shared
    ) -> ReplyRecipientSet {
        if let gmailMessage {
            return resolve(original: gmailMessage, accountEmail: email.account_email, mode: mode, gmailService: gmailService)
        }
        // Fallback when full message not loaded yet.
        var headers: [String: String] = [
            "from": formatFrom(email),
            "to": email.recipients_to ?? "",
            "cc": email.recipients_cc ?? "",
            "subject": email.subject
        ]
        if let replyTo = email.sender.contains("@") ? email.sender : nil {
            headers["reply-to"] = replyTo
        }
        return resolve(headers: headers, accountEmail: email.account_email, mode: mode)
    }

    public static func resolve(
        headers: [String: String],
        accountEmail: String,
        mode: ReplyMode
    ) -> ReplyRecipientSet {
        let selfEmails = normalizedIdentityEmails(accountEmail)
        let replyToHeader = headers["reply-to"] ?? ""
        let fromHeader = headers["from"] ?? ""
        let toHeader = headers["to"] ?? ""
        let ccHeader = headers["cc"] ?? ""

        let primaryReplyTarget = parseAddresses(from: replyToHeader.isEmpty ? fromHeader : replyToHeader)
        let originalTo = parseAddresses(from: toHeader)
        let originalCc = parseAddresses(from: ccHeader)
        let originalFrom = parseAddresses(from: fromHeader)

        switch mode {
        case .reply:
            let to = primaryReplyTarget.filter { !selfEmails.contains($0.email.lowercased()) }
            return ReplyRecipientSet(to: dedupe(to))

        case .replyAll:
            var toSet: [ReplyMailboxAddress] = primaryReplyTarget
            for addr in originalTo + originalFrom {
                if !toSet.contains(where: { $0.email.lowercased() == addr.email.lowercased() }) {
                    toSet.append(addr)
                }
            }
            toSet = toSet.filter { !selfEmails.contains($0.email.lowercased()) }

            var ccSet = originalCc.filter { addr in
                !selfEmails.contains(addr.email.lowercased())
                    && !toSet.contains(where: { $0.email.lowercased() == addr.email.lowercased() })
            }
            return ReplyRecipientSet(to: dedupe(toSet), cc: dedupe(ccSet))
        }
    }

    /// True when Reply All would add recipients beyond a single direct reply (e.g. other To/Cc parties).
    public static func isReplyAllMeaningful(
        email: EmailDetail,
        gmailMessage: GmailMessage? = nil,
        accountEmail: String? = nil,
        gmailService: GmailAPIService = .shared
    ) -> Bool {
        let account = accountEmail ?? email.account_email
        let reply = resolve(email: email, mode: .reply, gmailMessage: gmailMessage, gmailService: gmailService)
        let replyAll = resolve(email: email, mode: .replyAll, gmailMessage: gmailMessage, gmailService: gmailService)
        return recipientFingerprint(reply) != recipientFingerprint(replyAll)
    }

    public static func isReplyAllMeaningful(
        original: GmailMessage,
        accountEmail: String,
        gmailService: GmailAPIService = .shared
    ) -> Bool {
        let reply = resolve(original: original, accountEmail: accountEmail, mode: .reply, gmailService: gmailService)
        let replyAll = resolve(original: original, accountEmail: accountEmail, mode: .replyAll, gmailService: gmailService)
        return recipientFingerprint(reply) != recipientFingerprint(replyAll)
    }

    private static func recipientFingerprint(_ set: ReplyRecipientSet) -> Set<String> {
        var emails = Set(set.to.map { $0.email.lowercased() })
        emails.formUnion(set.cc.map { $0.email.lowercased() })
        emails.formUnion(set.bcc.map { $0.email.lowercased() })
        return emails
    }

    public static func replySubject(fromOriginalSubject raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Re: " }
        if trimmed.lowercased().hasPrefix("re:") { return trimmed }
        return "Re: \(trimmed)"
    }

    // MARK: - Parsing

    public static func parseAddresses(from headerValue: String) -> [ReplyMailboxAddress] {
        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [ReplyMailboxAddress] = []
        var current = ""
        var inQuotes = false
        var angleDepth = 0

        for char in trimmed {
            if char == "\"" { inQuotes.toggle() }
            if !inQuotes {
                if char == "<" { angleDepth += 1 }
                if char == ">" { angleDepth = max(0, angleDepth - 1) }
            }
            if char == "," && !inQuotes && angleDepth == 0 {
                if let parsed = parseSingleAddress(current) {
                    results.append(parsed)
                }
                current = ""
            } else {
                current.append(char)
            }
        }
        if let parsed = parseSingleAddress(current) {
            results.append(parsed)
        }
        return dedupe(results)
    }

    public static func parseSingleAddress(_ raw: String) -> ReplyMailboxAddress? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if let open = s.firstIndex(of: "<"), let close = s[open...].firstIndex(of: ">") {
            let email = String(s[s.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            let namePart = String(s[..<open]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard email.contains("@") else { return nil }
            return ReplyMailboxAddress(email: email, displayName: namePart.nilIfEmpty)
        }

        if s.contains("@") {
            return ReplyMailboxAddress(email: s)
        }
        return nil
    }

    public static func formattedHeaderList(_ addresses: [ReplyMailboxAddress]) -> String {
        addresses.map(\.formattedForHeader).joined(separator: ", ")
    }

    // MARK: - Private

    private static func formatFrom(_ email: EmailDetail) -> String {
        if let name = email.sender_name, !name.isEmpty {
            return "\"\(name)\" <\(email.sender)>"
        }
        return email.sender
    }

    private static func normalizedIdentityEmails(_ accountEmail: String) -> Set<String> {
        let lower = accountEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return [lower]
    }

    private static func dedupe(_ list: [ReplyMailboxAddress]) -> [ReplyMailboxAddress] {
        var seen = Set<String>()
        var out: [ReplyMailboxAddress] = []
        for item in list {
            let key = item.email.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(item)
        }
        return out
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
