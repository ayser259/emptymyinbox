//
//  MockURLSession.swift
//  emptyMyInboxTests
//
//  Mock URLSession for testing network requests
//

import Foundation

class MockURLSession {
    // Response storage
    private var responses: [URL: MockResponse] = [:]
    
    // Behavior control
    var defaultStatusCode = 200
    var defaultDelay: TimeInterval = 0
    var shouldFailAll = false
    var globalError: Error?
    
    // Call tracking
    var requestCallCount = 0
    var requestHistory: [URLRequest] = []
    
    struct MockResponse {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
        let delay: TimeInterval
    }
    
    init() {
        // Setup default successful response
        setupDefaultResponses()
    }
    
    private func setupDefaultResponses() {
        // Default token refresh response
        if let tokenURL = URL(string: "https://oauth2.googleapis.com/token") {
            let tokenData = """
            {
                "access_token": "new_access_token",
                "expires_in": 3600,
                "token_type": "Bearer"
            }
            """.data(using: .utf8)
            let response = HTTPURLResponse(url: tokenURL, statusCode: 200, httpVersion: nil, headerFields: nil)
            setResponse(for: tokenURL, data: tokenData, response: response, error: nil)
        }
        
        // Default Gmail API response
        if let gmailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile") {
            let profileData = """
            {
                "emailAddress": "test@example.com"
            }
            """.data(using: .utf8)
            let response = HTTPURLResponse(url: gmailURL, statusCode: 200, httpVersion: nil, headerFields: nil)
            setResponse(for: gmailURL, data: profileData, response: response, error: nil)
        }
    }
    
    // MARK: - Response Configuration
    
    func setResponse(
        for url: URL,
        data: Data?,
        response: HTTPURLResponse?,
        error: Error?,
        delay: TimeInterval = 0
    ) {
        responses[url] = MockResponse(
            data: data,
            response: response,
            error: error,
            delay: delay
        )
    }
    
    func setResponse(
        for urlString: String,
        data: Data?,
        statusCode: Int = 200,
        error: Error? = nil,
        delay: TimeInterval = 0
    ) {
        guard let url = URL(string: urlString) else { return }
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        setResponse(for: url, data: data, response: response, error: error, delay: delay)
    }
    
    func setRateLimitResponse(for urlString: String, retryAfter: Int = 1) {
        guard let url = URL(string: urlString) else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "\(retryAfter)"]
        )
        let error = NSError(
            domain: "MockURLSession",
            code: 429,
            userInfo: [NSLocalizedDescriptionKey: "Rate Limit Exceeded"]
        )
        setResponse(for: url, data: nil, response: response, error: error)
    }
    
    func setNetworkError(for urlString: String, error: Error) {
        guard let url = URL(string: urlString) else { return }
        setResponse(for: url, data: nil, response: nil, error: error)
    }
    
    func setTimeoutError(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let error = URLError(.timedOut)
        setResponse(for: url, data: nil, response: nil, error: error)
    }
    
    // MARK: - URLSession Data Task
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCallCount += 1
        requestHistory.append(request)
        
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        
        if shouldFailAll {
            throw globalError ?? URLError(.unknown)
        }
        
        // Find matching response (exact match or base URL match)
        var mockResponse: MockResponse?
        
        // Try exact match first
        if let response = responses[url] {
            mockResponse = response
        } else {
            // Try base URL match
            let baseURL = URL(string: url.scheme! + "://" + url.host! + url.path)!
            if let response = responses[baseURL] {
                mockResponse = response
            }
        }
        
        // Use default if no specific response found
        let response = mockResponse ?? MockResponse(
            data: nil,
            response: HTTPURLResponse(url: url, statusCode: defaultStatusCode, httpVersion: nil, headerFields: nil),
            error: nil,
            delay: defaultDelay
        )
        
        // Apply delay
        if response.delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(response.delay * 1_000_000_000))
        }
        
        // Return error if set
        if let error = response.error {
            throw error
        }
        
        // Return data and response
        guard let httpResponse = response.response else {
            throw URLError(.badServerResponse)
        }
        
        // Check status code
        if httpResponse.statusCode >= 400 {
            let error = NSError(
                domain: "MockURLSession",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            )
            throw error
        }
        
        return (response.data ?? Data(), httpResponse)
    }
    
    // MARK: - Test Helpers
    
    func clearResponses() {
        responses.removeAll()
        setupDefaultResponses()
    }
    
    func reset() {
        clearResponses()
        requestCallCount = 0
        requestHistory.removeAll()
        shouldFailAll = false
        globalError = nil
        defaultStatusCode = 200
        defaultDelay = 0
    }
    
    func getLastRequest() -> URLRequest? {
        return requestHistory.last
    }
    
    func getAllRequests() -> [URLRequest] {
        return requestHistory
    }
}

