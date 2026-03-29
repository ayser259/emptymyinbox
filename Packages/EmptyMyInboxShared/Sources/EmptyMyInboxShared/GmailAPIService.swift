//
//  GmailAPIService.swift
//  emptyMyInbox
//
//  Direct Gmail API integration
//  Uses Google Sign-In SDK and makes API calls directly from device
//

import Foundation
import Security
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Models

public struct GmailAccount: Codable, Identifiable {
    public let id: String // Gmail address
    public let email: String
    public var name: String? // User's display name from Google profile
    public var accessToken: String
    public var refreshToken: String?
    public var tokenExpiry: Date?
    public var lastSync: Date?
    public var unreadEmailsNextPageToken: String?

    public init(
        id: String,
        email: String,
        name: String?,
        accessToken: String,
        refreshToken: String?,
        tokenExpiry: Date?,
        lastSync: Date?,
        unreadEmailsNextPageToken: String?
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.lastSync = lastSync
        self.unreadEmailsNextPageToken = unreadEmailsNextPageToken
    }
    
    // Generate a stable numeric ID for compatibility with existing code
    public var numericId: Int {
        StableID.accountId(email: email)
    }
}

public struct GmailMessage: Codable, Identifiable {
    public let id: String
    public let threadId: String
    public let snippet: String
    public let payload: GmailPayload?
    public let labelIds: [String]
    public let internalDate: String

    public init(
        id: String,
        threadId: String,
        snippet: String,
        payload: GmailPayload?,
        labelIds: [String],
        internalDate: String
    ) {
        self.id = id
        self.threadId = threadId
        self.snippet = snippet
        self.payload = payload
        self.labelIds = labelIds
        self.internalDate = internalDate
    }
}

public struct GmailPayload: Codable {
    public let mimeType: String?
    public let headers: [GmailHeader]
    public let parts: [GmailPart]?
    public let body: GmailBody?

    public init(mimeType: String?, headers: [GmailHeader], parts: [GmailPart]?, body: GmailBody?) {
        self.mimeType = mimeType
        self.headers = headers
        self.parts = parts
        self.body = body
    }
}

public struct GmailHeader: Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct GmailPart: Codable {
    public let mimeType: String?
    public let filename: String?
    public let body: GmailBody?
    public let parts: [GmailPart]?

    public init(mimeType: String?, filename: String?, body: GmailBody?, parts: [GmailPart]?) {
        self.mimeType = mimeType
        self.filename = filename
        self.body = body
        self.parts = parts
    }
}

public struct GmailBody: Codable {
    public let data: String?
    public let size: Int?

    public init(data: String?, size: Int?) {
        self.data = data
        self.size = size
    }
}

public struct GmailMessagesResponse: Codable {
    public let messages: [GmailMessageReference]?
    public let nextPageToken: String?
}

public struct GmailMessageReference: Codable {
    public let id: String
    public let threadId: String

    public init(id: String, threadId: String) {
        self.id = id
        self.threadId = threadId
    }
}

public struct GmailProfile: Codable {
    public let emailAddress: String

    public init(emailAddress: String) {
        self.emailAddress = emailAddress
    }
}

// MARK: - Service

public class GmailAPIService {
    public enum AccountLoadStatus: Equatable {
        case loaded
        case notFound
        case transientFailure(OSStatus)
        case corruptedData
    }
    
    public static let shared = GmailAPIService()
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private var accounts: [GmailAccount] = []
    private var accountsLoadStatus: AccountLoadStatus = .notFound
    private var nextEmailId: Int = 1000 // Starting ID for generated email IDs
    
    // URLSession with timeout configuration to prevent hanging requests
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0 // 30 second timeout per request
        configuration.timeoutIntervalForResource = 60.0 // 60 second total timeout
        configuration.waitsForConnectivity = false // Don't wait for connectivity
        return URLSession(configuration: configuration)
    }()
    
    private init() {
        loadSavedAccounts()
    }
    
    // MARK: - Account Management
    
    public func hasAuthenticatedAccount() -> Bool {
        return !accounts.isEmpty
    }
    
    public func getAllAccounts() -> [GmailAccount] {
        return accounts
    }
    
    public func getAccount(byEmail email: String) -> GmailAccount? {
        return accounts.first { $0.email == email }
    }
    
    public func getAccount(byId id: String) -> GmailAccount? {
        return accounts.first { $0.id == id }
    }
    
    public func getCurrentAccountEmail() -> String? {
        return accounts.first?.email
    }
    
    public func getAccountsLoadStatus() -> AccountLoadStatus {
        return accountsLoadStatus
    }
    
    // MARK: - Google Sign-In
    
    #if canImport(UIKit)
    @MainActor
    public func signIn(presentingViewController: UIViewController) async throws -> GmailAccount {
        let clientID = getGoogleClientID()
        guard !clientID.isEmpty else {
            throw GmailAPIError.configurationError
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let scopes = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.modify",
            "https://www.googleapis.com/auth/gmail.settings.basic",
            "https://www.googleapis.com/auth/gmail.send"
        ]
        
        guard let result = try? await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: scopes
        ) else {
            throw GmailAPIError.signInFailed
        }
        
        // Verify we have a valid user token
        guard result.user.idToken != nil else {
            throw GmailAPIError.noToken
        }
        
        // Get access token from Google Sign-In
        let accessToken = result.user.accessToken.tokenString
        
        // Get refreshToken
        // In Google Sign-In SDK, refreshToken may be nil on first sign-in
        // It's provided when user grants offline access
        // Note: refreshToken property exists but may not always be populated
        let refreshToken: String? = {
            // Try to access refreshToken - handle SDK version differences
            // Some versions have it as optional, others as always-present but may be empty
            let rt = result.user.refreshToken
            return rt.tokenString.isEmpty ? nil : rt.tokenString
        }()
        
        // Get user's email from Google Sign-In
        let email = result.user.profile?.email ?? ""
        
        // Get user's name from Google Sign-In profile
        let name = result.user.profile?.name
        
        // Get token expiry (typically 1 hour)
        let tokenExpiry = Date().addingTimeInterval(3600)
        
        // Check if account already exists
        if let existingIndex = accounts.firstIndex(where: { $0.email == email }) {
            // Update existing account
            var updatedAccount = accounts[existingIndex]
            updatedAccount.accessToken = accessToken
            updatedAccount.refreshToken = refreshToken ?? updatedAccount.refreshToken
            updatedAccount.tokenExpiry = tokenExpiry
            // Update name if available (don't overwrite with nil if name already exists)
            if let name = name {
                updatedAccount.name = name
            }
            accounts[existingIndex] = updatedAccount
            saveAccounts()
            return updatedAccount
        } else {
            // Create new account
            let account = GmailAccount(
                id: email,
                email: email,
                name: name,
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenExpiry: tokenExpiry,
                lastSync: nil,
                unreadEmailsNextPageToken: nil
            )
            
            accounts.append(account)
            saveAccounts()
            
            return account
        }
    }
    #endif
    
    #if os(macOS)
    @MainActor
    public func signIn(presentingWindow: NSWindow?) async throws -> GmailAccount {
        let clientID = getGoogleClientID()
        guard !clientID.isEmpty else {
            throw GmailAPIError.configurationError
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let scopes = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.modify",
            "https://www.googleapis.com/auth/gmail.settings.basic",
            "https://www.googleapis.com/auth/gmail.send"
        ]
        
        guard let window = presentingWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw GmailAPIError.configurationError
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: scopes
            )
        } catch {
            logWarning("Google Sign-In (macOS): \(error)", category: "Auth")
            throw GmailAPIError.apiError(error.localizedDescription)
        }
        
        guard result.user.idToken != nil else {
            throw GmailAPIError.noToken
        }
        
        let accessToken = result.user.accessToken.tokenString
        
        let refreshToken: String? = {
            let rt = result.user.refreshToken
            return rt.tokenString.isEmpty ? nil : rt.tokenString
        }()
        
        let email = result.user.profile?.email ?? ""
        let name = result.user.profile?.name
        let tokenExpiry = Date().addingTimeInterval(3600)
        
        if let existingIndex = accounts.firstIndex(where: { $0.email == email }) {
            var updatedAccount = accounts[existingIndex]
            updatedAccount.accessToken = accessToken
            updatedAccount.refreshToken = refreshToken ?? updatedAccount.refreshToken
            updatedAccount.tokenExpiry = tokenExpiry
            if let name = name {
                updatedAccount.name = name
            }
            accounts[existingIndex] = updatedAccount
            saveAccounts()
            return updatedAccount
        } else {
            let account = GmailAccount(
                id: email,
                email: email,
                name: name,
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenExpiry: tokenExpiry,
                lastSync: nil,
                unreadEmailsNextPageToken: nil
            )
            
            accounts.append(account)
            saveAccounts()
            
            return account
        }
    }
    #endif
    
    public func signOut(accountEmail: String? = nil) {
        if let email = accountEmail {
            // Sign out specific account
            accounts.removeAll { $0.email == email }
            saveAccounts()
            accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
        } else {
            // Sign out all accounts
            GIDSignIn.sharedInstance.signOut()
            accounts.removeAll()
            clearSavedAccounts()
            accountsLoadStatus = .notFound
        }
    }
    
    // MARK: - Token Management
    
    /// Get valid access token, refreshing if necessary (internal for use by extensions)
    public func getValidAccessToken(for account: GmailAccount) async throws -> String {
        // Check if token needs refresh
        if let expiry = account.tokenExpiry, expiry > Date() {
            // Token is still valid
            return account.accessToken
        }
        
        // Token expired, need to refresh
        guard let refreshToken = account.refreshToken else {
            // No refresh token, need to re-authenticate
            throw GmailAPIError.tokenExpired
        }
        
        // Refresh the token
        let newAccessToken = try await refreshAccessToken(refreshToken: refreshToken, clientID: getGoogleClientID(), clientSecret: getGoogleClientSecret())
        
        // Update account in array
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            var updatedAccount = accounts[index]
            updatedAccount.accessToken = newAccessToken
            updatedAccount.tokenExpiry = Date().addingTimeInterval(3600)
            accounts[index] = updatedAccount
            saveAccounts()
        }
        
        return newAccessToken
    }
    
    private func refreshAccessToken(refreshToken: String, clientID: String, clientSecret: String) async throws -> String {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.tokenRefreshFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String else {
            throw GmailAPIError.tokenRefreshFailed
        }
        
        return accessToken
    }
    
    // MARK: - Gmail API Calls
    
    public func getUserProfile(for account: GmailAccount) async throws -> GmailProfile {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/profile")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get profile: \(response)")
        }
        
        return try JSONDecoder().decode(GmailProfile.self, from: data)
    }
    
    public func listMessages(for account: GmailAccount, query: String = "is:unread in:inbox", maxResults: Int = 50, pageToken: String? = nil, fields: String? = nil) async throws -> (messages: [GmailMessageReference], nextPageToken: String?) {
        let token = try await getValidAccessToken(for: account)
        let start = Date()
        
        var urlComponents = URLComponents(string: "\(baseURL)/users/me/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]
        
        if let pageToken = pageToken {
            urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        
        if let fields = fields {
            urlComponents.queryItems?.append(URLQueryItem(name: "fields", value: fields))
        }
        
        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.apiError("Invalid response")
        }
        
        // Handle success codes
        switch httpResponse.statusCode {
        case 200:
            // Normal response with messages
            let responseObj = try JSONDecoder().decode(GmailMessagesResponse.self, from: data)
            Telemetry.event("gmail.list_messages", metadata: [
                "status": "200",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
                "count": "\(responseObj.messages?.count ?? 0)"
            ])
            return (messages: responseObj.messages ?? [], nextPageToken: responseObj.nextPageToken)
        case 204:
            // No Content - means no messages match the query (this is success, not error)
            Telemetry.event("gmail.list_messages", metadata: [
                "status": "204",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
                "count": "0"
            ])
            return (messages: [], nextPageToken: nil)
        default:
            Telemetry.event("gmail.list_messages_error", metadata: [
                "status": "\(httpResponse.statusCode)",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(start) * 1000))"
            ])
            throw GmailAPIError.apiError("Failed to list messages: status \(httpResponse.statusCode)")
        }
    }
    
    public func getMessage(for account: GmailAccount, messageId: String, format: String = "full") async throws -> GmailMessage {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)?format=\(format)")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get message: \(response)")
        }
        
        return try JSONDecoder().decode(GmailMessage.self, from: data)
    }
    
    /// Get message with metadata format only (no body content) - much faster
    public func getMessageMetadata(for account: GmailAccount, messageId: String) async throws -> GmailMessage {
        return try await getMessage(for: account, messageId: messageId, format: "metadata")
    }
    
    /// Batch get multiple messages with metadata format - efficient for loading lists
    /// Uses rate limiting to avoid Gmail API 429 errors (max 5 concurrent requests)
    public func batchGetMessagesMetadata(for account: GmailAccount, messageIds: [String]) async throws -> [GmailMessage] {
        // Process with LIMITED concurrency to avoid rate limits
        let maxConcurrent = 5
        var results: [GmailMessage] = []
        
        // Process in chunks to limit concurrency
        for chunkStart in stride(from: 0, to: messageIds.count, by: maxConcurrent) {
            let chunkEnd = min(chunkStart + maxConcurrent, messageIds.count)
            let chunk = Array(messageIds[chunkStart..<chunkEnd])
            
            // Process this chunk in parallel (limited to maxConcurrent)
            let chunkResults = try await withThrowingTaskGroup(of: GmailMessage?.self) { group in
                for messageId in chunk {
                    group.addTask {
                        do {
                            return try await self.getMessageMetadataWithRetry(for: account, messageId: messageId)
                        } catch {
                            logError("Error fetching metadata for \(messageId): \(error)", category: "Gmail")
                            return nil
                        }
                    }
                }
                
                var chunkMessages: [GmailMessage] = []
                for try await message in group {
                    if let message = message {
                        chunkMessages.append(message)
                    }
                }
                return chunkMessages
            }
            
            results.append(contentsOf: chunkResults)
            
            // Small delay between chunks to be respectful of rate limits
            if chunkEnd < messageIds.count {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms between chunks
            }
        }
        
        return results
    }
    
    /// Get message metadata with exponential backoff retry for rate limits
    private func getMessageMetadataWithRetry(for account: GmailAccount, messageId: String, maxRetries: Int = 3) async throws -> GmailMessage {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await getMessageMetadata(for: account, messageId: messageId)
            } catch {
                lastError = error
                
                // Check if it's a rate limit error (429)
                let errorString = String(describing: error)
                if errorString.contains("429") || errorString.contains("Rate Limit") {
                    // Exponential backoff: 1s, 2s, 4s
                    let delaySeconds = pow(2.0, Double(attempt))
                    let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
                    
                    logInfo("Rate limited on \(messageId), retrying in \(delaySeconds)s (attempt \(attempt + 1)/\(maxRetries))", category: "Gmail")
                    
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continue
                }
                
                // For non-rate-limit errors, don't retry
                throw error
            }
        }
        
        throw lastError ?? GmailAPIError.apiError("Max retries exceeded for \(messageId)")
    }
    
    public func modifyMessageLabels(for account: GmailAccount, messageId: String, addLabelIds: [String]? = nil, removeLabelIds: [String]? = nil) async throws {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)/modify")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let add = addLabelIds {
            body["addLabelIds"] = add
        }
        if let remove = removeLabelIds {
            body["removeLabelIds"] = remove
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to modify message labels: \(response)")
        }
    }
    
    public func markAsRead(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, removeLabelIds: ["UNREAD"])
    }
    
    public func markAsUnread(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, addLabelIds: ["UNREAD"])
    }
    
    public func starMessage(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, addLabelIds: ["STARRED"])
    }
    
    public func unstarMessage(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, removeLabelIds: ["STARRED"])
    }
    
    // MARK: - Labels
    
    public func getAllLabels(for account: GmailAccount) async throws -> [String: String] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/labels")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get labels: \(response)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labelsArray = json["labels"] as? [[String: Any]] else {
            return [:]
        }
        
        var labelDict: [String: String] = [:]
        let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
        
        for label in labelsArray {
            guard let id = label["id"] as? String,
                  let name = label["name"] as? String,
                  let type = label["type"] as? String else {
                continue
            }
            
            // Only include user labels and some system labels
            if type == "user" || systemLabels.contains(id) {
                labelDict[id] = name
            }
        }
        
        return labelDict
    }
    
    // MARK: - Filters
    
    public func getAllFilters(for account: GmailAccount) async throws -> [[String: Any]] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get filters: \(response)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return json["filter"] as? [[String: Any]] ?? []
    }
    
    public func createFilter(for account: GmailAccount, filterData: [String: Any]) async throws -> [String: Any] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: filterData)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to create filter: \(response)")
        }
        
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    public func deleteFilter(for account: GmailAccount, filterId: String) async throws {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters/\(filterId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GmailAPIError.apiError("Failed to delete filter: \(response)")
        }
    }
    
    // MARK: - Storage (Keychain + sandbox fallback file)
    
    private let keychainService = "com.emptyMyInbox.gmail"
    private let keychainAccount = "gmail_accounts"
    /// Used when keychain is blocked (common for sandboxed macOS without keychain-access-groups).
    private let accountsFileName = "gmail_accounts_storage.json"
    
    private func appSupportAccountsFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(accountsFileName)
    }
    
    private func keychainStatusDescription(_ status: OSStatus) -> String {
        if let msg = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) — \(msg)"
        }
        return "\(status)"
    }
    
    private func saveAccountsToFileFallback(data: Data) -> Bool {
        let url = appSupportAccountsFileURL()
        do {
            try data.write(to: url, options: .atomic)
            logSuccess(
                "Saved \(accounts.count) Gmail account(s) to app storage (keychain unavailable on this build)",
                category: "Auth"
            )
            return true
        } catch {
            logError("Could not save accounts to file fallback: \(error)", category: "Auth")
            return false
        }
    }
    
    @discardableResult
    private func loadAccountsFromFileFallback() -> Bool {
        let url = appSupportAccountsFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return false
        }
        accounts = loaded
        logSuccess(
            "Loaded \(accounts.count) Gmail account(s) from app storage (keychain unavailable or empty)",
            category: "Auth"
        )
        accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
        return true
    }
    
    private func removeAccountsFileFallback() {
        try? FileManager.default.removeItem(at: appSupportAccountsFileURL())
    }
    
    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else {
            logWarning("Failed to encode accounts for keychain", category: "Auth")
            return
        }
        
        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add with proper accessibility for device
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            logSuccess("Saved \(accounts.count) accounts to keychain", category: "Auth")
            accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
            removeAccountsFileFallback()
            return
        }
        
        logWarning(
            "Keychain save failed: \(keychainStatusDescription(status)). Using Application Support fallback.",
            category: "Auth"
        )
        if saveAccountsToFileFallback(data: data) {
            accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
        } else {
            accountsLoadStatus = .transientFailure(status)
        }
    }
    
    private func loadSavedAccounts() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            logDebug("No Gmail accounts in keychain yet (normal before first sign-in)", category: "Auth")
            if loadAccountsFromFileFallback() { return }
            if migrateOldKeychainData() {
                accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
            } else {
                accountsLoadStatus = .notFound
            }
            return
        }
        
        guard status == errSecSuccess else {
            logWarning(
                "Keychain load failed: \(keychainStatusDescription(status)). Trying Application Support fallback.",
                category: "Auth"
            )
            if loadAccountsFromFileFallback() { return }
            accountsLoadStatus = .transientFailure(status)
            return
        }
        
        guard let data = result as? Data else {
            logWarning("Keychain returned non-data result", category: "Auth")
            if loadAccountsFromFileFallback() { return }
            accountsLoadStatus = .corruptedData
            return
        }
        
        do {
            let loadedAccounts = try JSONDecoder().decode([GmailAccount].self, from: data)
            accounts = loadedAccounts
            logSuccess("Loaded \(accounts.count) accounts from keychain", category: "Auth")
            accountsLoadStatus = accounts.isEmpty ? .notFound : .loaded
            removeAccountsFileFallback()
        } catch {
            logError("Failed to decode accounts from keychain: \(error)", category: "Auth")
            if loadAccountsFromFileFallback() { return }
            accountsLoadStatus = .corruptedData
        }
    }
    
    /// Migrate from old keychain format (without service identifier)
    private func migrateOldKeychainData() -> Bool {
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(oldQuery as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let loadedAccounts = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return false
        }
        
        logInfo("Migrating \(loadedAccounts.count) accounts from old keychain format", category: "Auth")
        accounts = loadedAccounts
        
        // Save to new format
        saveAccounts()
        
        // Delete old format
        let deleteOldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts"
        ]
        SecItemDelete(deleteOldQuery as CFDictionary)
        return true
    }
    
    private func clearSavedAccounts() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        logInfo("Cleared keychain accounts (status: \(status))", category: "Auth")
        
        // Also try to clear old format
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts"
        ]
        SecItemDelete(oldQuery as CFDictionary)
        removeAccountsFileFallback()
        accountsLoadStatus = .notFound
    }
    
    // MARK: - High-Level Email Operations
    
    /// Sync unread emails for an account
    /// Optimized strategy:
    /// 1. Fetch ALL unread message IDs (lightweight)
    /// 2. Diff with local cache
    /// 3. Fetch FULL content only for new emails
    public func syncUnreadEmails(for account: GmailAccount, maxResults: Int = 50, usePagination: Bool = true, resetPagination: Bool = false, progressCallback: ((Int, Int?) async -> Void)? = nil) async throws -> (emails: [EmailListItem], nextPageToken: String?) {
        // We ignore pagination for the ID fetch because we want to "scan" the inbox
        // But we respect maxResults for the final return count if needed, 
        // though the user wants to "fetch all", so we'll try to get a good chunk.
        
        // Step 1: Get message IDs (lightweight)
        // We'll fetch a large batch of IDs to ensure we cover recent changes
        // fetching 1000 IDs is very fast and small payload
        // Optimization: Use 'fields' to fetch ONLY id and threadId (and nextPageToken)
        let (messageRefs, nextPageToken) = try await listMessages(
            for: account,
            query: "is:unread in:inbox",
            maxResults: 1000, // Large batch of IDs
            pageToken: resetPagination ? nil : account.unreadEmailsNextPageToken,
            fields: "messages(id,threadId),nextPageToken"
        )
        
        // Step 2: Load local cache to see what we already have
        let cachedMetadata = await EmailCache.shared.loadEmailMetadata(accountId: account.numericId)
        // Filter out starred emails (catch up should only show unread, non-starred emails)
        let cachedMetadataFiltered = cachedMetadata.filter { !$0.is_starred }
        let cachedGmailIds = Set(cachedMetadataFiltered.map { $0.gmail_id })
        
        // Step 3: Identify new emails (not in cache)
        // These are the ONLY ones we need to download
        let newMessageRefs = messageRefs.filter { !cachedGmailIds.contains($0.id) }
        
        var emailItems: [EmailListItem] = []
        
        // Step 4: Add cached emails that are still in the server list
        // (This effectively removes emails that were archived/read on another device)
        let serverIdSet = Set(messageRefs.map { $0.id })
        for cachedMetadataItem in cachedMetadataFiltered {
            if serverIdSet.contains(cachedMetadataItem.gmail_id) {
                emailItems.append(cachedMetadataItem.toEmailListItem())
            }
        }
        
        // Step 5: Fetch ONLY new emails with FULL content
        // This is the "Precision Strike" - no redundancy
        if !newMessageRefs.isEmpty {
            let totalNewCount = newMessageRefs.count
            var fetchedNewCount = 0
            let batchSize = 20 // Increased batch size for better parallelism (was 10)
            
            // Process all batches in parallel for maximum speed
            // Split into batches but process them concurrently
            let batches = stride(from: 0, to: newMessageRefs.count, by: batchSize).map { start in
                let end = min(start + batchSize, newMessageRefs.count)
                return Array(newMessageRefs[start..<end])
            }
            
            // Process all batches concurrently for maximum parallelism
            await withTaskGroup(of: [(EmailListItem, EmailDetail)].self) { batchGroup in
                for batch in batches {
                    batchGroup.addTask {
                        var batchResults: [(EmailListItem, EmailDetail)] = []
                        
                        await withTaskGroup(of: (EmailListItem?, EmailDetail?).self) { group in
                            for messageRef in batch {
                                group.addTask {
                                    do {
                                        // Add timeout wrapper to prevent individual emails from hanging (25 second timeout)
                                        let gmailMessage = try await withThrowingTaskGroup(of: Result<GmailMessage, Error>.self) { timeoutGroup in
                                            timeoutGroup.addTask {
                                                do {
                                                    let message = try await self.getMessage(for: account, messageId: messageRef.id)
                                                    return .success(message)
                                                } catch {
                                                    return .failure(error)
                                                }
                                            }
                                            
                                            // Add a timeout task
                                            timeoutGroup.addTask {
                                                try await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                                                return .failure(GmailAPIError.apiError("Timeout fetching message \(messageRef.id)"))
                                            }
                                            
                                            // Wait for first task to complete
                                            let result = try await timeoutGroup.next()!
                                            timeoutGroup.cancelAll() // Cancel the other task
                                            
                                            switch result {
                                            case .success(let message):
                                                return message
                                            case .failure(let error):
                                                throw error
                                            }
                                        }
                                        
                                        // Only include emails that actually have both UNREAD and INBOX labels
                                        guard gmailMessage.labelIds.contains("UNREAD") && gmailMessage.labelIds.contains("INBOX") else {
                                            return (nil, nil)
                                        }
                                        
                                        let emailId = self.getEmailId(for: gmailMessage.id)
                                        let emailItem = self.parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                        let emailDetail = self.parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                        
                                        return (emailItem, emailDetail)
                                    } catch {
                                        logError("Error fetching message \(messageRef.id): \(error)", category: "Gmail")
                                        return (nil, nil)
                                    }
                                }
                            }
                            
                            for await (item, detail) in group {
                                if let item = item, let detail = detail {
                                    batchResults.append((item, detail))
                                }
                            }
                        }
                        
                        return batchResults
                    }
                }
                
                // Collect all results from all batches
                var detailsToCache: [EmailDetail] = []
                for await batchResults in batchGroup {
                    for (item, detail) in batchResults {
                        fetchedNewCount += 1
                        emailItems.append(item)
                        detailsToCache.append(detail)
                        await progressCallback?(fetchedNewCount, totalNewCount)
                    }
                }
                
                // Batch save all email details to persistent cache
                if !detailsToCache.isEmpty {
                    Task {
                        await EmailCache.shared.saveEmailDetails(detailsToCache)
                    }
                }
            }
        }
        
        // Sort by received_at descending
        emailItems.sort { $0.received_at > $1.received_at }
        
        // Update pagination token
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            var updatedAccount = accounts[index]
            updatedAccount.unreadEmailsNextPageToken = nextPageToken
            updatedAccount.lastSync = Date()
            accounts[index] = updatedAccount
            saveAccounts()
        }
        
        return (emailItems, nextPageToken)
    }
    
    // MARK: - Lightweight Metadata Sync (Fast - No Body Content)
    
    /// Sync unread email metadata only - FAST, no body content downloaded
    /// Returns EmailMetadata array for counts and lists, sorted by date descending
    public func syncUnreadEmailMetadata(for account: GmailAccount, maxResults: Int = 1000, progressCallback: ((Int, Int?) async -> Void)? = nil) async throws -> [EmailMetadata] {
        // Step 1: Get all message IDs (very fast - just IDs)
        let (messageRefs, _) = try await listMessages(
            for: account,
            query: "is:unread in:inbox",
            maxResults: maxResults,
            pageToken: nil,
            fields: "messages(id,threadId),nextPageToken"
        )
        
        guard !messageRefs.isEmpty else {
            // Still update lastSync even if no emails
            updateAccountLastSync(email: account.email)
            return []
        }
        
        let totalCount = messageRefs.count
        await progressCallback?(0, totalCount)
        
        // Step 2: Batch fetch metadata (no body) with rate limiting
        var allMetadata: [EmailMetadata] = []
        let batchSize = 20 // Reduced batch size to avoid rate limits
        
        let batches = stride(from: 0, to: messageRefs.count, by: batchSize).map { start in
            let end = min(start + batchSize, messageRefs.count)
            return Array(messageRefs[start..<end])
        }
        
        var processedCount = 0
        
        for batch in batches {
            let batchIds = batch.map { $0.id }
            let messages = try await batchGetMessagesMetadata(for: account, messageIds: batchIds)
            
            for gmailMessage in messages {
                // Only include emails that actually have UNREAD label
                guard gmailMessage.labelIds.contains("UNREAD") && gmailMessage.labelIds.contains("INBOX") else {
                    continue
                }
                
                let emailId = getEmailId(for: gmailMessage.id)
                let metadata = parseEmailMetadata(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                allMetadata.append(metadata)
            }
            
            processedCount += batch.count
            await progressCallback?(processedCount, totalCount)
        }
        
        // Sort by received_at descending (newest first)
        allMetadata.sort { $0.received_at > $1.received_at }
        
        // Update lastSync timestamp
        updateAccountLastSync(email: account.email)
        
        return allMetadata
    }
    
    /// Sync starred email metadata only - FAST, no body content downloaded
    public func syncStarredEmailMetadata(for account: GmailAccount, maxResults: Int = 500, progressCallback: ((Int, Int?) async -> Void)? = nil) async throws -> [EmailMetadata] {
        // Step 1: Get all message IDs
        let (messageRefs, _) = try await listMessages(
            for: account,
            query: "is:starred",
            maxResults: maxResults,
            pageToken: nil,
            fields: "messages(id,threadId),nextPageToken"
        )
        
        guard !messageRefs.isEmpty else {
            return []
        }
        
        let totalCount = messageRefs.count
        await progressCallback?(0, totalCount)
        
        // Step 2: Batch fetch metadata with rate limiting
        var allMetadata: [EmailMetadata] = []
        let batchSize = 20 // Reduced batch size to avoid rate limits
        
        let batches = stride(from: 0, to: messageRefs.count, by: batchSize).map { start in
            let end = min(start + batchSize, messageRefs.count)
            return Array(messageRefs[start..<end])
        }
        
        var processedCount = 0
        
        for batch in batches {
            let batchIds = batch.map { $0.id }
            let messages = try await batchGetMessagesMetadata(for: account, messageIds: batchIds)
            
            for gmailMessage in messages {
                let emailId = getEmailId(for: gmailMessage.id)
                let metadata = parseEmailMetadata(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                allMetadata.append(metadata)
            }
            
            processedCount += batch.count
            await progressCallback?(processedCount, totalCount)
        }
        
        // Sort by received_at descending
        allMetadata.sort { $0.received_at > $1.received_at }
        
        return allMetadata
    }
    
    /// Update the lastSync timestamp for an account
    private func updateAccountLastSync(email: String) {
        if let index = accounts.firstIndex(where: { $0.email == email }) {
            var updatedAccount = accounts[index]
            updatedAccount.lastSync = Date()
            accounts[index] = updatedAccount
            saveAccounts()
        }
    }
    
    /// Get full email content by Gmail ID - use for Catch Up view lazy loading
    public func getFullEmailDetail(for account: GmailAccount, gmailId: String) async throws -> EmailDetail {
        let gmailMessage = try await getMessage(for: account, messageId: gmailId, format: "full")
        let emailId = getEmailId(for: gmailId)
        return parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
    }
    
    /// Batch get full email details - for progressive loading in Catch Up
    /// Uses rate limiting to avoid Gmail API 429 errors
    public func batchGetFullEmailDetails(for account: GmailAccount, gmailIds: [String]) async throws -> [EmailDetail] {
        // Process with LIMITED concurrency to avoid rate limits
        let maxConcurrent = 5
        var results: [EmailDetail] = []
        
        // Process in chunks to limit concurrency
        for chunkStart in stride(from: 0, to: gmailIds.count, by: maxConcurrent) {
            let chunkEnd = min(chunkStart + maxConcurrent, gmailIds.count)
            let chunk = Array(gmailIds[chunkStart..<chunkEnd])
            
            // Process this chunk in parallel (limited to maxConcurrent)
            let chunkResults = try await withThrowingTaskGroup(of: EmailDetail?.self) { group in
                for gmailId in chunk {
                    group.addTask {
                        do {
                            return try await self.getFullEmailDetailWithRetry(for: account, gmailId: gmailId)
                        } catch {
                            logError("Error fetching full email \(gmailId): \(error)", category: "Gmail")
                            return nil
                        }
                    }
                }
                
                var chunkDetails: [EmailDetail] = []
                for try await detail in group {
                    if let detail = detail {
                        chunkDetails.append(detail)
                    }
                }
                return chunkDetails
            }
            
            results.append(contentsOf: chunkResults)
            
            // Small delay between chunks to be respectful of rate limits
            if chunkEnd < gmailIds.count {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms between chunks
            }
        }
        
        return results
    }
    
    /// Get full email detail with exponential backoff retry for rate limits
    private func getFullEmailDetailWithRetry(for account: GmailAccount, gmailId: String, maxRetries: Int = 3) async throws -> EmailDetail {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await getFullEmailDetail(for: account, gmailId: gmailId)
            } catch {
                lastError = error
                
                // Check if it's a rate limit error (429)
                let errorString = String(describing: error)
                if errorString.contains("429") || errorString.contains("Rate Limit") {
                    // Exponential backoff: 1s, 2s, 4s
                    let delaySeconds = pow(2.0, Double(attempt))
                    let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
                    
                    logInfo("Rate limited on full email \(gmailId), retrying in \(delaySeconds)s (attempt \(attempt + 1)/\(maxRetries))", category: "Gmail")
                    
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continue
                }
                
                // For non-rate-limit errors, don't retry
                throw error
            }
        }
        
        throw lastError ?? GmailAPIError.apiError("Max retries exceeded for full email \(gmailId)")
    }
    
    /// Sync starred emails for an account
    public func syncStarredEmails(for account: GmailAccount, maxResults: Int = 500, progressCallback: ((Int, Int?) async -> Void)? = nil) async throws -> [EmailListItem] {
        // Step 1: Get all message IDs (fast - one API call)
        // Optimized: Fetch IDs only first, restricting response fields
        let (messageRefs, _) = try await listMessages(
            for: account,
            query: "is:starred",
            maxResults: maxResults,
            pageToken: nil,
            fields: "messages(id,threadId),nextPageToken"
        )
        
        // Step 2: Load local cache to see what we already have
        let cachedSnapshot = await DashboardCache.shared.loadSnapshot()
        let cachedStarredGmailIds = Set((cachedSnapshot?.starredEmails ?? []).map { $0.gmail_id })
        
        // Step 3: Identify new starred emails (not in cache)
        let newMessageRefs = messageRefs.filter { !cachedStarredGmailIds.contains($0.id) }
        
        var emailItems: [EmailListItem] = []
        
        // Step 4: Use cached starred emails for emails we already have
        if let cachedSnapshot = cachedSnapshot {
            for cachedEmail in cachedSnapshot.starredEmails {
                // Check if the cached email is still in the server list
                if messageRefs.contains(where: { $0.id == cachedEmail.gmail_id }) {
                    emailItems.append(cachedEmail)
                }
            }
        }
        
        // Step 5: Fetch only new starred emails with full content
        if !newMessageRefs.isEmpty {
            let totalNewCount = newMessageRefs.count
            var fetchedNewCount = 0
            let batchSize = 20 // Increased batch size for better parallelism (was 10)
            
            // Process all batches in parallel for maximum speed
            let batches = stride(from: 0, to: newMessageRefs.count, by: batchSize).map { start in
                let end = min(start + batchSize, newMessageRefs.count)
                return Array(newMessageRefs[start..<end])
            }
            
            // Process all batches concurrently
            await withTaskGroup(of: [(EmailListItem, EmailDetail)].self) { batchGroup in
                for batch in batches {
                    batchGroup.addTask {
                        var batchResults: [(EmailListItem, EmailDetail)] = []
                        
                        await withTaskGroup(of: (EmailListItem?, EmailDetail?).self) { group in
                    for messageRef in batch {
                        group.addTask {
                            do {
                                // Add timeout wrapper to prevent individual emails from hanging (25 second timeout)
                                let gmailMessage = try await withThrowingTaskGroup(of: Result<GmailMessage, Error>.self) { timeoutGroup in
                                    timeoutGroup.addTask {
                                        do {
                                            let message = try await self.getMessage(for: account, messageId: messageRef.id)
                                            return .success(message)
                                        } catch {
                                            return .failure(error)
                                        }
                                    }
                                    
                                    // Add a timeout task
                                    timeoutGroup.addTask {
                                        try await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                                        return .failure(GmailAPIError.apiError("Timeout fetching starred message \(messageRef.id)"))
                                    }
                                    
                                    // Wait for first task to complete
                                    let result = try await timeoutGroup.next()!
                                    timeoutGroup.cancelAll() // Cancel the other task
                                    
                                    switch result {
                                    case .success(let message):
                                        return message
                                    case .failure(let error):
                                        throw error
                                    }
                                }
                                
                                let emailId = self.getEmailId(for: gmailMessage.id)
                                let emailItem = self.parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                let emailDetail = self.parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                
                                return (emailItem, emailDetail)
                            } catch {
                                logError("Error fetching starred message \(messageRef.id): \(error)", category: "Gmail")
                                return (nil, nil)
                            }
                        }
                    }
                    
                            for await (item, detail) in group {
                                if let item = item, let detail = detail {
                                    batchResults.append((item, detail))
                                }
                            }
                        }
                        
                        return batchResults
                    }
                }
                
                // Collect all results from all batches
                var detailsToCache: [EmailDetail] = []
                for await batchResults in batchGroup {
                    for (item, detail) in batchResults {
                        fetchedNewCount += 1
                        emailItems.append(item)
                        detailsToCache.append(detail)
                        await progressCallback?(fetchedNewCount, totalNewCount)
                    }
                }
                
                // Batch save all email details to persistent cache
                if !detailsToCache.isEmpty {
                    Task {
                        await EmailCache.shared.saveEmailDetails(detailsToCache)
                    }
                }
            }
        }
        
        // Sort by received_at descending
        emailItems.sort { $0.received_at > $1.received_at }
        
        // Update lastSync timestamp
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            var updatedAccount = accounts[index]
            updatedAccount.lastSync = Date()
            accounts[index] = updatedAccount
            saveAccounts()
        }
        
        return emailItems
    }
    
    /// Get emails by label
    public func getEmailsByLabel(for account: GmailAccount, labelId: String, maxResults: Int = 500) async throws -> [EmailListItem] {
        let query: String
        if labelId == "__UNCATEGORIZED__" {
            // For uncategorized, we need to get all emails and filter out those with user labels
            // This is complex, so for now we'll get all unread emails
            query = "is:unread in:inbox"
        } else {
            query = "label:\(labelId)"
        }
        
        let (messageRefs, _) = try await listMessages(
            for: account,
            query: query,
            maxResults: maxResults,
            pageToken: nil
        )
        
        var emailItems: [EmailListItem] = []
        var detailsToCache: [EmailDetail] = []
        
        // Process messages in batches (in parallel for speed)
        let batchSize = 20 // Increased batch size for better parallelism
        let batches = stride(from: 0, to: messageRefs.count, by: batchSize).map { start in
            let end = min(start + batchSize, messageRefs.count)
            return Array(messageRefs[start..<end])
        }

        // Process all batches concurrently
        await withTaskGroup(of: (items: [EmailListItem], details: [EmailDetail]).self) { batchGroup in
            for batch in batches {
                batchGroup.addTask {
                    var batchItems: [EmailListItem] = []
                    var batchDetails: [EmailDetail] = []
                    
                    await withTaskGroup(of: (EmailListItem?, EmailDetail?).self) { group in
                        for messageRef in batch {
                            group.addTask {
                                do {
                                    // Add timeout wrapper to prevent individual emails from hanging (25 second timeout)
                                    let gmailMessage = try await withThrowingTaskGroup(of: Result<GmailMessage, Error>.self) { timeoutGroup in
                                        timeoutGroup.addTask {
                                            do {
                                                let message = try await self.getMessage(for: account, messageId: messageRef.id)
                                                return .success(message)
                                            } catch {
                                                return .failure(error)
                                            }
                                        }
                                        
                                        // Add a timeout task
                                        timeoutGroup.addTask {
                                            try await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                                            return .failure(GmailAPIError.apiError("Timeout fetching message \(messageRef.id)"))
                                        }
                                        
                                        // Wait for first task to complete
                                        let result = try await timeoutGroup.next()!
                                        timeoutGroup.cancelAll() // Cancel the other task
                                        
                                        switch result {
                                        case .success(let message):
                                            return message
                                        case .failure(let error):
                                            throw error
                                        }
                                    }
                                    
                                    let emailId = self.getEmailId(for: gmailMessage.id)
                                    
                                    // Filter uncategorized if needed
                                    if labelId == "__UNCATEGORIZED__" {
                                        let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
                                        let userLabels = gmailMessage.labelIds.filter { !systemLabels.contains($0) }
                                        if !userLabels.isEmpty {
                                            return (nil, nil) // Skip emails with user labels
                                        }
                                    }
                                    
                                    let emailItem = self.parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                    
                                    // Parse detail for caching
                                    let emailDetail = self.parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                                    
                                    return (emailItem, emailDetail)
                                } catch {
                                    logError("Error fetching message \(messageRef.id): \(error)", category: "Gmail")
                                    return (nil, nil)
                                }
                            }
                        }
                        
                        for await (item, detail) in group {
                            if let item = item {
                                batchItems.append(item)
                            }
                            if let detail = detail {
                                batchDetails.append(detail)
                            }
                        }
                    }
                    
                    return (items: batchItems, details: batchDetails)
                }
            }
            
            // Collect all results from all batches
            for await batchResult in batchGroup {
                emailItems.append(contentsOf: batchResult.items)
                detailsToCache.append(contentsOf: batchResult.details)
            }
        }
        
        if !detailsToCache.isEmpty {
            await EmailCache.shared.saveEmailDetails(detailsToCache)
        }
        
        return emailItems
    }
    
    /// Get email detail by Gmail ID (uses full format for body content)
    public func getEmailDetail(for account: GmailAccount, gmailId: String) async throws -> EmailDetail {
        // Use full format when we need the body (for Catch Up view)
        let gmailMessage = try await getMessage(for: account, messageId: gmailId, format: "full")
        let emailId = getEmailId(for: gmailId)
        let emailDetail = parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
        // Cache the full detail for future use
        await EmailCache.shared.saveEmailDetail(emailDetail)
        return emailDetail
    }
    
    /// Get email detail by numeric ID (searches all accounts)
    public func getEmailDetail(byId emailId: Int, gmailId: String, accountEmail: String) async throws -> EmailDetail? {
        guard let account = getAccount(byEmail: accountEmail) else {
            return nil
        }
        
        // Use full format when we need the body
        let gmailMessage = try await getMessage(for: account, messageId: gmailId, format: "full")
        let emailDetail = parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
        // Cache the full detail for future use
        await EmailCache.shared.saveEmailDetail(emailDetail)
        return emailDetail
    }
    
    // MARK: - Configuration
    
    private func getGoogleClientID() -> String {
        // Try GIDClientID first (for Google Sign-In SDK)
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !clientID.isEmpty {
            return clientID
        }
        // Fallback to GOOGLE_CLIENT_ID
        return Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }
    
    private func getGoogleClientSecret() -> String {
        // Only needed for token refresh - you may want to store this securely
        return Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String ?? ""
    }
}

// MARK: - Errors

public enum GmailAPIError: LocalizedError {
    case configurationError
    case signInFailed
    case noToken
    case notAuthenticated
    case tokenExpired
    case tokenRefreshFailed
    case invalidURL
    case apiError(String)
    
    public var errorDescription: String? {
        switch self {
        case .configurationError:
            return "Google Sign-In configuration error"
        case .signInFailed:
            return "Failed to sign in with Google"
        case .noToken:
            return "No authentication token"
        case .notAuthenticated:
            return "Not authenticated with Gmail"
        case .tokenExpired:
            return "Authentication token expired. Please sign in again."
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let message):
            return message
        }
    }
}
