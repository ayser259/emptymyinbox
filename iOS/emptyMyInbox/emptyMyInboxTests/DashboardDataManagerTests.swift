//
//  DashboardDataManagerTests.swift
//  emptyMyInboxTests
//
//  Unit tests for DashboardDataManager.swift
//

import Testing
@testable import emptyMyInbox
import Foundation

struct DashboardDataManagerTests {
    
    // MARK: - Helper Methods
    
    func createTestEmailListItem(id: Int, isRead: Bool = false, isStarred: Bool = false) -> EmailListItem {
        var labels = isRead ? ["INBOX"] : ["INBOX", "UNREAD"]
        if isStarred {
            labels.append("STARRED")
        }
        
        return EmailListItem(
            id: id,
            gmail_id: "msg\(id)",
            subject: "Test Email \(id)",
            sender: "sender\(id)@example.com",
            sender_name: "Sender \(id)",
            snippet: "Test snippet \(id)",
            is_read: isRead,
            is_starred: isStarred,
            labels: labels,
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com",
            marked_read_at: isRead ? "2024-01-02T00:00:00Z" : nil
        )
    }
    
    func createTestEmailAccount(id: Int) -> EmailAccount {
        return EmailAccount(
            id: id,
            email: "test\(id)@example.com",
            is_active: true,
            last_sync: "2024-01-01T00:00:00Z",
            created_at: "2024-01-01T00:00:00Z",
            email_count: 10
        )
    }
    
    // MARK: - Snapshot Creation Tests
    
    @Test("Load cached snapshot returns nil when no cache exists")
    func testLoadCachedSnapshotReturnsNil() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot == nil)
    }
    
    @Test("Load cached snapshot returns existing snapshot")
    func testLoadCachedSnapshot() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Create and save a snapshot
        let accounts = [createTestEmailAccount(id: 1)]
        let emails = [createTestEmailListItem(id: 1)]
        
        await cache.saveSnapshot(
            accounts: accounts,
            emails: emails,
            allEmails: emails,
            starredEmails: [],
            labels: []
        )
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.accounts.count == 1)
        #expect(snapshot?.emails.count == 1)
        #expect(snapshot?.emails.first?.id == 1)
    }
    
    // MARK: - Health Status Tracking Tests
    
    @Test("Get account health returns empty array initially")
    func testGetAccountHealthInitiallyEmpty() async {
        let manager = DashboardDataManager.shared
        
        let health = await manager.getAccountHealth()
        
        #expect(health.isEmpty)
    }
    
    @Test("Get account health for specific account returns nil when not found")
    func testGetAccountHealthForNonExistentAccount() async {
        let manager = DashboardDataManager.shared
        
        let health = await manager.getAccountHealth(email: "nonexistent@example.com")
        
        #expect(health == nil)
    }
    
    // MARK: - Email Status Update Tests
    
    @Test("Mark email as read removes from unread list")
    func testMarkEmailAsRead() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache and create initial snapshot
        await cache.clear()
        
        let unreadEmail = createTestEmailListItem(id: 1, isRead: false)
        let readEmail = createTestEmailListItem(id: 2, isRead: true)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [unreadEmail, readEmail], // Both in unread list initially
            allEmails: [unreadEmail, readEmail],
            starredEmails: [],
            labels: []
        )
        
        // Mark email 1 as read
        await manager.markEmailAsRead(emailId: 1)
        
        // Load updated snapshot
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.emails.isEmpty == true) // Read emails are no longer in unread list
        
        // Email 1 should still be in allEmails but marked as read
        let email1 = snapshot?.allEmails.first { $0.id == 1 }
        #expect(email1 != nil)
        #expect(email1?.is_read == true)
    }
    
    @Test("Mark email as unread adds to unread list")
    func testMarkEmailAsUnread() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache and create initial snapshot
        await cache.clear()
        
        let readEmail = createTestEmailListItem(id: 1, isRead: true)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [], // Empty unread list
            allEmails: [readEmail],
            starredEmails: [],
            labels: []
        )
        
        // Mark email 1 as unread
        await manager.markEmailAsUnread(emailId: 1, accountId: nil)
        
        // Load updated snapshot
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.emails.count == 1) // Email 1 should be in unread list
        #expect(snapshot?.emails.first?.id == 1)
        #expect(snapshot?.emails.first?.is_read == false)
        
        // Email 1 should be updated in allEmails
        let email1 = snapshot?.allEmails.first { $0.id == 1 }
        #expect(email1 != nil)
        #expect(email1?.is_read == false)
    }
    
    @Test("Mark non-existent email as read does nothing")
    func testMarkNonExistentEmailAsRead() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        // Try to mark non-existent email
        await manager.markEmailAsRead(emailId: 999)
        
        // Should not crash, snapshot should still be nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    @Test("Mark non-existent email as unread does nothing")
    func testMarkNonExistentEmailAsUnread() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        // Try to mark non-existent email
        await manager.markEmailAsUnread(emailId: 999, accountId: nil)
        
        // Should not crash, snapshot should still be nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    // MARK: - Starred Status Update Tests
    
    @Test("Update email starred status adds to starred list")
    func testUpdateEmailStarredStatusAdds() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache and create initial snapshot
        await cache.clear()
        
        let unstarredEmail = createTestEmailListItem(id: 1, isStarred: false)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [unstarredEmail],
            allEmails: [unstarredEmail],
            starredEmails: [],
            labels: []
        )
        
        // Star the email
        await manager.updateEmailStarred(emailId: 1, isStarred: true)
        
        // Load updated snapshot
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.starredEmails.count == 1)
        #expect(snapshot?.starredEmails.first?.id == 1)
        #expect(snapshot?.starredEmails.first?.is_starred == true)
        
        // Email should be updated in allEmails and emails
        let email1 = snapshot?.allEmails.first { $0.id == 1 }
        #expect(email1?.is_starred == true)
        
        let email1InList = snapshot?.emails.first { $0.id == 1 }
        #expect(email1InList?.is_starred == true)
    }
    
    @Test("Update email starred status removes from starred list")
    func testUpdateEmailStarredStatusRemoves() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache and create initial snapshot
        await cache.clear()
        
        let starredEmail = createTestEmailListItem(id: 1, isStarred: true)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [starredEmail],
            allEmails: [starredEmail],
            starredEmails: [starredEmail],
            labels: []
        )
        
        // Unstar the email
        await manager.updateEmailStarred(emailId: 1, isStarred: false)
        
        // Load updated snapshot
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.starredEmails.isEmpty == true)
        
        // Email should be updated in allEmails and emails
        let email1 = snapshot?.allEmails.first { $0.id == 1 }
        #expect(email1?.is_starred == false)
        
        let email1InList = snapshot?.emails.first { $0.id == 1 }
        #expect(email1InList?.is_starred == false)
    }
    
    @Test("Update non-existent email starred status does nothing")
    func testUpdateNonExistentEmailStarredStatus() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        // Try to update non-existent email
        await manager.updateEmailStarred(emailId: 999, isStarred: true)
        
        // Should not crash, snapshot should still be nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    // MARK: - Multi-Account Handling Tests
    
    @Test("Snapshot handles multiple accounts")
    func testSnapshotHandlesMultipleAccounts() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        let account1 = createTestEmailAccount(id: 1)
        let account2 = createTestEmailAccount(id: 2)
        
        let email1 = createTestEmailListItem(id: 1)
        var email2 = createTestEmailListItem(id: 2)
        email2 = EmailListItem(
            id: email2.id,
            gmail_id: email2.gmail_id,
            subject: email2.subject,
            sender: email2.sender,
            sender_name: email2.sender_name,
            snippet: email2.snippet,
            is_read: email2.is_read,
            is_starred: email2.is_starred,
            labels: email2.labels,
            received_at: email2.received_at,
            account_email: "test2@example.com", // Different account
            marked_read_at: email2.marked_read_at
        )
        
        await cache.saveSnapshot(
            accounts: [account1, account2],
            emails: [email1, email2],
            allEmails: [email1, email2],
            starredEmails: [],
            labels: []
        )
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.accounts.count == 2)
        #expect(snapshot?.emails.count == 2)
    }
    
    // MARK: - Edge Cases
    
    @Test("Mark email as read when already read does nothing")
    func testMarkEmailAsReadWhenAlreadyRead() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        let readEmail = createTestEmailListItem(id: 1, isRead: true)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [],
            allEmails: [readEmail],
            starredEmails: [],
            labels: []
        )
        
        let before = await manager.loadCachedSnapshot()
        
        // Mark as read again (no-op)
        await manager.markEmailAsRead(emailId: 1)
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.emails.isEmpty == true) // Should still be empty
        #expect(snapshot?.allEmails.first?.is_read == true)
        #expect(snapshot?.timestamp == before?.timestamp)
    }
    
    @Test("Update starred status when already starred does nothing")
    func testUpdateStarredStatusWhenAlreadyStarred() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        let starredEmail = createTestEmailListItem(id: 1, isStarred: true)
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [starredEmail],
            allEmails: [starredEmail],
            starredEmails: [starredEmail],
            labels: []
        )
        
        let before = await manager.loadCachedSnapshot()
        
        // Star again (no-op)
        await manager.updateEmailStarred(emailId: 1, isStarred: true)
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.starredEmails.count == 1) // Should still have one
        #expect(snapshot?.starredEmails.first?.is_starred == true)
        #expect(snapshot?.timestamp == before?.timestamp)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Mark email as read handles missing snapshot gracefully")
    func testMarkEmailAsReadHandlesMissingSnapshot() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache to ensure no snapshot
        await cache.clear()
        
        // Try to mark non-existent email - should not crash
        await manager.markEmailAsRead(emailId: 999)
        
        // Verify snapshot is still nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    @Test("Mark email as unread handles missing snapshot gracefully")
    func testMarkEmailAsUnreadHandlesMissingSnapshot() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        // Try to mark non-existent email - should not crash
        await manager.markEmailAsUnread(emailId: 999, accountId: nil)
        
        // Verify snapshot is still nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    @Test("Update starred status handles missing snapshot gracefully")
    func testUpdateStarredStatusHandlesMissingSnapshot() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear cache
        await cache.clear()
        
        // Try to update non-existent email - should not crash
        await manager.updateEmailStarred(emailId: 999, isStarred: true)
        
        // Verify snapshot is still nil
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot == nil)
    }
    
    @Test("Mark email as read handles email not in snapshot")
    func testMarkEmailAsReadHandlesEmailNotInSnapshot() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear and create snapshot with one email
        await cache.clear()
        
        let email1 = createTestEmailListItem(id: 1)
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [email1],
            allEmails: [email1],
            starredEmails: [],
            labels: []
        )
        
        // Try to mark different email as read
        await manager.markEmailAsRead(emailId: 999)
        
        // Verify original email is still there
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot != nil)
        #expect(snapshot?.emails.count == 1)
        #expect(snapshot?.emails.first?.id == 1)
    }
    
    @Test("Update starred status handles email not in allEmails")
    func testUpdateStarredStatusHandlesEmailNotInAllEmails() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        // Clear and create snapshot
        await cache.clear()
        
        let email1 = createTestEmailListItem(id: 1)
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [email1],
            allEmails: [email1],
            starredEmails: [],
            labels: []
        )
        
        // Try to star non-existent email
        await manager.updateEmailStarred(emailId: 999, isStarred: true)
        
        // Verify original state unchanged
        let snapshot = await manager.loadCachedSnapshot()
        #expect(snapshot != nil)
        #expect(snapshot?.starredEmails.isEmpty == true)
    }
    
    @Test("Snapshot handles empty accounts array")
    func testSnapshotHandlesEmptyAccounts() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        await cache.clear()
        
        let email = createTestEmailListItem(id: 1)
        await cache.saveSnapshot(
            accounts: [], // Empty accounts
            emails: [email],
            allEmails: [email],
            starredEmails: [],
            labels: []
        )
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.accounts.isEmpty == true)
        #expect(snapshot?.emails.count == 1)
    }
    
    @Test("Snapshot handles empty emails array")
    func testSnapshotHandlesEmptyEmails() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        await cache.clear()
        
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [], // Empty emails
            allEmails: [],
            starredEmails: [],
            labels: []
        )
        
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.emails.isEmpty == true)
        #expect(snapshot?.allEmails.isEmpty == true)
    }
    
    @Test("Multiple status updates maintain consistency")
    func testMultipleStatusUpdatesMaintainConsistency() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        await cache.clear()
        
        let email = createTestEmailListItem(id: 1, isRead: false, isStarred: false)
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [email],
            allEmails: [email],
            starredEmails: [],
            labels: []
        )
        
        // Mark as read
        await manager.markEmailAsRead(emailId: 1)
        
        // Star it
        await manager.updateEmailStarred(emailId: 1, isStarred: true)
        
        // Unstar it
        await manager.updateEmailStarred(emailId: 1, isStarred: false)
        
        // Mark as unread
        await manager.markEmailAsUnread(emailId: 1, accountId: nil)
        
        // Verify final state
        let snapshot = await manager.loadCachedSnapshot()
        
        #expect(snapshot != nil)
        #expect(snapshot?.emails.count == 1) // Should be back in unread list
        #expect(snapshot?.emails.first?.is_read == false)
        #expect(snapshot?.emails.first?.is_starred == false)
        #expect(snapshot?.starredEmails.isEmpty == true)
    }
    
    @Test("Label counters are recomputed after read and star mutations")
    func testLabelCountersAreRecomputed() async {
        let manager = DashboardDataManager.shared
        let cache = DashboardCache.shared
        
        await cache.clear()
        
        let unreadStarred = createTestEmailListItem(id: 1, isRead: false, isStarred: true)
        let unread = createTestEmailListItem(id: 2, isRead: false, isStarred: false)
        await cache.saveSnapshot(
            accounts: [createTestEmailAccount(id: 1)],
            emails: [unreadStarred, unread],
            allEmails: [unreadStarred, unread],
            starredEmails: [unreadStarred],
            labels: []
        )
        
        await manager.markEmailAsRead(emailId: 1)
        
        let snapshotAfterRead = await manager.loadCachedSnapshot()
        #expect(snapshotAfterRead?.labels.first(where: { $0.id == "UNREAD" })?.unread_count == 1)
        #expect(snapshotAfterRead?.labels.first(where: { $0.id == "STARRED" }) == nil)
        
        await manager.updateEmailStarred(emailId: 2, isStarred: true)
        let snapshotAfterStar = await manager.loadCachedSnapshot()
        
        #expect(snapshotAfterStar?.labels.first(where: { $0.id == "UNREAD" })?.unread_count == 1)
        #expect(snapshotAfterStar?.labels.first(where: { $0.id == "STARRED" })?.unread_count == 1)
    }
}

