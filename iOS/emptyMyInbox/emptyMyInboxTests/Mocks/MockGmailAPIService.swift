//
//  MockGmailAPIService.swift
//  emptyMyInboxTests
//
//  Mock implementation of GmailAPIService for testing
//

import Foundation
@testable import emptyMyInbox

class MockGmailAPIService {
    // Test data storage
    var accounts: [GmailAccount] = []
    var messages: [String: GmailMessage] = [:] // keyed by messageId
    var messageReferences: [GmailMessageReference] = []
    var labels: [String: String] = [:]
    
    // Behavior control
    var shouldFailTokenRefresh = false
    var shouldFailAPI = false
    var shouldReturnRateLimit = false
    var apiError: GmailAPIError?
    var delay: TimeInterval = 0
    
    // Call tracking
    var tokenRefreshCallCount = 0
    var apiCallCount = 0
    
    // Initialize with test data
    init() {
        setupDefaultTestData()
    }
    
    private func setupDefaultTestData() {
        // Create a default test account
        let testAccount = GmailAccount(
            id: "test@example.com",
            email: "test@example.com",
            name: "Test User",
            accessToken: "test_access_token",
            refreshToken: "test_refresh_token",
            tokenExpiry: Date().addingTimeInterval(3600),
            lastSync: nil,
            unreadEmailsNextPageToken: nil
        )
        accounts.append(testAccount)
        
        // Create default test messages
        let testMessage = createTestGmailMessage(
            id: "msg1",
            subject: "Test Email",
            sender: "sender@example.com",
            snippet: "Test snippet"
        )
        messages["msg1"] = testMessage
        messageReferences.append(GmailMessageReference(id: "msg1", threadId: "thread1"))
        
        // Default labels
        labels = [
            "INBOX": "Inbox",
            "UNREAD": "Unread",
            "STARRED": "Starred"
        ]
    }
    
    // MARK: - Test Data Helpers
    
    func createTestGmailMessage(
        id: String,
        subject: String,
        sender: String,
        snippet: String,
        isRead: Bool = false,
        isStarred: Bool = false
    ) -> GmailMessage {
        let headers = [
            GmailHeader(name: "Subject", value: subject),
            GmailHeader(name: "From", value: sender),
            GmailHeader(name: "To", value: "test@example.com")
        ]
        
        var labelIds = ["INBOX"]
        if !isRead {
            labelIds.append("UNREAD")
        }
        if isStarred {
            labelIds.append("STARRED")
        }
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let internalDate = String(Int(Date().timeIntervalSince1970 * 1000))
        
        return GmailMessage(
            id: id,
            threadId: "thread_\(id)",
            snippet: snippet,
            payload: payload,
            labelIds: labelIds,
            internalDate: internalDate
        )
    }
    
    func addTestMessage(_ message: GmailMessage) {
        messages[message.id] = message
        messageReferences.append(GmailMessageReference(id: message.id, threadId: message.threadId))
    }
    
    func addTestAccount(_ account: GmailAccount) {
        accounts.append(account)
    }
    
    // MARK: - Mock API Methods
    
    func getAllAccounts() -> [GmailAccount] {
        return accounts
    }
    
    func getAccount(byEmail email: String) -> GmailAccount? {
        return accounts.first { $0.email == email }
    }
    
    func getUserProfile(for account: GmailAccount) async throws -> GmailProfile {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        apiCallCount += 1
        return GmailProfile(emailAddress: account.email)
    }
    
    func listMessages(
        for account: GmailAccount,
        query: String = "is:unread in:inbox",
        maxResults: Int = 50,
        pageToken: String? = nil
    ) async throws -> (messages: [GmailMessageReference], nextPageToken: String?) {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        if shouldReturnRateLimit {
            throw GmailAPIError.apiError("429 Rate Limit Exceeded")
        }
        
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        apiCallCount += 1
        
        let filteredMessages = messageReferences.filter { ref in
            if let message = messages[ref.id] {
                if query.contains("is:unread") && message.labelIds.contains("UNREAD") {
                    return true
                }
                if query.contains("is:starred") && message.labelIds.contains("STARRED") {
                    return true
                }
                return true
            }
            return false
        }
        
        let limited = Array(filteredMessages.prefix(maxResults))
        return (limited, nil)
    }
    
    func getMessage(
        for account: GmailAccount,
        messageId: String,
        format: String = "full"
    ) async throws -> GmailMessage {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        if shouldReturnRateLimit {
            throw GmailAPIError.apiError("429 Rate Limit Exceeded")
        }
        
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        apiCallCount += 1
        
        guard let message = messages[messageId] else {
            throw GmailAPIError.apiError("Message not found: \(messageId)")
        }
        
        return message
    }
    
    func batchGetMessagesMetadata(
        for account: GmailAccount,
        messageIds: [String]
    ) async throws -> [GmailMessage] {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        apiCallCount += 1
        
        var results: [GmailMessage] = []
        for messageId in messageIds {
            if let message = messages[messageId] {
                results.append(message)
            }
        }
        
        return results
    }
    
    func syncUnreadEmailMetadata(
        for account: GmailAccount,
        maxResults: Int = 1000,
        progressCallback: ((Int, Int?) async -> Void)? = nil
    ) async throws -> [EmailMetadata] {
        let (refs, _) = try await listMessages(for: account, query: "is:unread in:inbox", maxResults: maxResults)
        
        var metadata: [EmailMetadata] = []
        for ref in refs {
            if let message = messages[ref.id] {
                let emailId = StableID.emailId(gmailId: message.id)
                let metadataItem = parseEmailMetadata(from: message, accountEmail: account.email, emailId: emailId)
                metadata.append(metadataItem)
            }
        }
        
        if let callback = progressCallback {
            await callback(metadata.count, metadata.count)
        }
        
        return metadata
    }
    
    func markAsRead(for account: GmailAccount, messageId: String) async throws {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        apiCallCount += 1
        
        if var message = messages[messageId] {
            var labelIds = message.labelIds
            labelIds.removeAll { $0 == "UNREAD" }
            // Note: GmailMessage is a struct, so we need to recreate it
            // For testing purposes, we'll update the stored message
            let updatedMessage = GmailMessage(
                id: message.id,
                threadId: message.threadId,
                snippet: message.snippet,
                payload: message.payload,
                labelIds: labelIds,
                internalDate: message.internalDate
            )
            messages[messageId] = updatedMessage
        }
    }
    
    func starMessage(for account: GmailAccount, messageId: String) async throws {
        if shouldFailAPI {
            throw apiError ?? GmailAPIError.apiError("Mock API error")
        }
        
        apiCallCount += 1
        
        if var message = messages[messageId] {
            var labelIds = message.labelIds
            if !labelIds.contains("STARRED") {
                labelIds.append("STARRED")
            }
            let updatedMessage = GmailMessage(
                id: message.id,
                threadId: message.threadId,
                snippet: message.snippet,
                payload: message.payload,
                labelIds: labelIds,
                internalDate: message.internalDate
            )
            messages[messageId] = updatedMessage
        }
    }
    
    // MARK: - Token Management
    
    func refreshAccessToken(refreshToken: String) async throws -> String {
        tokenRefreshCallCount += 1
        
        if shouldFailTokenRefresh {
            throw GmailAPIError.tokenRefreshFailed
        }
        
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        return "new_access_token_\(Date().timeIntervalSince1970)"
    }
    
    // MARK: - Parsing Helpers (copied from GmailAPIService)
    
    private func parseEmailMetadata(from gmailMessage: GmailMessage, accountEmail: String, emailId: Int) -> EmailMetadata {
        let headers = extractHeaders(from: gmailMessage.payload)
        let subject = headers["subject"] ?? ""
        let from = headers["from"] ?? ""
        let senderEmail = extractEmail(from: from)
        let senderName = extractName(from: from)
        
        let isRead = !gmailMessage.labelIds.contains("UNREAD")
        let isStarred = gmailMessage.labelIds.contains("STARRED")
        
        let receivedAt = parseDate(from: gmailMessage.internalDate) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let receivedAtString = dateFormatter.string(from: receivedAt)
        
        return EmailMetadata(
            id: emailId,
            gmail_id: gmailMessage.id,
            thread_id: gmailMessage.threadId,
            subject: subject,
            sender: senderEmail,
            sender_name: senderName.isEmpty ? nil : senderName,
            snippet: gmailMessage.snippet,
            is_read: isRead,
            is_starred: isStarred,
            labels: gmailMessage.labelIds,
            received_at: receivedAtString,
            account_email: accountEmail
        )
    }
    
    private func extractHeaders(from payload: GmailPayload?) -> [String: String] {
        guard let payload = payload else { return [:] }
        var headers: [String: String] = [:]
        for header in payload.headers {
            headers[header.name.lowercased()] = header.value
        }
        return headers
    }
    
    private func extractEmail(from headerValue: String) -> String {
        if let range = headerValue.range(of: "<") {
            let emailPart = String(headerValue[range.upperBound...])
            if let endRange = emailPart.range(of: ">") {
                return String(emailPart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return headerValue.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractName(from headerValue: String) -> String {
        if let range = headerValue.range(of: "<") {
            let namePart = String(headerValue[..<range.lowerBound])
            return namePart.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ""
    }
    
    private func parseDate(from internalDate: String) -> Date? {
        if let milliseconds = Double(internalDate) {
            return Date(timeIntervalSince1970: milliseconds / 1000.0)
        }
        return nil
    }
}

