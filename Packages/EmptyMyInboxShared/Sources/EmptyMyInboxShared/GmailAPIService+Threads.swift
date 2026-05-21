//
//  GmailAPIService+Threads.swift
//  EmptyMyInboxShared
//
//  Gmail thread fetch and parsing for full-conversation reading.
//

import Foundation

// MARK: - Gmail Thread API models

public struct GmailThread: Codable {
    public let id: String
    public let snippet: String?
    public let historyId: String?
    public let messages: [GmailMessage]?

    public init(
        id: String,
        snippet: String? = nil,
        historyId: String? = nil,
        messages: [GmailMessage]? = nil
    ) {
        self.id = id
        self.snippet = snippet
        self.historyId = historyId
        self.messages = messages
    }
}

extension GmailAPIService {
    /// Fetch a full Gmail thread (all messages with bodies).
    public func getThread(
        for account: GmailAccount,
        threadId: String,
        format: String = "full"
    ) async throws -> GmailThread {
        let token = try await getValidAccessToken(for: account)
        var components = URLComponents(string: "\(baseURL)/users/me/threads/\(threadId)")!
        components.queryItems = [URLQueryItem(name: "format", value: format)]

        guard let url = components.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get thread: \(response)")
        }

        return try JSONDecoder().decode(GmailThread.self, from: data)
    }

    /// Parse every message in a thread into `EmailDetail`, oldest-first.
    public func parseThreadDetails(
        from thread: GmailThread,
        accountEmail: String
    ) -> [EmailDetail] {
        guard let messages = thread.messages, !messages.isEmpty else { return [] }

        let sorted = messages.sorted { lhs, rhs in
            let left = parseDate(from: lhs.internalDate) ?? .distantPast
            let right = parseDate(from: rhs.internalDate) ?? .distantPast
            return left < right
        }

        return sorted.map { message in
            let emailId = getEmailId(for: message.id)
            return parseEmailDetail(from: message, accountEmail: accountEmail, emailId: emailId)
        }
    }

    /// Load full thread conversation details from Gmail.
    public func loadThreadConversation(
        for account: GmailAccount,
        threadId: String
    ) async throws -> [EmailDetail] {
        let thread = try await getThread(for: account, threadId: threadId, format: "full")
        return parseThreadDetails(from: thread, accountEmail: account.email)
    }

    private func parseDate(from internalDate: String) -> Date? {
        if let milliseconds = Double(internalDate) {
            return Date(timeIntervalSince1970: milliseconds / 1000.0)
        }
        return nil
    }
}
