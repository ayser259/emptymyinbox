//
//  ModelsTests.swift
//  emptyMyInboxTests
//
//  Unit tests for Models.swift
//

import Foundation
import Testing
@testable import emptyMyInbox

struct ModelsTests {
    
    // MARK: - EmailListItem Tests
    
    @Test("EmailListItem decodes with missing marked_read_at")
    func testEmailListItemDecodingWithoutMarkedReadAt() throws {
        let json = """
        {
            "id": 1,
            "gmail_id": "msg123",
            "subject": "Test Subject",
            "sender": "test@example.com",
            "sender_name": "Test Sender",
            "snippet": "Test snippet",
            "is_read": false,
            "is_starred": false,
            "labels": ["INBOX", "UNREAD"],
            "received_at": "2024-01-01T00:00:00Z",
            "account_email": "user@example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let email = try decoder.decode(EmailListItem.self, from: data)
        
        #expect(email.id == 1)
        #expect(email.gmail_id == "msg123")
        #expect(email.marked_read_at == nil)
    }
    
    @Test("EmailListItem decodes with marked_read_at")
    func testEmailListItemDecodingWithMarkedReadAt() throws {
        let json = """
        {
            "id": 1,
            "gmail_id": "msg123",
            "subject": "Test Subject",
            "sender": "test@example.com",
            "sender_name": null,
            "snippet": "Test snippet",
            "is_read": true,
            "is_starred": false,
            "labels": ["INBOX"],
            "received_at": "2024-01-01T00:00:00Z",
            "account_email": "user@example.com",
            "marked_read_at": "2024-01-02T00:00:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let email = try decoder.decode(EmailListItem.self, from: data)
        
        #expect(email.marked_read_at == "2024-01-02T00:00:00Z")
        #expect(email.sender_name == nil)
    }
    
    @Test("EmailListItem handles empty labels array")
    func testEmailListItemWithEmptyLabels() throws {
        let json = """
        {
            "id": 1,
            "gmail_id": "msg123",
            "subject": "Test",
            "sender": "test@example.com",
            "sender_name": null,
            "snippet": "Test",
            "is_read": false,
            "is_starred": false,
            "labels": [],
            "received_at": "2024-01-01T00:00:00Z",
            "account_email": "user@example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let email = try decoder.decode(EmailListItem.self, from: data)
        
        #expect(email.labels.isEmpty)
    }
    
    // MARK: - EmailMetadata Tests
    
    @Test("EmailMetadata converts to EmailListItem")
    func testEmailMetadataToEmailListItem() {
        let metadata = EmailMetadata(
            id: 1,
            gmail_id: "msg123",
            thread_id: "thread1",
            subject: "Test Subject",
            sender: "test@example.com",
            sender_name: "Test Sender",
            snippet: "Test snippet",
            is_read: false,
            is_starred: true,
            labels: ["INBOX", "UNREAD", "STARRED"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "user@example.com"
        )
        
        let emailItem = metadata.toEmailListItem()
        
        #expect(emailItem.id == 1)
        #expect(emailItem.gmail_id == "msg123")
        #expect(emailItem.subject == "Test Subject")
        #expect(emailItem.sender == "test@example.com")
        #expect(emailItem.sender_name == "Test Sender")
        #expect(emailItem.is_read == false)
        #expect(emailItem.is_starred == true)
        #expect(emailItem.marked_read_at == nil) // Should be nil for new conversions
    }
    
    @Test("EmailMetadata with nil sender_name converts correctly")
    func testEmailMetadataWithNilSenderName() {
        let metadata = EmailMetadata(
            id: 1,
            gmail_id: "msg123",
            thread_id: "thread1",
            subject: "Test",
            sender: "test@example.com",
            sender_name: nil,
            snippet: "Test",
            is_read: false,
            is_starred: false,
            labels: ["INBOX"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "user@example.com"
        )
        
        let emailItem = metadata.toEmailListItem()
        
        #expect(emailItem.sender_name == nil)
    }
    
    // MARK: - FilterCriteria Tests
    
    @Test("FilterCriteria encodes and decodes correctly")
    func testFilterCriteriaEncodingDecoding() throws {
        let criteria = FilterCriteria(
            from: "sender@example.com",
            to: "recipient@example.com",
            subject: "Test Subject",
            hasAttachment: true,
            excludeChats: true,
            size: 1024,
            sizeComparison: "larger"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        #expect(decoded.from == "sender@example.com")
        #expect(decoded.to == "recipient@example.com")
        #expect(decoded.subject == "Test Subject")
        #expect(decoded.hasAttachment == true)
        #expect(decoded.excludeChats == true)
        #expect(decoded.size == 1024)
        #expect(decoded.sizeComparison == "larger")
    }
    
    @Test("FilterCriteria handles nil values")
    func testFilterCriteriaWithNilValues() throws {
        let criteria = FilterCriteria(
            from: nil,
            to: nil,
            subject: nil,
            hasAttachment: nil,
            excludeChats: nil,
            size: nil,
            sizeComparison: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        #expect(decoded.from == nil)
        #expect(decoded.to == nil)
        #expect(decoded.subject == nil)
        #expect(decoded.hasAttachment == nil)
        #expect(decoded.excludeChats == nil)
        #expect(decoded.size == nil)
        #expect(decoded.sizeComparison == nil)
    }
    
    @Test("FilterCriteria handles partial values")
    func testFilterCriteriaWithPartialValues() throws {
        let criteria = FilterCriteria(
            from: "sender@example.com",
            to: nil,
            subject: "Test",
            hasAttachment: true,
            excludeChats: nil,
            size: nil,
            sizeComparison: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        #expect(decoded.from == "sender@example.com")
        #expect(decoded.subject == "Test")
        #expect(decoded.hasAttachment == true)
        #expect(decoded.to == nil)
    }
    
    // MARK: - FilterActions Tests
    
    @Test("FilterActions encodes and decodes correctly")
    func testFilterActionsEncodingDecoding() throws {
        let actions = FilterActions(
            addLabelIds: ["Label1", "Label2"],
            removeLabelIds: ["Label3"],
            forward: "forward@example.com",
            markAsRead: true,
            archive: false,
            delete: false,
            alwaysMarkAsRead: true,
            neverMarkAsRead: false,
            neverSpam: true,
            star: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(actions)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterActions.self, from: data)
        
        #expect(decoded.addLabelIds == ["Label1", "Label2"])
        #expect(decoded.removeLabelIds == ["Label3"])
        #expect(decoded.forward == "forward@example.com")
        #expect(decoded.markAsRead == true)
        #expect(decoded.archive == false)
        #expect(decoded.delete == false)
        #expect(decoded.alwaysMarkAsRead == true)
        #expect(decoded.neverMarkAsRead == false)
        #expect(decoded.neverSpam == true)
        #expect(decoded.star == true)
    }
    
    @Test("FilterActions handles nil values")
    func testFilterActionsWithNilValues() throws {
        let actions = FilterActions(
            addLabelIds: nil,
            removeLabelIds: nil,
            forward: nil,
            markAsRead: nil,
            archive: nil,
            delete: nil,
            alwaysMarkAsRead: nil,
            neverMarkAsRead: nil,
            neverSpam: nil,
            star: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(actions)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterActions.self, from: data)
        
        #expect(decoded.addLabelIds == nil)
        #expect(decoded.removeLabelIds == nil)
        #expect(decoded.forward == nil)
        #expect(decoded.markAsRead == nil)
        #expect(decoded.archive == nil)
        #expect(decoded.delete == nil)
        #expect(decoded.alwaysMarkAsRead == nil)
        #expect(decoded.neverMarkAsRead == nil)
        #expect(decoded.neverSpam == nil)
        #expect(decoded.star == nil)
    }
    
    @Test("FilterActions handles empty arrays")
    func testFilterActionsWithEmptyArrays() throws {
        let actions = FilterActions(
            addLabelIds: [],
            removeLabelIds: [],
            forward: nil,
            markAsRead: nil,
            archive: nil,
            delete: nil,
            alwaysMarkAsRead: nil,
            neverMarkAsRead: nil,
            neverSpam: nil,
            star: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(actions)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterActions.self, from: data)
        
        #expect(decoded.addLabelIds == [])
        #expect(decoded.removeLabelIds == [])
    }
    
    // MARK: - Edge Cases
    
    @Test("EmailListItem handles invalid date format gracefully")
    func testEmailListItemWithInvalidDate() throws {
        // This test ensures the decoder doesn't crash on invalid dates
        // The received_at is stored as a String, so it should decode fine
        let json = """
        {
            "id": 1,
            "gmail_id": "msg123",
            "subject": "Test",
            "sender": "test@example.com",
            "sender_name": null,
            "snippet": "Test",
            "is_read": false,
            "is_starred": false,
            "labels": ["INBOX"],
            "received_at": "invalid-date",
            "account_email": "user@example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let email = try decoder.decode(EmailListItem.self, from: data)
        
        #expect(email.received_at == "invalid-date") // Should still decode as string
    }
    
    @Test("EmailListItem handles very long strings")
    func testEmailListItemWithLongStrings() throws {
        let longString = String(repeating: "a", count: 10000)
        let json = """
        {
            "id": 1,
            "gmail_id": "msg123",
            "subject": "\(longString)",
            "sender": "test@example.com",
            "sender_name": null,
            "snippet": "\(longString)",
            "is_read": false,
            "is_starred": false,
            "labels": ["INBOX"],
            "received_at": "2024-01-01T00:00:00Z",
            "account_email": "user@example.com"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let email = try decoder.decode(EmailListItem.self, from: data)
        
        #expect(email.subject.count == 10000)
        #expect(email.snippet.count == 10000)
    }
}

