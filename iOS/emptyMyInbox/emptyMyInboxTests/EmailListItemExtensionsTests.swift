//
//  EmailListItemExtensionsTests.swift
//  emptyMyInboxTests
//
//  Unit tests for EmailListItem+Extensions.swift
//

import Foundation
import Testing
@testable import emptyMyInbox

struct EmailListItemExtensionsTests {
    
    func createTestEmailListItem(
        id: Int = 1,
        isRead: Bool = false,
        isStarred: Bool = false,
        markedReadAt: String? = nil
    ) -> EmailListItem {
        return EmailListItem(
            id: id,
            gmail_id: "msg\(id)",
            subject: "Test Email",
            sender: "sender@example.com",
            sender_name: "Test Sender",
            snippet: "Test snippet",
            is_read: isRead,
            is_starred: isStarred,
            labels: isRead ? ["INBOX"] : ["INBOX", "UNREAD"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com",
            marked_read_at: markedReadAt
        )
    }
    
    // MARK: - Update isRead Tests
    
    @Test("Updating isRead from false to true sets marked_read_at timestamp")
    func testUpdatingIsReadFromFalseToTrue() {
        let email = createTestEmailListItem(isRead: false)
        
        let updated = email.updating(isRead: true)
        
        #expect(updated.is_read == true)
        #expect(updated.marked_read_at != nil)
        #expect(updated.marked_read_at?.isEmpty == false)
    }
    
    @Test("Updating isRead from true to false clears marked_read_at")
    func testUpdatingIsReadFromTrueToFalse() {
        let email = createTestEmailListItem(isRead: true, markedReadAt: "2024-01-02T00:00:00Z")
        
        let updated = email.updating(isRead: false)
        
        #expect(updated.is_read == false)
        #expect(updated.marked_read_at == nil)
    }
    
    @Test("Updating isRead from true to true keeps existing marked_read_at")
    func testUpdatingIsReadFromTrueToTrue() {
        let existingTimestamp = "2024-01-02T00:00:00Z"
        let email = createTestEmailListItem(isRead: true, markedReadAt: existingTimestamp)
        
        let updated = email.updating(isRead: true)
        
        #expect(updated.is_read == true)
        #expect(updated.marked_read_at == existingTimestamp)
    }
    
    @Test("Updating isRead with custom markedReadAt uses provided timestamp")
    func testUpdatingIsReadWithCustomTimestamp() {
        let email = createTestEmailListItem(isRead: false)
        let customTimestamp = "2024-01-15T12:00:00Z"
        
        let updated = email.updating(isRead: true, markedReadAt: customTimestamp)
        
        #expect(updated.is_read == true)
        #expect(updated.marked_read_at == customTimestamp)
    }
    
    @Test("Updating isRead to nil does not change is_read")
    func testUpdatingIsReadToNil() {
        let email = createTestEmailListItem(isRead: false)
        
        let updated = email.updating(isRead: nil)
        
        #expect(updated.is_read == false) // Unchanged
        #expect(updated.marked_read_at == nil)
    }
    
    // MARK: - Update isStarred Tests
    
    @Test("Updating isStarred from false to true")
    func testUpdatingIsStarredFromFalseToTrue() {
        let email = createTestEmailListItem(isStarred: false)
        
        let updated = email.updating(isStarred: true)
        
        #expect(updated.is_starred == true)
        #expect(updated.is_read == email.is_read) // Unchanged
    }
    
    @Test("Updating isStarred from true to false")
    func testUpdatingIsStarredFromTrueToFalse() {
        let email = createTestEmailListItem(isStarred: true)
        
        let updated = email.updating(isStarred: false)
        
        #expect(updated.is_starred == false)
    }
    
    @Test("Updating isStarred to nil does not change is_starred")
    func testUpdatingIsStarredToNil() {
        let email = createTestEmailListItem(isStarred: true)
        
        let updated = email.updating(isStarred: nil)
        
        #expect(updated.is_starred == true) // Unchanged
    }
    
    // MARK: - Combined Updates Tests
    
    @Test("Updating both isRead and isStarred simultaneously")
    func testUpdatingBothIsReadAndIsStarred() {
        let email = createTestEmailListItem(isRead: false, isStarred: false)
        
        let updated = email.updating(isRead: true, isStarred: true)
        
        #expect(updated.is_read == true)
        #expect(updated.is_starred == true)
        #expect(updated.marked_read_at != nil)
    }
    
    @Test("Updating multiple properties preserves other fields")
    func testUpdatingPreservesOtherFields() {
        let email = createTestEmailListItem(
            id: 123,
            isRead: false,
            isStarred: false
        )
        
        let updated = email.updating(isRead: true, isStarred: true)
        
        #expect(updated.id == 123)
        #expect(updated.gmail_id == "msg123")
        #expect(updated.subject == "Test Email")
        #expect(updated.sender == "sender@example.com")
        #expect(updated.sender_name == "Test Sender")
        #expect(updated.snippet == "Test snippet")
        #expect(updated.account_email == "test@example.com")
    }
    
    // MARK: - Edge Cases
    
    @Test("Updating with all nil parameters returns unchanged email")
    func testUpdatingWithAllNil() {
        let email = createTestEmailListItem(isRead: false, isStarred: false)
        
        let updated = email.updating(isRead: nil, isStarred: nil, markedReadAt: nil)
        
        #expect(updated.is_read == false)
        #expect(updated.is_starred == false)
        #expect(updated.marked_read_at == nil)
    }
    
    @Test("Updating markedReadAt when already read preserves timestamp if not changing isRead")
    func testUpdatingMarkedReadAtWhenAlreadyRead() {
        let existingTimestamp = "2024-01-02T00:00:00Z"
        let email = createTestEmailListItem(isRead: true, markedReadAt: existingTimestamp)
        
        let updated = email.updating(markedReadAt: "2024-01-03T00:00:00Z")
        
        #expect(updated.is_read == true)
        #expect(updated.marked_read_at == "2024-01-03T00:00:00Z")
    }
    
    @Test("Updating markedReadAt when unread does not set timestamp")
    func testUpdatingMarkedReadAtWhenUnread() {
        let email = createTestEmailListItem(isRead: false)
        
        let updated = email.updating(markedReadAt: "2024-01-02T00:00:00Z")
        
        #expect(updated.is_read == false)
        // When unread, markedReadAt should remain nil even if provided
        // (only gets set when marking as read)
        #expect(updated.marked_read_at == nil)
    }
    
    @Test("Updating from read to unread then back to read creates new timestamp")
    func testUpdatingReadToUnreadToRead() {
        let email = createTestEmailListItem(isRead: true, markedReadAt: "2024-01-02T00:00:00Z")
        
        // First, mark as unread
        let unread = email.updating(isRead: false)
        #expect(unread.is_read == false)
        #expect(unread.marked_read_at == nil)
        
        // Then, mark as read again
        let readAgain = unread.updating(isRead: true)
        #expect(readAgain.is_read == true)
        #expect(readAgain.marked_read_at != nil)
        // Should be a new timestamp, not the old one
        #expect(readAgain.marked_read_at != "2024-01-02T00:00:00Z")
    }
}
