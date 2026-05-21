//
//  GmailAPIService+Drafts.swift
//  EmptyMyInboxShared
//
//  Reply drafts: RFC 2822 MIME, Gmail drafts.create / update / send / delete.
//

import Foundation

// MARK: - Models

public struct GmailDraftResource: Codable {
    public let id: String
    public let message: GmailMessage?

    public init(id: String, message: GmailMessage? = nil) {
        self.id = id
        self.message = message
    }
}

/// Drafts.create returns `id` plus a `message` that is often too partial to decode as `GmailMessage`.
private struct GmailDraftCreateAPIResponse: Decodable {
    let id: String
}

// MARK: - MIME + drafts

extension GmailAPIService {

    /// Builds a plain-text reply MIME message for Gmail `users.drafts` / `messages.send`.
    public func buildReplyRFC2822Message(
        account: GmailAccount,
        original: GmailMessage,
        envelope: ReplyDraftEnvelope
    ) -> String {
        let headers = extractHeaders(from: original.payload)
        let fromLine = rfc822FromLine(account: account)

        let messageId = headers["message-id"] ?? ""
        let priorReferences = headers["references"] ?? ""
        let referencesLine: String = {
            if messageId.isEmpty { return priorReferences }
            if priorReferences.isEmpty { return messageId }
            return "\(priorReferences) \(messageId)"
        }()

        let subjectLine = rfc822FoldSubject(
            ReplyRecipientResolver.replySubject(fromOriginalSubject: envelope.subject)
        )

        var body = envelope.body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if envelope.includeQuotedOriginal {
            let quote = quotedOriginalBlock(original: original, cachedDetail: nil)
            if !quote.isEmpty {
                if !body.isEmpty { body += "\n\n" }
                body += quote
            }
        }

        var headerLines: [String] = []
        headerLines.append("MIME-Version: 1.0")
        headerLines.append("Content-Type: text/plain; charset=UTF-8")
        headerLines.append("Content-Transfer-Encoding: 8bit")
        headerLines.append("From: \(fromLine)")

        let toLine = ReplyRecipientResolver.formattedHeaderList(envelope.to)
        if !toLine.isEmpty {
            headerLines.append("To: \(toLine)")
        }
        let ccLine = ReplyRecipientResolver.formattedHeaderList(envelope.cc)
        if !ccLine.isEmpty {
            headerLines.append("Cc: \(ccLine)")
        }
        let bccLine = ReplyRecipientResolver.formattedHeaderList(envelope.bcc)
        if !bccLine.isEmpty {
            headerLines.append("Bcc: \(bccLine)")
        }

        headerLines.append("Subject: \(subjectLine)")
        if !messageId.isEmpty {
            headerLines.append("In-Reply-To: \(messageId)")
        }
        if !referencesLine.isEmpty {
            headerLines.append("References: \(referencesLine)")
        }

        let headerBlock = headerLines.joined(separator: "\r\n")
        return "\(headerBlock)\r\n\r\n\(body)"
    }

    /// Legacy single-recipient builder (plain reply body only).
    public func buildReplyRFC2822Message(
        account: GmailAccount,
        original: GmailMessage,
        replyBody: String
    ) -> String {
        let set = ReplyRecipientResolver.resolve(original: original, accountEmail: account.email, mode: .reply)
        let headers = extractHeaders(from: original.payload)
        let subject = ReplyRecipientResolver.replySubject(fromOriginalSubject: headers["subject"] ?? "")
        let envelope = ReplyDraftEnvelope(to: set.to, subject: subject, body: replyBody)
        return buildReplyRFC2822Message(account: account, original: original, envelope: envelope)
    }

    public func createReplyDraft(
        account: GmailAccount,
        original: GmailMessage,
        envelope: ReplyDraftEnvelope
    ) async throws -> String {
        let raw = buildReplyRFC2822Message(account: account, original: original, envelope: envelope)
        let draft = try await createDraft(account: account, rawRFC2822: raw, threadId: original.threadId)
        Telemetry.event("gmail.draft_create", metadata: [
            "thread_id": original.threadId,
            "mode": envelope.cc.isEmpty ? "reply" : "reply_all"
        ])
        return draft.id
    }

    public func createReplyDraft(
        account: GmailAccount,
        original: GmailMessage,
        body: String
    ) async throws -> String {
        try await createReplyDraft(
            account: account,
            original: original,
            envelope: ReplyRecipientResolver.resolve(original: original, accountEmail: account.email, mode: .reply)
                .toEnvelope(subject: ReplyRecipientResolver.replySubject(
                    fromOriginalSubject: extractHeaders(from: original.payload)["subject"] ?? ""
                ), body: body)
        )
    }

    public func updateReplyDraft(
        account: GmailAccount,
        draftId: String,
        original: GmailMessage,
        envelope: ReplyDraftEnvelope
    ) async throws {
        let raw = buildReplyRFC2822Message(account: account, original: original, envelope: envelope)
        try await updateDraft(account: account, draftId: draftId, rawRFC2822: raw, threadId: original.threadId)
        Telemetry.event("gmail.draft_update", metadata: [
            "draft_id": draftId
        ])
    }

    public func updateReplyDraft(
        account: GmailAccount,
        draftId: String,
        original: GmailMessage,
        body: String
    ) async throws {
        let headers = extractHeaders(from: original.payload)
        let subject = ReplyRecipientResolver.replySubject(fromOriginalSubject: headers["subject"] ?? "")
        let set = ReplyRecipientResolver.resolve(original: original, accountEmail: account.email, mode: .reply)
        try await updateReplyDraft(
            account: account,
            draftId: draftId,
            original: original,
            envelope: set.toEnvelope(subject: subject, body: body)
        )
    }

    public func createDraft(
        account: GmailAccount,
        rawRFC2822: String,
        threadId: String
    ) async throws -> GmailDraftResource {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/drafts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "message": [
                "raw": Self.base64URLEncodeRFC822(rawRFC2822),
                "threadId": threadId
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.apiError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GmailAPIError.apiError("Failed to create draft (\(http.statusCode)): \(snippet)")
        }
        let decoded = try JSONDecoder().decode(GmailDraftCreateAPIResponse.self, from: data)
        return GmailDraftResource(id: decoded.id, message: nil)
    }

    public func updateDraft(
        account: GmailAccount,
        draftId: String,
        rawRFC2822: String,
        threadId: String
    ) async throws {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/drafts/\(draftId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "id": draftId,
            "message": [
                "raw": Self.base64URLEncodeRFC822(rawRFC2822),
                "threadId": threadId
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.apiError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GmailAPIError.apiError("Failed to update draft (\(http.statusCode)): \(snippet)")
        }
    }

    public func sendDraft(account: GmailAccount, draftId: String) async throws -> GmailMessage {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/drafts/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["id": draftId]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.apiError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GmailAPIError.apiError("Failed to send draft (\(http.statusCode)): \(snippet)")
        }
        let sent = Self.decodeSentMessage(from: data)
        var telemetryMeta: [String: String] = ["draft_id": draftId]
        if !sent.id.isEmpty {
            telemetryMeta["message_id"] = Telemetry.hashForDiagnostics(sent.id)
        }
        if !sent.threadId.isEmpty {
            telemetryMeta["thread_id"] = Telemetry.hashForDiagnostics(sent.threadId)
        }
        Telemetry.event("gmail.draft_send", metadata: telemetryMeta)
        return sent
    }

    /// Best-effort decode after `drafts.send`. Never throws: send already succeeded when this runs.
    private static func decodeSentMessage(from data: Data) -> GmailMessage {
        if data.isEmpty {
            return GmailMessage(
                id: "",
                threadId: "",
                snippet: "",
                payload: nil,
                labelIds: [],
                internalDate: ""
            )
        }
        if let full = try? JSONDecoder().decode(GmailMessage.self, from: data) {
            return full
        }
        struct MinimalSent: Decodable {
            let id: String?
            let threadId: String?
            let snippet: String?
        }
        if let minimal = try? JSONDecoder().decode(MinimalSent.self, from: data) {
            return GmailMessage(
                id: minimal.id ?? "",
                threadId: minimal.threadId ?? "",
                snippet: minimal.snippet ?? "",
                payload: nil,
                labelIds: [],
                internalDate: ""
            )
        }
        return GmailMessage(
            id: "",
            threadId: "",
            snippet: "",
            payload: nil,
            labelIds: [],
            internalDate: ""
        )
    }

    public func deleteDraft(account: GmailAccount, draftId: String) async throws {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/drafts/\(draftId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.apiError("Invalid response")
        }
        guard http.statusCode == 204 || http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GmailAPIError.apiError("Failed to delete draft (\(http.statusCode)): \(snippet)")
        }
        Telemetry.event("gmail.draft_delete", metadata: ["draft_id": draftId])
    }

    // MARK: - Quoted original

    func quotedOriginalBlock(original: GmailMessage, cachedDetail: EmailDetail?) -> String {
        let headers = extractHeaders(from: original.payload)
        let from = headers["from"] ?? cachedDetail?.sender ?? ""
        let date = headers["date"] ?? cachedDetail?.received_at ?? ""
        let subject = headers["subject"] ?? cachedDetail?.subject ?? ""

        var body = ""
        if let detail = cachedDetail, !detail.body_text.isEmpty {
            body = detail.body_text
        } else {
            let parsed = parseEmailDetail(from: original, accountEmail: cachedDetail?.account_email ?? "", emailId: cachedDetail?.id ?? 0)
            body = parsed.body_text
        }

        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")

        return """
        On \(date), \(from) wrote regarding "\(subject)":
        \(lines)
        """
    }

    // MARK: - Private helpers

    private static func base64URLEncodeRFC822(_ raw: String) -> String {
        Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func rfc822FromLine(account: GmailAccount) -> String {
        let email = account.email
        guard let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return email
        }
        let safeName = name.replacingOccurrences(of: "\"", with: "")
        return "\"\(safeName)\" <\(email)>"
    }

    /// Avoid bare newlines inside a subject header line.
    private func rfc822FoldSubject(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

// MARK: - ReplyRecipientSet helpers

private extension ReplyRecipientSet {
    func toEnvelope(subject: String, body: String, includeQuotedOriginal: Bool = false) -> ReplyDraftEnvelope {
        ReplyDraftEnvelope(
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            includeQuotedOriginal: includeQuotedOriginal
        )
    }
}
