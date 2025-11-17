//
//  APIService.swift
//  emptyMyInbox
//
//  API service for connecting to backend
//

import Foundation

class APIService {
    static let shared = APIService()
    
    private let baseURL: String = {
        if let overrideURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !overrideURL.isEmpty {
            return overrideURL
        }

        let env = ProcessInfo.processInfo.environment
        if let apiBase = env["API_BASE_URL"], !apiBase.isEmpty {
            return apiBase
        }

        return "https://emptymyinbox-sgwq.onrender.com/api"
    }()
    private var accessToken: String?
    private var refreshToken: String?
    
    private init() {
        // Load tokens from UserDefaults
        accessToken = UserDefaults.standard.string(forKey: "accessToken")
        refreshToken = UserDefaults.standard.string(forKey: "refreshToken")
    }
    
    // MARK: - Token Management
    
    var hasAccessToken: Bool {
        return accessToken != nil
    }
    
    func setTokens(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
        
        if let access = access {
            UserDefaults.standard.set(access, forKey: "accessToken")
        } else {
            UserDefaults.standard.removeObject(forKey: "accessToken")
        }
        
        if let refresh = refresh {
            UserDefaults.standard.set(refresh, forKey: "refreshToken")
        } else {
            UserDefaults.standard.removeObject(forKey: "refreshToken")
        }
    }
    
    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
    }
    
    // MARK: - Request Helpers
    
    private func createRequest(endpoint: String, method: String, body: Data? = nil, requiresAuth: Bool = true) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }
    
    private func performRequest<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle 401 Unauthorized - try to refresh token when possible, otherwise force login
        if httpResponse.statusCode == 401 {
            if let _ = refreshToken {
                do {
                    try await refreshAccessToken()
                    // Retry with new token
                    var retryRequest = request
                    if let newToken = accessToken {
                        retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    }
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                          (200...299).contains(retryHttpResponse.statusCode) else {
                        throw APIError.invalidResponse
                    }
                    return try JSONDecoder().decode(T.self, from: retryData)
                } catch {
                    clearTokens()
                    throw APIError.unauthorized
                }
            } else {
                clearTokens()
                throw APIError.unauthorized
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorData.error ?? "Unknown error")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw APIError.unauthorized
        }
        
        let body = try JSONEncoder().encode(["refresh": refresh])
        guard let request = createRequest(endpoint: "/auth/token/refresh/", method: "POST", body: body, requiresAuth: false) else {
            throw APIError.invalidRequest
        }
        
        let response: TokenRefreshResponse = try await performRequest(request, responseType: TokenRefreshResponse.self)
        setTokens(access: response.access, refresh: refresh)
    }
    
    // MARK: - Authentication
    
    func register(_ data: RegisterRequest) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(data)
        guard let request = createRequest(endpoint: "/auth/register/", method: "POST", body: body, requiresAuth: false) else {
            throw APIError.invalidRequest
        }
        
        let response: AuthResponse = try await performRequest(request, responseType: AuthResponse.self)
        setTokens(access: response.tokens.access, refresh: response.tokens.refresh)
        return response
    }
    
    func login(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        guard let request = createRequest(endpoint: "/auth/login/", method: "POST", body: body, requiresAuth: false) else {
            throw APIError.invalidRequest
        }
        
        let response: AuthResponse = try await performRequest(request, responseType: AuthResponse.self)
        setTokens(access: response.tokens.access, refresh: response.tokens.refresh)
        return response
    }
    
    func logout() async throws {
        guard let refresh = refreshToken else { return }
        
        let body = try JSONEncoder().encode(["refresh": refresh])
        guard let request = createRequest(endpoint: "/auth/logout/", method: "POST", body: body) else {
            throw APIError.invalidRequest
        }
        
        _ = try await URLSession.shared.data(for: request)
        clearTokens()
    }
    
    func getUser() async throws -> User {
        guard let request = createRequest(endpoint: "/auth/user/", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: User.self)
    }
    
    func updateProfile(state: String?, zipCode: String?) async throws -> User {
        var bodyDict: [String: Any] = [:]
        if let state = state, !state.isEmpty {
            bodyDict["state"] = state
        }
        if let zipCode = zipCode, !zipCode.isEmpty {
            bodyDict["zip_code"] = zipCode
        }
        
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
        guard let request = createRequest(endpoint: "/auth/profile/", method: "PUT", body: body) else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: User.self)
    }
    
    // MARK: - Email Accounts
    
    func getAccounts() async throws -> [EmailAccount] {
        guard let request = createRequest(endpoint: "/accounts/", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: [EmailAccount].self)
    }
    
    func syncAllAccounts() async throws -> SyncResponse {
        guard let request = createRequest(endpoint: "/accounts/sync_all/", method: "POST") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: SyncResponse.self)
    }
    
    // MARK: - Labels
    
    func getLabels() async throws -> [Label] {
        guard let request = createRequest(endpoint: "/labels/", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: [Label].self)
    }
    
    func getFiltersForLabel(labelId: String) async throws -> [GmailFilter] {
        guard let encodedLabelId = labelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidRequest
        }
        guard let request = createRequest(endpoint: "/labels/\(encodedLabelId)/filters/", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: [GmailFilter].self)
    }
    
    // MARK: - Filter Management
    
    struct CreateFilterRequest: Codable {
        let account_id: Int
        let criteria: FilterCriteria
        let actions: FilterActions
    }
    
    func createFilter(accountId: Int, criteria: FilterCriteria, actions: FilterActions) async throws -> GmailFilter {
        let requestBody = CreateFilterRequest(account_id: accountId, criteria: criteria, actions: actions)
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            throw APIError.invalidRequest
        }
        guard let request = createRequest(endpoint: "/filters/", method: "POST", body: jsonData) else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: GmailFilter.self)
    }
    
    struct UpdateFilterRequest: Codable {
        let criteria: FilterCriteria
        let actions: FilterActions
    }
    
    func updateFilter(filterId: Int, criteria: FilterCriteria, actions: FilterActions) async throws -> GmailFilter {
        let requestBody = UpdateFilterRequest(criteria: criteria, actions: actions)
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            throw APIError.invalidRequest
        }
        guard let request = createRequest(endpoint: "/filters/\(filterId)/", method: "PUT", body: jsonData) else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: GmailFilter.self)
    }
    
    func deleteFilter(filterId: Int) async throws {
        guard let request = createRequest(endpoint: "/filters/\(filterId)/delete/", method: "DELETE") else {
            throw APIError.invalidRequest
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401, refreshToken != nil {
            try await refreshAccessToken()
            var retryRequest = request
            if let newToken = accessToken {
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            }
            let (_, retryResponse) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                  (200...299).contains(retryHttpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Maintenance
    
    struct ClearDatabaseResponse: Codable {
        let deleted: Int
    }
    
    func clearDatabaseEmails() async throws -> ClearDatabaseResponse {
        guard let request = createRequest(endpoint: "/accounts/clear_database/", method: "POST") else {
            throw APIError.invalidRequest
        }
        return try await performRequest(request, responseType: ClearDatabaseResponse.self)
    }
    
    // MARK: - Emails
    
    func getEmails(accountId: Int? = nil, isRead: Bool? = nil, searchQuery: String? = nil) async throws -> [EmailListItem] {
        var queryItems: [String] = []
        if let accountId = accountId {
            queryItems.append("account=\(accountId)")
        }
        if let isRead = isRead {
            queryItems.append("is_read=\(isRead)")
        }
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            if let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryItems.append("q=\(encodedQuery)")
            }
        }
        
        let queryString = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        guard let request = createRequest(endpoint: "/emails/\(queryString)", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: [EmailListItem].self)
    }
    
    func searchEmails(query: String) async throws -> [EmailListItem] {
        return try await getEmails(searchQuery: query)
    }
    
    func getStarredEmails() async throws -> [EmailListItem] {
        // Get all starred emails
        guard let request = createRequest(endpoint: "/emails/?is_starred=true", method: "GET") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: [EmailListItem].self)
    }
    
    func getEmailsByLabel(labelId: String) async throws -> [EmailListItem] {
        guard let encodedLabelId = labelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidRequest
        }
        guard let request = createRequest(endpoint: "/emails/?label=\(encodedLabelId)", method: "GET") else {
            throw APIError.invalidRequest
        }
        return try await performRequest(request, responseType: [EmailListItem].self)
    }
    
    func getUnreadEmails(accountId: Int? = nil) async throws -> [EmailListItem] {
        try await getEmails(accountId: accountId, isRead: false)
    }
    
    func getEmailsBySender(senderEmail: String) async throws -> [EmailListItem] {
        // Note: Backend doesn't support sender filtering yet, so we fetch all and filter client-side
        // This could be optimized later with backend support
        let allEmails = try await getEmails()
        return allEmails.filter { $0.sender == senderEmail }
    }
    
    func getEmailDetails(emailId: Int) async throws -> EmailDetail {
        guard let request = createRequest(endpoint: "/emails/\(emailId)/", method: "GET") else {
            throw APIError.invalidRequest
        }
        return try await performRequest(request, responseType: EmailDetail.self)
    }
    
    func markEmailAsRead(emailId: Int) async throws -> EmailDetail {
        guard let request = createRequest(endpoint: "/emails/\(emailId)/mark_read/", method: "POST") else {
            throw APIError.invalidRequest
        }
        return try await performRequest(request, responseType: EmailDetail.self)
    }
    
    func starEmail(emailId: Int) async throws -> EmailDetail {
        guard let request = createRequest(endpoint: "/emails/\(emailId)/star/", method: "POST") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: EmailDetail.self)
    }
    
    func unstarEmail(emailId: Int) async throws -> EmailDetail {
        guard let request = createRequest(endpoint: "/emails/\(emailId)/unstar/", method: "POST") else {
            throw APIError.invalidRequest
        }
        
        return try await performRequest(request, responseType: EmailDetail.self)
    }
    
    // MARK: - Gmail OAuth
    
    func getGmailAuthURL(redirectURI: String? = nil) async throws -> String {
        var endpoint = "/auth/gmail/start/"
        if let redirectURI = redirectURI,
           let encoded = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "?redirect_uri=\(encoded)"
        }
        
        guard let request = createRequest(endpoint: endpoint, method: "GET") else {
            throw APIError.invalidRequest
        }
        
        let response: GmailAuthResponse = try await performRequest(request, responseType: GmailAuthResponse.self)
        return response.authorization_url
    }
}

// MARK: - Models

struct RegisterRequest: Codable {
    let username: String
    let email: String?
    let password: String
    let password_confirm: String
    let first_name: String?
    let last_name: String?
    let state: String?
    let zip_code: String?
}

struct AuthResponse: Codable {
    let user: User
    let tokens: Tokens
}

struct Tokens: Codable {
    let access: String
    let refresh: String
}

struct TokenRefreshResponse: Codable {
    let access: String
}

struct User: Codable {
    let id: Int
    let username: String
    let email: String?
    let first_name: String?
    let last_name: String?
    let state: String?
    let zip_code: String?
    let date_joined: String
    
    // Helper computed property for display name
    var displayName: String {
        if let firstName = first_name, !firstName.isEmpty {
            return firstName
        }
        return username
    }
}

struct EmailAccount: Codable {
    let id: Int
    let email: String
    let is_active: Bool
    let last_sync: String?
    let created_at: String
    let email_count: Int
}

struct EmailListItem: Codable {
    let id: Int
    let gmail_id: String
    let subject: String
    let sender: String
    let sender_name: String?
    let snippet: String
    let is_read: Bool
    let is_starred: Bool
    let labels: [String]
    let received_at: String
    let account_email: String
}

struct Label: Codable, Hashable {
    let id: String
    let name: String
    let unread_count: Int
}

struct GmailFilter: Codable, Identifiable {
    let id: Int
    let gmail_filter_id: String
    let criteria: FilterCriteria
    let actions: FilterActions
    let created_at: String
    let updated_at: String
}

struct FilterCriteria: Codable {
    let from: String?
    let to: String?
    let subject: String?
    let query: String?
    let negatedQuery: String?
    let hasAttachment: Bool?
    let excludeChats: Bool?
    let size: Int?  // Size in bytes
    let sizeComparison: String?  // "larger" or "smaller"
    
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case subject
        case query
        case negatedQuery
        case hasAttachment
        case excludeChats
        case size
        case sizeComparison
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        negatedQuery = try container.decodeIfPresent(String.self, forKey: .negatedQuery)
        hasAttachment = try container.decodeIfPresent(Bool.self, forKey: .hasAttachment)
        excludeChats = try container.decodeIfPresent(Bool.self, forKey: .excludeChats)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        sizeComparison = try container.decodeIfPresent(String.self, forKey: .sizeComparison)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(negatedQuery, forKey: .negatedQuery)
        try container.encodeIfPresent(hasAttachment, forKey: .hasAttachment)
        try container.encodeIfPresent(excludeChats, forKey: .excludeChats)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(sizeComparison, forKey: .sizeComparison)
    }
    
    // Convenience initializer for creating new criteria
    init(
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        query: String? = nil,
        negatedQuery: String? = nil,
        hasAttachment: Bool? = nil,
        excludeChats: Bool? = nil,
        size: Int? = nil,
        sizeComparison: String? = nil
    ) {
        self.from = from
        self.to = to
        self.subject = subject
        self.query = query
        self.negatedQuery = negatedQuery
        self.hasAttachment = hasAttachment
        self.excludeChats = excludeChats
        self.size = size
        self.sizeComparison = sizeComparison
    }
}

struct FilterActions: Codable {
    let addLabelIds: [String]?
    let removeLabelIds: [String]?
    let forward: String?
    let markAsRead: Bool?
    let archive: Bool?
    let delete: Bool?
    let alwaysMarkAsRead: Bool?
    let neverMarkAsRead: Bool?
    let neverSpam: Bool?
    let star: Bool?
    
    enum CodingKeys: String, CodingKey {
        case addLabelIds
        case removeLabelIds
        case forward
        case markAsRead
        case archive
        case delete
        case alwaysMarkAsRead
        case neverMarkAsRead
        case neverSpam
        case star
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addLabelIds = try container.decodeIfPresent([String].self, forKey: .addLabelIds)
        removeLabelIds = try container.decodeIfPresent([String].self, forKey: .removeLabelIds)
        forward = try container.decodeIfPresent(String.self, forKey: .forward)
        markAsRead = try container.decodeIfPresent(Bool.self, forKey: .markAsRead)
        archive = try container.decodeIfPresent(Bool.self, forKey: .archive)
        delete = try container.decodeIfPresent(Bool.self, forKey: .delete)
        alwaysMarkAsRead = try container.decodeIfPresent(Bool.self, forKey: .alwaysMarkAsRead)
        neverMarkAsRead = try container.decodeIfPresent(Bool.self, forKey: .neverMarkAsRead)
        neverSpam = try container.decodeIfPresent(Bool.self, forKey: .neverSpam)
        star = try container.decodeIfPresent(Bool.self, forKey: .star)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(addLabelIds, forKey: .addLabelIds)
        try container.encodeIfPresent(removeLabelIds, forKey: .removeLabelIds)
        try container.encodeIfPresent(forward, forKey: .forward)
        try container.encodeIfPresent(markAsRead, forKey: .markAsRead)
        try container.encodeIfPresent(archive, forKey: .archive)
        try container.encodeIfPresent(delete, forKey: .delete)
        try container.encodeIfPresent(alwaysMarkAsRead, forKey: .alwaysMarkAsRead)
        try container.encodeIfPresent(neverMarkAsRead, forKey: .neverMarkAsRead)
        try container.encodeIfPresent(neverSpam, forKey: .neverSpam)
        try container.encodeIfPresent(star, forKey: .star)
    }
    
    // Convenience initializer for creating new actions
    init(
        addLabelIds: [String]? = nil,
        removeLabelIds: [String]? = nil,
        forward: String? = nil,
        markAsRead: Bool? = nil,
        archive: Bool? = nil,
        delete: Bool? = nil,
        alwaysMarkAsRead: Bool? = nil,
        neverMarkAsRead: Bool? = nil,
        neverSpam: Bool? = nil,
        star: Bool? = nil
    ) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
        self.forward = forward
        self.markAsRead = markAsRead
        self.archive = archive
        self.delete = delete
        self.alwaysMarkAsRead = alwaysMarkAsRead
        self.neverMarkAsRead = neverMarkAsRead
        self.neverSpam = neverSpam
        self.star = star
    }
}

struct EmailDetail: Codable {
    let id: Int
    let gmail_id: String
    let thread_id: String
    let subject: String
    let sender: String
    let sender_name: String?
    let recipients_to: String?
    let recipients_cc: String?
    let recipients_bcc: String?
    let body_text: String
    let body_html: String?
    let snippet: String
    let is_read: Bool
    let is_starred: Bool
    let labels: [String]
    let received_at: String
    let account_email: String
    let created_at: String
}

struct ErrorResponse: Codable {
    let error: String?
}

struct GmailAuthResponse: Codable {
    let authorization_url: String
}

struct SyncResponse: Codable {
    let synced: Int
    let message: String
    let most_recent_email_at: String?
    let errors: [String]?
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case invalidRequest
    case invalidResponse
    case unauthorized
    case httpError(Int)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid request"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized. Please login again."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        }
    }
}

