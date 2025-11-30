//
//  UnsubscribeService.swift
//  emptyMyInbox
//
//  Service for handling email unsubscribes via List-Unsubscribe header
//

import Foundation

struct UnsubscribeResult {
    let success: Bool
    let message: String
    let method: UnsubscribeMethod?
    let details: String?  // Additional details for verification (URL, email address, etc.)
    let requiresManualAction: Bool  // True if user needs to complete unsubscribe manually
    
    var verificationInfo: String {
        guard let method = method else { return message }
        switch method {
        case .http(let url):
            if requiresManualAction {
                return "Tap to complete unsubscribe:\n\(url.host ?? url.absoluteString)"
            }
            return "Unsubscribe request sent to: \(url.host ?? url.absoluteString)\nNote: Some senders may require manual confirmation"
        case .mailto(let email):
            return "Unsubscribe email sent to: \(email)\nYou may receive a confirmation email"
        }
    }
    
    var manualActionURL: URL? {
        guard let method = method, requiresManualAction else { return nil }
        switch method {
        case .http(let url):
            return url
        case .mailto:
            return nil  // Can't open mailto in browser for manual action
        }
    }
}

enum UnsubscribeMethod {
    case http(url: URL)
    case mailto(email: String)
}

class UnsubscribeService {
    static let shared = UnsubscribeService()
    
    private init() {}
    
    /// Extract unsubscribe information from email headers
    /// Returns the unsubscribe method if found, nil otherwise
    func extractUnsubscribeInfo(from headers: [String: String]) -> UnsubscribeMethod? {
        // Check for List-Unsubscribe header (RFC 2369/RFC 8058)
        guard let listUnsubscribe = headers["list-unsubscribe"] else {
            return nil
        }
        
        // Parse the header value - can contain multiple methods separated by commas
        // Format: <mailto:unsubscribe@example.com>, <https://example.com/unsubscribe>
        let methods = listUnsubscribe.components(separatedBy: ",")
        
        for method in methods {
            let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove angle brackets if present
            let cleaned = trimmed
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for mailto link
            if cleaned.hasPrefix("mailto:") {
                let email = String(cleaned.dropFirst(7))
                if !email.isEmpty {
                    return .mailto(email: email)
                }
            }
            
            // Check for HTTP/HTTPS URL
            if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
                if let url = URL(string: cleaned) {
                    return .http(url: url)
                }
            }
        }
        
        return nil
    }
    
    /// Execute unsubscribe request
    /// Returns result indicating success or failure
    func executeUnsubscribe(method: UnsubscribeMethod, userEmail: String) async -> UnsubscribeResult {
        switch method {
        case .http(let url):
            return await executeHTTPUnsubscribe(url: url, userEmail: userEmail)
        case .mailto(let email):
            return await executeMailtoUnsubscribe(email: email, userEmail: userEmail)
        }
    }
    
    /// Execute HTTP-based unsubscribe (POST or GET request)
    private func executeHTTPUnsubscribe(url: URL, userEmail: String) async -> UnsubscribeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST" // RFC 8058 recommends POST
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userEmail, forHTTPHeaderField: "List-Unsubscribe-Post") // RFC 8058
        
        // Add user email as form data
        let body = "email=\(userEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                // 200-299 are success codes
                if (200...299).contains(httpResponse.statusCode) {
                    // Check if response indicates manual action needed
                    // Some senders return 200 but redirect to a confirmation page
                    let responseBody = String(data: data, encoding: .utf8) ?? ""
                    // One-click unsubscribes typically return minimal content (JSON success or small HTML)
                    // Manual confirmation pages are usually larger HTML pages with confirmation text
                    let responseSize = data.count
                    let hasConfirmationKeywords = responseBody.lowercased().contains("confirm") || 
                                                 responseBody.lowercased().contains("verify") ||
                                                 responseBody.lowercased().contains("click here")
                    // If response is large (>5KB) or has confirmation keywords, likely needs manual action
                    // Small responses (<5KB) without confirmation keywords are likely one-click success
                    let requiresManual = hasConfirmationKeywords || responseSize > 5000
                    
                    return UnsubscribeResult(
                        success: true,
                        message: requiresManual ? "Unsubscribe page opened - please complete manually" : "Successfully unsubscribed via HTTP",
                        method: .http(url: url),
                        details: "Request sent to: \(url.absoluteString)\nResponse: \(httpResponse.statusCode)\n\(requiresManual ? "⚠️ Manual confirmation may be required" : "")",
                        requiresManualAction: requiresManual
                    )
                } else {
                    // Non-2xx response - likely needs manual action
                    return UnsubscribeResult(
                        success: false,
                        message: "Automated unsubscribe failed (status \(httpResponse.statusCode))",
                        method: .http(url: url),
                        details: "URL: \(url.absoluteString)\nYou may need to complete unsubscribe manually",
                        requiresManualAction: true
                    )
                }
            }
            
            return UnsubscribeResult(
                success: false,
                message: "Invalid response from unsubscribe endpoint",
                method: .http(url: url),
                details: "URL: \(url.absoluteString)\nYou may need to complete unsubscribe manually",
                requiresManualAction: true
            )
        } catch {
            return UnsubscribeResult(
                success: false,
                message: "Failed to execute unsubscribe: \(error.localizedDescription)",
                method: .http(url: url),
                details: "URL: \(url.absoluteString)\nError: \(error.localizedDescription)\nYou may need to complete unsubscribe manually",
                requiresManualAction: true
            )
        }
    }
    
    /// Execute mailto-based unsubscribe (send email via Gmail API)
    private func executeMailtoUnsubscribe(email: String, userEmail: String) async -> UnsubscribeResult {
        // For mailto unsubscribes, we need to send an email via Gmail API
        // This requires the gmail.send scope
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: userEmail) else {
            return UnsubscribeResult(
                success: false,
                message: "Account not found",
                method: .mailto(email: email),
                details: "Target email: \(email)",
                requiresManualAction: false
            )
        }
        
        // Create unsubscribe email
        let subject = "Unsubscribe"
        let body = "Please unsubscribe me from this mailing list."
        
        do {
            try await gmailService.sendEmail(
                for: account,
                to: email,
                subject: subject,
                body: body
            )
            
            // Mailto always requires manual confirmation (they need to reply/confirm)
            return UnsubscribeResult(
                success: true,
                message: "Unsubscribe email sent",
                method: .mailto(email: email),
                details: "Email sent from: \(userEmail)\nTo: \(email)\nSubject: \(subject)\n⚠️ You may receive a confirmation email",
                requiresManualAction: true  // Mailto typically requires email confirmation
            )
        } catch {
            return UnsubscribeResult(
                success: false,
                message: "Failed to send unsubscribe email: \(error.localizedDescription)",
                method: .mailto(email: email),
                details: "Target email: \(email)\nError: \(error.localizedDescription)",
                requiresManualAction: false
            )
        }
    }
    
    /// Get unsubscribe info from an email by fetching its headers
    func getUnsubscribeInfo(for email: EmailDetail, accountEmail: String) async -> UnsubscribeMethod? {
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: accountEmail) else {
            return nil
        }
        
        do {
            // Fetch message with metadata to get headers
            let gmailMessage = try await gmailService.getMessageMetadata(for: account, messageId: email.gmail_id)
            let headers = gmailService.extractHeaders(from: gmailMessage.payload)
            return extractUnsubscribeInfo(from: headers)
        } catch {
            logError("Failed to get unsubscribe info: \(error)", category: "Unsubscribe")
            return nil
        }
    }
    
    /// Get unsubscribe info for a sender by checking their most recent email
    func getUnsubscribeInfoForSender(senderEmail: String, accountEmail: String) async -> UnsubscribeMethod? {
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: accountEmail) else {
            return nil
        }
        
        do {
            // Search for most recent email from this sender
            let query = "from:\(senderEmail) in:inbox"
            let (messages, _) = try await gmailService.listMessages(
                for: account,
                query: query,
                maxResults: 1
            )
            
            guard let firstMessage = messages.first else {
                return nil
            }
            
            // Get message metadata to extract headers
            let gmailMessage = try await gmailService.getMessageMetadata(for: account, messageId: firstMessage.id)
            let headers = gmailService.extractHeaders(from: gmailMessage.payload)
            return extractUnsubscribeInfo(from: headers)
        } catch {
            logError("Failed to get unsubscribe info for sender: \(error)", category: "Unsubscribe")
            return nil
        }
    }
}

// MARK: - GmailAPIService Extensions

extension GmailAPIService {
    /// Send email via Gmail API (for mailto unsubscribes)
    func sendEmail(for account: GmailAccount, to: String, subject: String, body: String) async throws {
        // Get valid access token (this will refresh if needed and update the account)
        let token = try await getValidAccessToken(for: account)
        
        let baseURL = "https://gmail.googleapis.com/gmail/v1"
        let url = URL(string: "\(baseURL)/users/me/messages/send")!
        
        // Create email message in RFC 2822 format
        let emailContent = """
        To: \(to)
        Subject: \(subject)
        Content-Type: text/plain; charset=UTF-8
        
        \(body)
        """
        
        // Base64URL encode the email content
        let emailData = emailContent.data(using: .utf8)!
        let base64Encoded = emailData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "raw": base64Encoded
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GmailAPIError.apiError("Failed to send email: \(response)")
        }
    }
}

