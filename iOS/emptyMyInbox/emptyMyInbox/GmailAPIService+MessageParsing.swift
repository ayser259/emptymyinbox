//
//  GmailAPIService+MessageParsing.swift
//  emptyMyInbox
//
//  Message parsing and conversion utilities
//

import Foundation

extension GmailAPIService {
    // MARK: - Message Parsing
    
    /// Parse GmailMessage to EmailMetadata (lightweight - no body content)
    func parseEmailMetadata(from gmailMessage: GmailMessage, accountEmail: String, emailId: Int) -> EmailMetadata {
        let headers = extractHeaders(from: gmailMessage.payload)
        let subject = headers["subject"] ?? ""
        let from = headers["from"] ?? ""
        let senderEmail = extractEmail(from: from)
        let senderName = extractName(from: from)
        
        let isRead = !gmailMessage.labelIds.contains("UNREAD")
        let isStarred = gmailMessage.labelIds.contains("STARRED")
        
        // Parse date
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
    
    /// Parse GmailMessage to EmailListItem
    func parseEmailListItem(from gmailMessage: GmailMessage, accountEmail: String, emailId: Int) -> EmailListItem {
        let headers = extractHeaders(from: gmailMessage.payload)
        let subject = headers["subject"] ?? ""
        let from = headers["from"] ?? ""
        let senderEmail = extractEmail(from: from)
        let senderName = extractName(from: from)
        
        let isRead = !gmailMessage.labelIds.contains("UNREAD")
        let isStarred = gmailMessage.labelIds.contains("STARRED")
        
        // Parse date
        let receivedAt = parseDate(from: gmailMessage.internalDate) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let receivedAtString = dateFormatter.string(from: receivedAt)
        
        return EmailListItem(
            id: emailId,
            gmail_id: gmailMessage.id,
            subject: subject,
            sender: senderEmail,
            sender_name: senderName.isEmpty ? nil : senderName,
            snippet: gmailMessage.snippet,
            is_read: isRead,
            is_starred: isStarred,
            labels: gmailMessage.labelIds,
            received_at: receivedAtString,
            account_email: accountEmail,
            marked_read_at: nil // New emails from Gmail don't have a marked_read_at timestamp
        )
    }
    
    /// Parse GmailMessage to EmailDetail
    func parseEmailDetail(from gmailMessage: GmailMessage, accountEmail: String, emailId: Int) -> EmailDetail {
        let headers = extractHeaders(from: gmailMessage.payload)
        let subject = headers["subject"] ?? ""
        let from = headers["from"] ?? ""
        let senderEmail = extractEmail(from: from)
        let senderName = extractName(from: from)
        let to = headers["to"] ?? ""
        let cc = headers["cc"] ?? ""
        let bcc = headers["bcc"] ?? ""
        
        let (bodyText, bodyHTML) = extractBody(from: gmailMessage.payload)
        
        let isRead = !gmailMessage.labelIds.contains("UNREAD")
        let isStarred = gmailMessage.labelIds.contains("STARRED")
        
        // Parse date
        let receivedAt = parseDate(from: gmailMessage.internalDate) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let receivedAtString = dateFormatter.string(from: receivedAt)
        let createdAtString = receivedAtString // Use same date for created_at
        
        return EmailDetail(
            id: emailId,
            gmail_id: gmailMessage.id,
            thread_id: gmailMessage.threadId,
            subject: subject,
            sender: senderEmail,
            sender_name: senderName.isEmpty ? nil : senderName,
            recipients_to: to.isEmpty ? nil : to,
            recipients_cc: cc.isEmpty ? nil : cc,
            recipients_bcc: bcc.isEmpty ? nil : bcc,
            body_text: bodyText,
            body_html: bodyHTML,
            snippet: gmailMessage.snippet,
            is_read: isRead,
            is_starred: isStarred,
            labels: gmailMessage.labelIds,
            received_at: receivedAtString,
            account_email: accountEmail,
            created_at: createdAtString
        )
    }
    
    // MARK: - Helper Methods
    
    /// Extract headers from GmailPayload (public access for unsubscribe functionality)
    func extractHeaders(from payload: GmailPayload?) -> [String: String] {
        guard let payload = payload else { return [:] }
        
        var headers: [String: String] = [:]
        for header in payload.headers {
            headers[header.name.lowercased()] = header.value
        }
        return headers
    }
    
    private func extractEmail(from headerValue: String) -> String {
        // Extract email from "Name <email@example.com>" or just "email@example.com"
        if let range = headerValue.range(of: "<") {
            let emailPart = String(headerValue[range.upperBound...])
            if let endRange = emailPart.range(of: ">") {
                return String(emailPart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return headerValue.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractName(from headerValue: String) -> String {
        // Extract name from "Name <email@example.com>"
        if let range = headerValue.range(of: "<") {
            let namePart = String(headerValue[..<range.lowerBound])
            return namePart.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ""
    }
    
    private func extractBody(from payload: GmailPayload?) -> (text: String, html: String?) {
        guard let payload = payload else { return ("", nil) }
        
        var bodyText = ""
        var bodyHTML: String? = nil
        
        func extractFromPart(_ part: GmailPart) {
            if let mimeType = part.mimeType {
                if mimeType == "text/plain", let body = part.body, let data = body.data {
                    if let decoded = decodeBase64URL(data) {
                        bodyText = decoded
                    }
                } else if mimeType == "text/html", let body = part.body, let data = body.data {
                    if let decoded = decodeBase64URL(data) {
                        bodyHTML = decoded
                    }
                }
            }
            
            // Recursively process nested parts
            if let parts = part.parts {
                for subPart in parts {
                    extractFromPart(subPart)
                }
            }
        }
        
        // Check if payload has direct body - MUST check mimeType to determine if HTML or plain text
        if let body = payload.body, let data = body.data {
            if let decoded = decodeBase64URL(data) {
                // Check the payload's mimeType to store in correct field
                if payload.mimeType == "text/html" {
                    bodyHTML = decoded
                } else {
                    bodyText = decoded
                }
            }
        }
        
        // Process parts
        if let parts = payload.parts {
            for part in parts {
                extractFromPart(part)
            }
        }
        
        // Fallback: If bodyHTML is nil but bodyText looks like HTML, move it to bodyHTML
        // This handles edge cases where HTML content ends up in bodyText
        if bodyHTML == nil && !bodyText.isEmpty {
            let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") || 
               (trimmed.hasPrefix("<") && (trimmed.contains("<head") || trimmed.contains("<body") || trimmed.contains("<div") || trimmed.contains("<table"))) {
                bodyHTML = bodyText
                bodyText = "" // Clear bodyText since it's actually HTML
            }
        }
        
        return (bodyText, bodyHTML)
    }
    
    private func decodeBase64URL(_ base64String: String) -> String? {
        // Gmail uses Base64URL encoding (URL-safe base64)
        var base64 = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    private func parseDate(from internalDate: String) -> Date? {
        // Gmail internalDate is milliseconds since epoch
        if let milliseconds = Double(internalDate) {
            return Date(timeIntervalSince1970: milliseconds / 1000.0)
        }
        return nil
    }
    
    // MARK: - Email ID Generation
    
    private func generateEmailId(for gmailId: String) -> Int {
        StableID.emailId(gmailId: gmailId)
    }
    
    func getEmailId(for gmailId: String) -> Int {
        return generateEmailId(for: gmailId)
    }
}

