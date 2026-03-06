//
//  DashboardCacheTests.swift
//  emptyMyInboxTests
//
//  Unit tests for DashboardCache.swift
//

import Foundation
import Testing
@testable import emptyMyInbox

struct DashboardCacheTests {
    
    func createTestEmailAccount(id: Int = 1) -> EmailAccount {
        return EmailAccount(
            id: id,
            email: "test\(id)@example.com",
            is_active: true,
            last_sync: "2024-01-01T00:00:00Z",
            created_at: "2024-01-01T00:00:00Z",
            email_count: 10
        )
    }
    
    func createTestEmailListItem(id: Int = 1, isRead: Bool = false, isStarred: Bool = false) -> EmailListItem {
        return EmailListItem(
            id: id,
            gmail_id: "msg\(id)",
            subject: "Test Email \(id)",
            sender: "sender\(id)@example.com",
            sender_name: "Sender \(id)",
            snippet: "Test snippet \(id)",
            is_read: isRead,
            is_starred: isStarred,
            labels: isRead ? ["INBOX"] : ["INBOX", "UNREAD"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com",
            marked_read_at: nil
        )
    }
    
    func createTestLabel(id: String = "INBOX") -> Label {
        return Label(
            id: id,
            name: id.capitalized,
            unread_count: 5
        )
    }
    
    // MARK: - Save and Load Tests
    
    @Test("Save and load snapshot")
    func testSaveAndLoadSnapshot() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let accounts = [createTestEmailAccount(id: 1)]
        let emails = [createTestEmailListItem(id: 1)]
        let labels = [createTestLabel(id: "INBOX")]
        
        await cache.saveSnapshot(
            accounts: accounts,
            emails: emails,
            allEmails: emails,
            starredEmails: [],
            labels: labels
        )
        
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded != nil)
        #expect(loaded?.accounts.count == 1)
        #expect(loaded?.accounts.first?.id == 1)
        #expect(loaded?.emails.count == 1)
        #expect(loaded?.emails.first?.id == 1)
        #expect(loaded?.allEmails.count == 1)
        #expect(loaded?.starredEmails.isEmpty == true)
        #expect(loaded?.labels.count == 1)
        #expect(loaded?.labels.first?.id == "INBOX")
    }
    
    @Test("Save snapshot with all fields populated")
    func testSaveSnapshotWithAllFields() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let accounts = [
            createTestEmailAccount(id: 1),
            createTestEmailAccount(id: 2)
        ]
        let emails = [
            createTestEmailListItem(id: 1),
            createTestEmailListItem(id: 2)
        ]
        let starredEmails = [createTestEmailListItem(id: 3, isStarred: true)]
        let labels = [
            createTestLabel(id: "INBOX"),
            createTestLabel(id: "STARRED")
        ]
        
        await cache.saveSnapshot(
            accounts: accounts,
            emails: emails,
            allEmails: emails + starredEmails,
            starredEmails: starredEmails,
            labels: labels
        )
        
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded != nil)
        #expect(loaded?.accounts.count == 2)
        #expect(loaded?.emails.count == 2)
        #expect(loaded?.allEmails.count == 3)
        #expect(loaded?.starredEmails.count == 1)
        #expect(loaded?.starredEmails.first?.id == 3)
        #expect(loaded?.labels.count == 2)
    }
    
    @Test("Load snapshot returns nil when cache is empty")
    func testLoadSnapshotReturnsNilWhenEmpty() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded == nil)
    }
    
    @Test("Save snapshot with empty arrays")
    func testSaveSnapshotWithEmptyArrays() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        await cache.saveSnapshot(
            accounts: [],
            emails: [],
            allEmails: [],
            starredEmails: [],
            labels: []
        )
        
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded != nil)
        #expect(loaded?.accounts.isEmpty == true)
        #expect(loaded?.emails.isEmpty == true)
        #expect(loaded?.allEmails.isEmpty == true)
        #expect(loaded?.starredEmails.isEmpty == true)
        #expect(loaded?.labels.isEmpty == true)
    }
    
    // MARK: - Clear Tests
    
    @Test("Clear removes saved snapshot")
    func testClearRemovesSnapshot() async {
        let cache = DashboardCache.shared
        
        // Save a snapshot first
        let accounts = [createTestEmailAccount(id: 1)]
        let emails = [createTestEmailListItem(id: 1)]
        await cache.saveSnapshot(
            accounts: accounts,
            emails: emails,
            allEmails: emails,
            starredEmails: [],
            labels: []
        )
        
        // Verify it's saved
        let beforeClear = await cache.loadSnapshot()
        #expect(beforeClear != nil)
        
        // Clear it
        await cache.clear()
        
        // Verify it's gone
        let afterClear = await cache.loadSnapshot()
        #expect(afterClear == nil)
    }
    
    @Test("Clear on empty cache does not crash")
    func testClearOnEmptyCache() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        // Clear again should not crash
        await cache.clear()
        
        let loaded = await cache.loadSnapshot()
        #expect(loaded == nil)
    }
    
    // MARK: - Snapshot Timestamp Tests
    
    @Test("Snapshot includes timestamp")
    func testSnapshotIncludesTimestamp() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let beforeSave = Date()
        let accounts = [createTestEmailAccount(id: 1)]
        let emails = [createTestEmailListItem(id: 1)]
        await cache.saveSnapshot(
            accounts: accounts,
            emails: emails,
            allEmails: emails,
            starredEmails: [],
            labels: []
        )
        let afterSave = Date()
        
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded != nil)
        if let timestamp = loaded?.timestamp {
            #expect(timestamp >= beforeSave)
            #expect(timestamp <= afterSave)
        } else {
            #expect(Bool(false))
        }
    }
    
    // MARK: - Multiple Save Tests
    
    @Test("Save snapshot overwrites previous snapshot")
    func testSaveSnapshotOverwritesPrevious() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        // Save first snapshot
        let accounts1 = [createTestEmailAccount(id: 1)]
        let emails1 = [createTestEmailListItem(id: 1)]
        await cache.saveSnapshot(
            accounts: accounts1,
            emails: emails1,
            allEmails: emails1,
            starredEmails: [],
            labels: []
        )
        
        // Save second snapshot
        let accounts2 = [createTestEmailAccount(id: 2)]
        let emails2 = [createTestEmailListItem(id: 2)]
        await cache.saveSnapshot(
            accounts: accounts2,
            emails: emails2,
            allEmails: emails2,
            starredEmails: [],
            labels: []
        )
        
        // Verify only second snapshot exists
        let loaded = await cache.loadSnapshot()
        
        #expect(loaded != nil)
        #expect(loaded?.accounts.count == 1)
        #expect(loaded?.accounts.first?.id == 2)
        #expect(loaded?.emails.count == 1)
        #expect(loaded?.emails.first?.id == 2)
    }
    
    // MARK: - Data Integrity Tests
    
    @Test("Snapshot preserves all email fields")
    func testSnapshotPreservesEmailFields() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let email = EmailListItem(
            id: 123,
            gmail_id: "gmail_msg_456",
            subject: "Test Subject",
            sender: "sender@example.com",
            sender_name: "Sender Name",
            snippet: "Test snippet",
            is_read: true,
            is_starred: true,
            labels: ["INBOX", "STARRED"],
            received_at: "2024-01-15T12:30:00Z",
            account_email: "account@example.com",
            marked_read_at: "2024-01-16T10:00:00Z"
        )
        
        await cache.saveSnapshot(
            accounts: [],
            emails: [email],
            allEmails: [email],
            starredEmails: [email],
            labels: []
        )
        
        let loaded = await cache.loadSnapshot()
        let loadedEmail = loaded?.emails.first
        
        #expect(loadedEmail != nil)
        #expect(loadedEmail?.id == 123)
        #expect(loadedEmail?.gmail_id == "gmail_msg_456")
        #expect(loadedEmail?.subject == "Test Subject")
        #expect(loadedEmail?.sender == "sender@example.com")
        #expect(loadedEmail?.sender_name == "Sender Name")
        #expect(loadedEmail?.snippet == "Test snippet")
        #expect(loadedEmail?.is_read == true)
        #expect(loadedEmail?.is_starred == true)
        #expect(loadedEmail?.labels == ["INBOX", "STARRED"])
        #expect(loadedEmail?.received_at == "2024-01-15T12:30:00Z")
        #expect(loadedEmail?.account_email == "account@example.com")
        #expect(loadedEmail?.marked_read_at == "2024-01-16T10:00:00Z")
    }
    
    @Test("Snapshot preserves all account fields")
    func testSnapshotPreservesAccountFields() async {
        let cache = DashboardCache.shared
        await cache.clear()
        
        let account = EmailAccount(
            id: 789,
            email: "account@example.com",
            is_active: true,
            last_sync: "2024-01-20T15:00:00Z",
            created_at: "2024-01-01T00:00:00Z",
            email_count: 42
        )
        
        await cache.saveSnapshot(
            accounts: [account],
            emails: [],
            allEmails: [],
            starredEmails: [],
            labels: []
        )
        
        let loaded = await cache.loadSnapshot()
        let loadedAccount = loaded?.accounts.first
        
        #expect(loadedAccount != nil)
        #expect(loadedAccount?.id == 789)
        #expect(loadedAccount?.email == "account@example.com")
        #expect(loadedAccount?.is_active == true)
        #expect(loadedAccount?.last_sync == "2024-01-20T15:00:00Z")
        #expect(loadedAccount?.created_at == "2024-01-01T00:00:00Z")
        #expect(loadedAccount?.email_count == 42)
    }
}

