//
//  GmailAPIServiceTests.swift
//  emptyMyInboxTests
//
//  Unit tests for GmailAPIService.swift
//

import Testing
@testable import emptyMyInbox
import Foundation

struct GmailAPIServiceTests {
    
    // MARK: - Message Parsing Tests
    
    @Test("Parse GmailMessage to EmailListItem")
    func testParseEmailListItem() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test Subject"),
            GmailHeader(name: "From", value: "John Doe <john@example.com>"),
            GmailHeader(name: "To", value: "recipient@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg123",
            threadId: "thread123",
            snippet: "Test snippet",
            payload: payload,
            labelIds: ["INBOX", "UNREAD"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 1)
        
        #expect(emailItem.id == 1)
        #expect(emailItem.gmail_id == "msg123")
        #expect(emailItem.subject == "Test Subject")
        #expect(emailItem.sender == "john@example.com")
        #expect(emailItem.sender_name == "John Doe")
        #expect(emailItem.snippet == "Test snippet")
        #expect(emailItem.is_read == false) // Has UNREAD label
        #expect(emailItem.is_starred == false)
        #expect(emailItem.labels.contains("INBOX"))
        #expect(emailItem.labels.contains("UNREAD"))
    }
    
    @Test("Parse GmailMessage to EmailListItem with starred label")
    func testParseEmailListItemStarred() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Starred Email"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg456",
            threadId: "thread456",
            snippet: "Starred snippet",
            payload: payload,
            labelIds: ["INBOX", "STARRED"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 2)
        
        #expect(emailItem.is_starred == true)
        #expect(emailItem.is_read == true) // No UNREAD label
    }
    
    @Test("Parse GmailMessage to EmailDetail")
    func testParseEmailDetail() {
        let service = GmailAPIService.shared
        
        // Create base64 encoded body
        let bodyText = "This is the email body"
        let bodyData = bodyText.data(using: .utf8)!
        let base64Body = bodyData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test Email"),
            GmailHeader(name: "From", value: "sender@example.com"),
            GmailHeader(name: "To", value: "recipient@example.com"),
            GmailHeader(name: "Cc", value: "cc@example.com")
        ]
        
        let body = GmailBody(data: base64Body, size: bodyData.count)
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: body
        )
        
        let gmailMessage = GmailMessage(
            id: "msg789",
            threadId: "thread789",
            snippet: "Test snippet",
            payload: payload,
            labelIds: ["INBOX", "UNREAD"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailDetail = service.parseEmailDetail(from: gmailMessage, accountEmail: "test@example.com", emailId: 3)
        
        #expect(emailDetail.id == 3)
        #expect(emailDetail.gmail_id == "msg789")
        #expect(emailDetail.subject == "Test Email")
        #expect(emailDetail.sender == "sender@example.com")
        #expect(emailDetail.recipients_to == "recipient@example.com")
        #expect(emailDetail.recipients_cc == "cc@example.com")
        #expect(emailDetail.body_text.contains("email body"))
    }
    
    @Test("Parse GmailMessage to EmailMetadata")
    func testParseEmailMetadata() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Metadata Test"),
            GmailHeader(name: "From", value: "Jane Doe <jane@example.com>")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg999",
            threadId: "thread999",
            snippet: "Metadata snippet",
            payload: payload,
            labelIds: ["INBOX", "UNREAD"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let metadata = service.parseEmailMetadata(from: gmailMessage, accountEmail: "test@example.com", emailId: 4)
        
        #expect(metadata.id == 4)
        #expect(metadata.gmail_id == "msg999")
        #expect(metadata.subject == "Metadata Test")
        #expect(metadata.sender == "jane@example.com")
        #expect(metadata.sender_name == "Jane Doe")
        #expect(metadata.is_read == false)
        #expect(metadata.is_starred == false)
    }
    
    @Test("Parse email with sender name only")
    func testParseEmailWithSenderNameOnly() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test"),
            GmailHeader(name: "From", value: "justanemail@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg111",
            threadId: "thread111",
            snippet: "Test",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 5)
        
        #expect(emailItem.sender == "justanemail@example.com")
        #expect(emailItem.sender_name == nil || emailItem.sender_name?.isEmpty == true)
    }
    
    @Test("Parse email with HTML body")
    func testParseEmailWithHTMLBody() {
        let service = GmailAPIService.shared
        
        let htmlBody = "<html><body><p>HTML content</p></body></html>"
        let htmlData = htmlBody.data(using: .utf8)!
        let base64HTML = htmlData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let headers = [
            GmailHeader(name: "Subject", value: "HTML Email"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let htmlPart = GmailPart(
            mimeType: "text/html",
            filename: nil,
            body: GmailBody(data: base64HTML, size: htmlData.count),
            parts: nil
        )
        
        let payload = GmailPayload(
            mimeType: "multipart/alternative",
            headers: headers,
            parts: [htmlPart],
            body: nil
        )
        
        let gmailMessage = GmailMessage(
            id: "msg222",
            threadId: "thread222",
            snippet: "HTML snippet",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailDetail = service.parseEmailDetail(from: gmailMessage, accountEmail: "test@example.com", emailId: 6)
        
        #expect(emailDetail.body_html != nil)
        #expect(emailDetail.body_html?.contains("HTML content") == true)
    }
    
    @Test("Parse email with nested parts")
    func testParseEmailWithNestedParts() {
        let service = GmailAPIService.shared
        
        let textBody = "Plain text content"
        let textData = textBody.data(using: .utf8)!
        let base64Text = textData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let htmlBody = "<p>HTML content</p>"
        let htmlData = htmlBody.data(using: .utf8)!
        let base64HTML = htmlData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let textPart = GmailPart(
            mimeType: "text/plain",
            filename: nil,
            body: GmailBody(data: base64Text, size: textData.count),
            parts: nil
        )
        
        let htmlPart = GmailPart(
            mimeType: "text/html",
            filename: nil,
            body: GmailBody(data: base64HTML, size: htmlData.count),
            parts: nil
        )
        
        let multipart = GmailPart(
            mimeType: "multipart/alternative",
            filename: nil,
            body: nil,
            parts: [textPart, htmlPart]
        )
        
        let headers = [
            GmailHeader(name: "Subject", value: "Multipart Email"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "multipart/alternative",
            headers: headers,
            parts: [multipart],
            body: nil
        )
        
        let gmailMessage = GmailMessage(
            id: "msg333",
            threadId: "thread333",
            snippet: "Multipart snippet",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailDetail = service.parseEmailDetail(from: gmailMessage, accountEmail: "test@example.com", emailId: 7)
        
        #expect(emailDetail.body_text.contains("Plain text content"))
        #expect(emailDetail.body_html?.contains("HTML content") == true)
    }
    
    // MARK: - Email ID Generation Tests
    
    @Test("getEmailId generates consistent IDs")
    func testGetEmailIdConsistency() {
        let service = GmailAPIService.shared
        
        let gmailId = "test_gmail_id_12345"
        let id1 = service.getEmailId(for: gmailId)
        let id2 = service.getEmailId(for: gmailId)
        
        #expect(id1 == id2) // Should be consistent
        #expect(id1 > 0) // Should be positive
    }
    
    @Test("getEmailId generates different IDs for different Gmail IDs")
    func testGetEmailIdUniqueness() {
        let service = GmailAPIService.shared
        
        let id1 = service.getEmailId(for: "gmail_id_1")
        let id2 = service.getEmailId(for: "gmail_id_2")
        
        #expect(id1 != id2)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Parse handles missing payload gracefully")
    func testParseHandlesMissingPayload() {
        let service = GmailAPIService.shared
        
        let gmailMessage = GmailMessage(
            id: "msg444",
            threadId: "thread444",
            snippet: "Test",
            payload: nil,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 8)
        
        #expect(emailItem.subject == "")
        #expect(emailItem.sender == "")
    }
    
    @Test("Parse handles missing headers gracefully")
    func testParseHandlesMissingHeaders() {
        let service = GmailAPIService.shared
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: [],
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg555",
            threadId: "thread555",
            snippet: "Test",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 9)
        
        #expect(emailItem.subject == "")
        #expect(emailItem.sender == "")
    }
    
    @Test("Parse handles invalid date gracefully")
    func testParseHandlesInvalidDate() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg666",
            threadId: "thread666",
            snippet: "Test",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: "invalid_date"
        )
        
        // Should not crash, should use current date as fallback
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 10)
        
        #expect(emailItem.id == 10)
        #expect(!emailItem.received_at.isEmpty)
    }
    
    // MARK: - Edge Cases
    
    @Test("Parse handles empty snippet")
    func testParseHandlesEmptySnippet() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg777",
            threadId: "thread777",
            snippet: "",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 11)
        
        #expect(emailItem.snippet == "")
    }
    
    @Test("Parse handles empty labels array")
    func testParseHandlesEmptyLabels() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test"),
            GmailHeader(name: "From", value: "sender@example.com")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg888",
            threadId: "thread888",
            snippet: "Test",
            payload: payload,
            labelIds: [],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 12)
        
        #expect(emailItem.labels.isEmpty)
        #expect(emailItem.is_read == true) // No UNREAD label means read
        #expect(emailItem.is_starred == false)
    }
    
    @Test("Parse handles complex From header format")
    func testParseHandlesComplexFromHeader() {
        let service = GmailAPIService.shared
        
        let headers = [
            GmailHeader(name: "Subject", value: "Test"),
            GmailHeader(name: "From", value: "\"John Doe\" <john.doe@example.com>")
        ]
        
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        
        let gmailMessage = GmailMessage(
            id: "msg999",
            threadId: "thread999",
            snippet: "Test",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        
        let emailItem = service.parseEmailListItem(from: gmailMessage, accountEmail: "test@example.com", emailId: 13)
        
        #expect(emailItem.sender == "john.doe@example.com")
        #expect(emailItem.sender_name == "John Doe")
    }
}
