//
//  GmailAPIService.swift
//  emptyMyInbox
//
//  Direct Gmail API integration
//  Uses Google Sign-In SDK and makes API calls directly from device
//

import Foundation
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Models

struct GmailAccount: Codable, Identifiable {
    let id: String // Gmail address
    let email: String
    var accessToken: String
    var refreshToken: String?
    var tokenExpiry: Date?
    var lastSync: Date?
    var unreadEmailsNextPageToken: String?
    
    // Generate a stable numeric ID for compatibility with existing code
    var numericId: Int {
        // Use hash of email for consistent ID
        abs(email.hashValue)
    }
}

struct GmailMessage: Codable, Identifiable {
    let id: String
    let threadId: String
    let snippet: String
    let payload: GmailPayload?
    let labelIds: [String]
    let internalDate: String
}

struct GmailPayload: Codable {
    let headers: [GmailHeader]
    let parts: [GmailPart]?
    let body: GmailBody?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailPart: Codable {
    let mimeType: String?
    let filename: String?
    let body: GmailBody?
    let parts: [GmailPart]?
}

struct GmailBody: Codable {
    let data: String?
    let size: Int?
}

struct GmailMessagesResponse: Codable {
    let messages: [GmailMessageReference]?
    let nextPageToken: String?
}

struct GmailMessageReference: Codable {
    let id: String
    let threadId: String
}

struct GmailProfile: Codable {
    let emailAddress: String
}

// MARK: - Service

class GmailAPIService {
    static let shared = GmailAPIService()
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private var accounts: [GmailAccount] = []
    private var nextEmailId: Int = 1000 // Starting ID for generated email IDs
    
    private init() {
        loadSavedAccounts()
    }
    
    // MARK: - Account Management
    
    func hasAuthenticatedAccount() -> Bool {
        return !accounts.isEmpty
    }
    
    func getAllAccounts() -> [GmailAccount] {
        return accounts
    }
    
    func getAccount(byEmail email: String) -> GmailAccount? {
        return accounts.first { $0.email == email }
    }
    
    func getAccount(byId id: String) -> GmailAccount? {
        return accounts.first { $0.id == id }
    }
    
    func getCurrentAccountEmail() -> String? {
        return accounts.first?.email
    }
    
    // MARK: - Google Sign-In
    
    #if canImport(UIKit)
    @MainActor
    func signIn(presentingViewController: UIViewController) async throws -> GmailAccount {
        let clientID = getGoogleClientID()
        guard !clientID.isEmpty else {
            throw GmailAPIError.configurationError
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let scopes = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.modify",
            "https://www.googleapis.com/auth/gmail.settings.basic"
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
        
        // Get token expiry (typically 1 hour)
        let tokenExpiry = Date().addingTimeInterval(3600)
        
        // Check if account already exists
        if let existingIndex = accounts.firstIndex(where: { $0.email == email }) {
            // Update existing account
            var updatedAccount = accounts[existingIndex]
            updatedAccount.accessToken = accessToken
            updatedAccount.refreshToken = refreshToken ?? updatedAccount.refreshToken
            updatedAccount.tokenExpiry = tokenExpiry
            accounts[existingIndex] = updatedAccount
            saveAccounts()
            return updatedAccount
        } else {
            // Create new account
        let account = GmailAccount(
            id: email,
            email: email,
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
    
    func signOut(accountEmail: String? = nil) {
        if let email = accountEmail {
            // Sign out specific account
            accounts.removeAll { $0.email == email }
            saveAccounts()
        } else {
            // Sign out all accounts
        GIDSignIn.sharedInstance.signOut()
            accounts.removeAll()
            clearSavedAccounts()
        }
    }
    
    // MARK: - Token Management
    
    private func getValidAccessToken(for account: GmailAccount) async throws -> String {
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
    
    func getUserProfile(for account: GmailAccount) async throws -> GmailProfile {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/profile")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get profile: \(response)")
        }
        
        return try JSONDecoder().decode(GmailProfile.self, from: data)
    }
    
    func listMessages(for account: GmailAccount, query: String = "is:unread in:inbox", maxResults: Int = 50, pageToken: String? = nil) async throws -> (messages: [GmailMessageReference], nextPageToken: String?) {
        let token = try await getValidAccessToken(for: account)
        
        var urlComponents = URLComponents(string: "\(baseURL)/users/me/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]
        
        if let pageToken = pageToken {
            urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        
        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to list messages: \(response)")
        }
        
        let responseObj = try JSONDecoder().decode(GmailMessagesResponse.self, from: data)
        return (messages: responseObj.messages ?? [], nextPageToken: responseObj.nextPageToken)
    }
    
    func getMessage(for account: GmailAccount, messageId: String) async throws -> GmailMessage {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)?format=full")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get message: \(response)")
        }
        
        return try JSONDecoder().decode(GmailMessage.self, from: data)
    }
    
    func modifyMessageLabels(for account: GmailAccount, messageId: String, addLabelIds: [String]? = nil, removeLabelIds: [String]? = nil) async throws {
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to modify message labels: \(response)")
        }
    }
    
    func markAsRead(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, removeLabelIds: ["UNREAD"])
    }
    
    func markAsUnread(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, addLabelIds: ["UNREAD"])
    }
    
    func starMessage(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, addLabelIds: ["STARRED"])
    }
    
    func unstarMessage(for account: GmailAccount, messageId: String) async throws {
        try await modifyMessageLabels(for: account, messageId: messageId, removeLabelIds: ["STARRED"])
    }
    
    // MARK: - Labels
    
    func getAllLabels(for account: GmailAccount) async throws -> [String: String] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/labels")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
    
    func getAllFilters(for account: GmailAccount) async throws -> [[String: Any]] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to get filters: \(response)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return json["filter"] as? [[String: Any]] ?? []
    }
    
    func createFilter(for account: GmailAccount, filterData: [String: Any]) async throws -> [String: Any] {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: filterData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError("Failed to create filter: \(response)")
        }
        
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    func deleteFilter(for account: GmailAccount, filterId: String) async throws {
        let token = try await getValidAccessToken(for: account)
        let url = URL(string: "\(baseURL)/users/me/settings/filters/\(filterId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GmailAPIError.apiError("Failed to delete filter: \(response)")
        }
    }
    
    // MARK: - Storage (Keychain)
    
    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts",
            kSecValueData as String: data
        ]
        
        // Delete existing
        SecItemDelete(query as CFDictionary)
        
        // Add new
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadSavedAccounts() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let loadedAccounts = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return
        }
        
        accounts = loadedAccounts
    }
    
    private func clearSavedAccounts() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gmail_accounts"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - High-Level Email Operations
    
    /// Sync unread emails for an account
    func syncUnreadEmails(for account: GmailAccount, maxResults: Int = 50, usePagination: Bool = true, resetPagination: Bool = false) async throws -> (emails: [EmailListItem], nextPageToken: String?) {
        var pageToken: String? = nil
        if usePagination && !resetPagination {
            pageToken = account.unreadEmailsNextPageToken
        }
        
        if resetPagination {
            // Clear pagination token
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                var updatedAccount = accounts[index]
                updatedAccount.unreadEmailsNextPageToken = nil
                accounts[index] = updatedAccount
                saveAccounts()
            }
        }
        
        let (messageRefs, nextPageToken) = try await listMessages(
            for: account,
            query: "is:unread in:inbox",
            maxResults: maxResults,
            pageToken: pageToken
        )
        
        var emailItems: [EmailListItem] = []
        for messageRef in messageRefs {
            do {
                let gmailMessage = try await getMessage(for: account, messageId: messageRef.id)
                
                // Only include emails that actually have both UNREAD and INBOX labels
                // This ensures we don't include emails that were marked as read or archived between query and fetch
                guard gmailMessage.labelIds.contains("UNREAD") && gmailMessage.labelIds.contains("INBOX") else {
                    continue
                }
                
                let emailId = getEmailId(for: gmailMessage.id)
                let emailItem = parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                emailItems.append(emailItem)
                
                // Also cache the full email detail since we already have the full message
                // This prevents Catch Up from needing to re-fetch the same data
                let emailDetail = parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                await EmailCache.shared.saveEmailDetail(emailDetail)
            } catch {
                print("Error fetching message \(messageRef.id): \(error)")
                continue
            }
        }
        
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
    
    /// Sync starred emails for an account
    func syncStarredEmails(for account: GmailAccount, maxResults: Int = 500) async throws -> [EmailListItem] {
        let (messageRefs, _) = try await listMessages(
            for: account,
            query: "is:starred",
            maxResults: maxResults,
            pageToken: nil
        )
        
        var emailItems: [EmailListItem] = []
        for messageRef in messageRefs {
            do {
                let gmailMessage = try await getMessage(for: account, messageId: messageRef.id)
                let emailId = getEmailId(for: gmailMessage.id)
                let emailItem = parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                emailItems.append(emailItem)
                
                // Also cache the full email detail since we already have the full message
                let emailDetail = parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                await EmailCache.shared.saveEmailDetail(emailDetail)
            } catch {
                print("Error fetching starred message \(messageRef.id): \(error)")
                continue
            }
        }
        
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
    func getEmailsByLabel(for account: GmailAccount, labelId: String, maxResults: Int = 500) async throws -> [EmailListItem] {
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
        for messageRef in messageRefs {
            do {
                let gmailMessage = try await getMessage(for: account, messageId: messageRef.id)
                let emailId = getEmailId(for: gmailMessage.id)
                
                // Filter uncategorized if needed
                if labelId == "__UNCATEGORIZED__" {
                    let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
                    let userLabels = gmailMessage.labelIds.filter { !systemLabels.contains($0) }
                    if !userLabels.isEmpty {
                        continue // Skip emails with user labels
                    }
                }
                
                let emailItem = parseEmailListItem(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                emailItems.append(emailItem)
                
                // Also cache the full email detail since we already have the full message
                let emailDetail = parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                await EmailCache.shared.saveEmailDetail(emailDetail)
            } catch {
                print("Error fetching message \(messageRef.id): \(error)")
                continue
            }
        }
        
        return emailItems
    }
    
    /// Get email detail by Gmail ID
    func getEmailDetail(for account: GmailAccount, gmailId: String) async throws -> EmailDetail {
        let gmailMessage = try await getMessage(for: account, messageId: gmailId)
        let emailId = getEmailId(for: gmailId)
        return parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
    }
    
    /// Get email detail by numeric ID (searches all accounts)
    func getEmailDetail(byId emailId: Int, gmailId: String, accountEmail: String) async throws -> EmailDetail? {
        guard let account = getAccount(byEmail: accountEmail) else {
            return nil
        }
        
        let gmailMessage = try await getMessage(for: account, messageId: gmailId)
        return parseEmailDetail(from: gmailMessage, accountEmail: account.email, emailId: emailId)
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

enum GmailAPIError: LocalizedError {
    case configurationError
    case signInFailed
    case noToken
    case notAuthenticated
    case tokenExpired
    case tokenRefreshFailed
    case invalidURL
    case apiError(String)
    
    var errorDescription: String? {
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

