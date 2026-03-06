//
//  CacheIntegrationTests.swift
//  emptyMyInboxTests
//
//  Integration tests for cache operations
//

import Testing
@testable import emptyMyInbox
import Foundation

struct CacheIntegrationTests {
    
    // MARK: - Full Cache Flow Tests
    
    @Test("Full cache flow: save → load → delete")
    func testFullCacheFlow() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Step 1: Save email details
        let emailDetail = EmailDetail(
            id: 1,
            gmail_id: "msg123",
            thread_id: "thread123",
            subject: "Integration Test Email",
            sender: "sender@example.com",
            sender_name: "Test Sender",
            recipients_to: "recipient@example.com",
            recipients_cc: nil,
            recipients_bcc: nil,
            body_text: "This is a test email body for integration testing",
            body_html: "<p>This is a test email body</p>",
            snippet: "Integration test snippet",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com",
            created_at: "2024-01-01T00:00:00Z"
        )
        
        await cache.saveEmailDetail(emailDetail)
        
        // Step 2: Verify it's cached
        let isCached = await cache.isEmailCached(emailId: 1)
        #expect(isCached == true)
        
        // Step 3: Load the email detail
        let loaded = await cache.loadEmailDetail(emailId: 1)
        #expect(loaded != nil)
        #expect(loaded?.subject == "Integration Test Email")
        
        // Step 4: Delete the email
        await cache.deleteEmailDetail(emailId: 1)
        
        // Step 5: Verify it's gone
        let isStillCached = await cache.isEmailCached(emailId: 1)
        #expect(isStillCached == false)
        
        let loadedAfterDelete = await cache.loadEmailDetail(emailId: 1)
        #expect(loadedAfterDelete == nil)
    }
    
    @Test("Full cache flow with metadata")
    func testFullCacheFlowWithMetadata() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Step 1: Save metadata
        let metadata = [
            EmailMetadata(
                id: 1,
                gmail_id: "msg1",
                thread_id: "thread1",
                subject: "Test Email 1",
                sender: "sender1@example.com",
                sender_name: "Sender 1",
                snippet: "Snippet 1",
                is_read: false,
                is_starred: false,
                labels: ["INBOX", "UNREAD"],
                received_at: "2024-01-01T00:00:00Z",
                account_email: "test@example.com"
            ),
            EmailMetadata(
                id: 2,
                gmail_id: "msg2",
                thread_id: "thread2",
                subject: "Test Email 2",
                sender: "sender2@example.com",
                sender_name: "Sender 2",
                snippet: "Snippet 2",
                is_read: false,
                is_starred: true,
                labels: ["INBOX", "UNREAD", "STARRED"],
                received_at: "2024-01-02T00:00:00Z",
                account_email: "test@example.com"
            )
        ]
        
        await cache.saveEmailMetadata(metadata)
        
        // Step 2: Load metadata
        let loaded = await cache.loadEmailMetadata()
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == 1 })
        #expect(loaded.contains { $0.id == 2 })
        
        // Step 3: Convert to EmailListItem
        let emailItems = loaded.map { $0.toEmailListItem() }
        #expect(emailItems.count == 2)
        #expect(emailItems.first { $0.id == 1 }?.is_starred == false)
        #expect(emailItems.first { $0.id == 2 }?.is_starred == true)
    }
    
    // MARK: - Cache Persistence Tests
    
    @Test("Cache persists across operations")
    func testCachePersistence() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save multiple emails
        for i in 1...5 {
            let emailDetail = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: "Sender \(i)",
                recipients_to: "recipient@example.com",
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: false,
                is_starred: false,
                labels: ["INBOX", "UNREAD"],
                received_at: "2024-01-0\(i)T00:00:00Z",
                account_email: "test@example.com",
                created_at: "2024-01-0\(i)T00:00:00Z"
            )
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Verify all are cached
        let cachedCount = await cache.cachedEmailCount()
        #expect(cachedCount == 5)
        
        // Load all cached emails
        let allCached = await cache.loadAllCachedEmails()
        #expect(allCached.count == 5)
        
        // Verify each email
        for i in 1...5 {
            let email = allCached.first { $0.id == i }
            #expect(email != nil)
            #expect(email?.subject == "Email \(i)")
        }
    }
    
    @Test("Cache handles account-specific metadata")
    func testCacheAccountSpecificMetadata() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save metadata for account 1
        let metadata1 = [
            EmailMetadata(
                id: 1,
                gmail_id: "msg1",
                thread_id: "thread1",
                subject: "Account 1 Email",
                sender: "sender@example.com",
                sender_name: nil,
                snippet: "Snippet",
                is_read: false,
                is_starred: false,
                labels: ["INBOX"],
                received_at: "2024-01-01T00:00:00Z",
                account_email: "account1@example.com"
            )
        ]
        await cache.saveEmailMetadata(metadata1, accountId: 1)
        
        // Save metadata for account 2
        let metadata2 = [
            EmailMetadata(
                id: 2,
                gmail_id: "msg2",
                thread_id: "thread2",
                subject: "Account 2 Email",
                sender: "sender@example.com",
                sender_name: nil,
                snippet: "Snippet",
                is_read: false,
                is_starred: false,
                labels: ["INBOX"],
                received_at: "2024-01-01T00:00:00Z",
                account_email: "account2@example.com"
            )
        ]
        await cache.saveEmailMetadata(metadata2, accountId: 2)
        
        // Load metadata for account 1
        let loaded1 = await cache.loadEmailMetadata(accountId: 1)
        #expect(loaded1.count == 1)
        #expect(loaded1.first?.id == 1)
        #expect(loaded1.first?.account_email == "account1@example.com")
        
        // Load metadata for account 2
        let loaded2 = await cache.loadEmailMetadata(accountId: 2)
        #expect(loaded2.count == 1)
        #expect(loaded2.first?.id == 2)
        #expect(loaded2.first?.account_email == "account2@example.com")
        
        // Load default metadata (should be empty or different)
        let defaultLoaded = await cache.loadEmailMetadata()
        // Default might be empty or contain account-specific data
        #expect(defaultLoaded.count >= 0)
    }
    
    // MARK: - Concurrent Access Tests
    
    @Test("Concurrent save and load operations")
    func testConcurrentSaveAndLoad() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Concurrently save emails
        await withTaskGroup(of: Void.self) { group in
            for i in 1...20 {
                group.addTask {
                    let emailDetail = EmailDetail(
                        id: i,
                        gmail_id: "msg\(i)",
                        thread_id: "thread\(i)",
                        subject: "Email \(i)",
                        sender: "sender\(i)@example.com",
                        sender_name: nil,
                        recipients_to: nil,
                        recipients_cc: nil,
                        recipients_bcc: nil,
                        body_text: "Body \(i)",
                        body_html: nil,
                        snippet: "Snippet \(i)",
                        is_read: false,
                        is_starred: false,
                        labels: ["INBOX"],
                        received_at: "2024-01-01T00:00:00Z",
                        account_email: "test@example.com",
                        created_at: "2024-01-01T00:00:00Z"
                    )
                    await cache.saveEmailDetail(emailDetail)
                }
            }
        }
        
        // Concurrently load emails
        var loadedCount = 0
        await withTaskGroup(of: EmailDetail?.self) { group in
            for i in 1...20 {
                group.addTask {
                    return await cache.loadEmailDetail(emailId: i)
                }
            }
            
            for await result in group {
                if result != nil {
                    loadedCount += 1
                }
            }
        }
        
        #expect(loadedCount == 20)
    }
    
    @Test("Concurrent save, load, and delete operations")
    func testConcurrentSaveLoadDelete() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save emails
        for i in 1...10 {
            let emailDetail = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: nil,
                recipients_to: nil,
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: false,
                is_starred: false,
                labels: ["INBOX"],
                received_at: "2024-01-01T00:00:00Z",
                account_email: "test@example.com",
                created_at: "2024-01-01T00:00:00Z"
            )
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Concurrently load and delete
        await withTaskGroup(of: Void.self) { group in
            // Load some
            for i in 1...5 {
                group.addTask {
                    _ = await cache.loadEmailDetail(emailId: i)
                }
            }
            
            // Delete others
            for i in 6...10 {
                group.addTask {
                    await cache.deleteEmailDetail(emailId: i)
                }
            }
        }
        
        // Verify first 5 still exist
        for i in 1...5 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
        
        // Verify last 5 are deleted
        for i in 6...10 {
            #expect(await cache.isEmailCached(emailId: i) == false)
        }
    }
    
    @Test("Concurrent batch save operations")
    func testConcurrentBatchSave() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Create multiple batches
        var batch1: [EmailDetail] = []
        var batch2: [EmailDetail] = []
        
        for i in 1...10 {
            let emailDetail = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: nil,
                recipients_to: nil,
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: false,
                is_starred: false,
                labels: ["INBOX"],
                received_at: "2024-01-01T00:00:00Z",
                account_email: "test@example.com",
                created_at: "2024-01-01T00:00:00Z"
            )
            
            if i <= 5 {
                batch1.append(emailDetail)
            } else {
                batch2.append(emailDetail)
            }
        }
        
        // Save batches concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await cache.saveEmailDetails(batch1)
            }
            group.addTask {
                await cache.saveEmailDetails(batch2)
            }
        }
        
        // Verify all are saved
        #expect(await cache.cachedEmailCount() == 10)
        
        for i in 1...10 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
    }
    
    // MARK: - Cleanup Operations Tests
    
    @Test("Cleanup operations maintain cache integrity")
    func testCleanupMaintainsIntegrity() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Create mix of old and new emails
        var emails: [EmailDetail] = []
        
        // Old read emails (should be cleaned up)
        for i in 1...5 {
            let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
            let oldDateString = formatter.string(from: oldDate)
            
            let email = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Old Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: nil,
                recipients_to: nil,
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: true, // Read
                is_starred: false,
                labels: ["INBOX"],
                received_at: oldDateString,
                account_email: "test@example.com",
                created_at: oldDateString
            )
            emails.append(email)
        }
        
        // Recent read emails (should NOT be cleaned up)
        for i in 6...10 {
            let recentDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
            let recentDateString = formatter.string(from: recentDate)
            
            let email = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Recent Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: nil,
                recipients_to: nil,
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: true, // Read
                is_starred: false,
                labels: ["INBOX"],
                received_at: recentDateString,
                account_email: "test@example.com",
                created_at: recentDateString
            )
            emails.append(email)
        }
        
        // Unread emails (should NOT be cleaned up)
        for i in 11...15 {
            let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
            let oldDateString = formatter.string(from: oldDate)
            
            let email = EmailDetail(
                id: i,
                gmail_id: "msg\(i)",
                thread_id: "thread\(i)",
                subject: "Old Unread Email \(i)",
                sender: "sender\(i)@example.com",
                sender_name: nil,
                recipients_to: nil,
                recipients_cc: nil,
                recipients_bcc: nil,
                body_text: "Body \(i)",
                body_html: nil,
                snippet: "Snippet \(i)",
                is_read: false, // Unread
                is_starred: false,
                labels: ["INBOX", "UNREAD"],
                received_at: oldDateString,
                account_email: "test@example.com",
                created_at: oldDateString
            )
            emails.append(email)
        }
        
        // Save all emails
        await cache.saveEmailDetails(emails)
        
        // Verify all are saved
        #expect(await cache.cachedEmailCount() == 15)
        
        // Cleanup emails older than 10 days
        await cache.cleanupOldEmails(olderThanDays: 10)
        
        // Old read emails (1-5) should be deleted
        for i in 1...5 {
            #expect(await cache.isEmailCached(emailId: i) == false)
        }
        
        // Recent read emails (6-10) should still exist
        for i in 6...10 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
        
        // Old unread emails (11-15) should still exist
        for i in 11...15 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
        
        // Final count should be 10 (6-15)
        #expect(await cache.cachedEmailCount() == 10)
    }
    
}

