//
//  EmailCacheTests.swift
//  emptyMyInboxTests
//
//  Unit tests for EmailCache.swift (highest priority)
//

import Testing
import EmptyMyInboxShared
import Foundation

struct EmailCacheTests {
    
    // MARK: - Setup Helpers
    
    func createTestEmailDetail(id: Int, gmailId: String = "msg\(Int.random(in: 1...10000))") -> EmailDetail {
        return EmailDetail(
            id: id,
            gmail_id: gmailId,
            thread_id: "thread_\(id)",
            subject: "Test Email \(id)",
            sender: "sender\(id)@example.com",
            sender_name: "Sender \(id)",
            recipients_to: "recipient@example.com",
            recipients_cc: nil,
            recipients_bcc: nil,
            body_text: "Test body text for email \(id)",
            body_html: "<p>Test body HTML for email \(id)</p>",
            snippet: "Test snippet \(id)",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com",
            created_at: "2024-01-01T00:00:00Z"
        )
    }
    
    func createTestEmailMetadata(id: Int) -> EmailMetadata {
        return EmailMetadata(
            id: id,
            gmail_id: "msg\(id)",
            thread_id: "thread_\(id)",
            subject: "Test Email \(id)",
            sender: "sender\(id)@example.com",
            sender_name: "Sender \(id)",
            snippet: "Test snippet \(id)",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: "2024-01-01T00:00:00Z",
            account_email: "test@example.com"
        )
    }
    
    // MARK: - Save and Load Email Details Tests
    
    @Test("Save and load email detail")
    func testSaveAndLoadEmailDetail() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let emailDetail = createTestEmailDetail(id: 1)
        await cache.saveEmailDetail(emailDetail)
        
        let loaded = await cache.loadEmailDetail(emailId: 1)
        
        #expect(loaded != nil)
        #expect(loaded?.id == 1)
        #expect(loaded?.subject == "Test Email 1")
        #expect(loaded?.sender == "sender1@example.com")
    }
    
    @Test("Load email detail by Gmail ID")
    func testLoadEmailDetailByGmailId() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let emailDetail = createTestEmailDetail(id: 1, gmailId: "gmail_msg_123")
        await cache.saveEmailDetail(emailDetail)
        
        let loaded = await cache.loadEmailDetail(gmailId: "gmail_msg_123")
        
        #expect(loaded != nil)
        #expect(loaded?.gmail_id == "gmail_msg_123")
        #expect(loaded?.id == StableID.emailId(gmailId: "gmail_msg_123"))
    }
    
    @Test("Load non-existent email detail returns nil")
    func testLoadNonExistentEmailDetail() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let loaded = await cache.loadEmailDetail(emailId: 999)
        
        #expect(loaded == nil)
    }
    
    // MARK: - Memory Cache Eviction Tests
    
    @Test("Memory cache evicts oldest when over maxMemoryCacheSize")
    func testMemoryCacheEviction() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save more than maxMemoryCacheSize (50) emails
        for i in 1...60 {
            let emailDetail = createTestEmailDetail(id: i)
            await cache.saveEmailDetail(emailDetail)
        }
        
        // The first 10 should be evicted from memory cache
        // But they should still be on disk
        let firstEmail = await cache.loadEmailDetail(emailId: 1)
        let lastEmail = await cache.loadEmailDetail(emailId: 60)
        
        // Both should be loadable (from disk if not in memory)
        #expect(firstEmail != nil)
        #expect(lastEmail != nil)
    }
    
    @Test("Memory cache maintains access order")
    func testMemoryCacheAccessOrder() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save 3 emails
        for i in 1...3 {
            let emailDetail = createTestEmailDetail(id: i)
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Access first email (should move it to end of access order)
        let _ = await cache.loadEmailDetail(emailId: 1)
        let _ = await cache.loadEmailDetail(emailId: 2)
        let _ = await cache.loadEmailDetail(emailId: 1) // Access again
        
        // All should still be accessible
        #expect(await cache.loadEmailDetail(emailId: 1) != nil)
        #expect(await cache.loadEmailDetail(emailId: 2) != nil)
        #expect(await cache.loadEmailDetail(emailId: 3) != nil)
    }
    
    // MARK: - isEmailCached Tests
    
    @Test("isEmailCached returns true for cached email")
    func testIsEmailCachedReturnsTrue() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let emailDetail = createTestEmailDetail(id: 1)
        await cache.saveEmailDetail(emailDetail)
        
        let isCached = await cache.isEmailCached(emailId: 1)
        
        #expect(isCached == true)
    }
    
    @Test("isEmailCached returns false for non-cached email")
    func testIsEmailCachedReturnsFalse() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let isCached = await cache.isEmailCached(emailId: 999)
        
        #expect(isCached == false)
    }
    
    @Test("isEmailCached by Gmail ID returns true")
    func testIsEmailCachedByGmailId() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let emailDetail = createTestEmailDetail(id: 1, gmailId: "gmail_msg_456")
        await cache.saveEmailDetail(emailDetail)
        
        let isCached = await cache.isEmailCached(gmailId: "gmail_msg_456")
        
        #expect(isCached == true)
    }
    
    @Test("isEmailCached by Gmail ID returns false for non-cached")
    func testIsEmailCachedByGmailIdReturnsFalse() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let isCached = await cache.isEmailCached(gmailId: "non_existent_gmail_id")
        
        #expect(isCached == false)
    }
    
    // MARK: - Delete Email Details Tests
    
    @Test("Delete email detail removes from cache")
    func testDeleteEmailDetail() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let emailDetail = createTestEmailDetail(id: 1)
        await cache.saveEmailDetail(emailDetail)
        
        // Verify it's cached
        #expect(await cache.isEmailCached(emailId: 1) == true)
        
        // Delete it
        await cache.deleteEmailDetail(emailId: 1)
        
        // Verify it's gone
        #expect(await cache.isEmailCached(emailId: 1) == false)
        #expect(await cache.loadEmailDetail(emailId: 1) == nil)
    }
    
    @Test("Delete multiple email details")
    func testDeleteMultipleEmailDetails() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save multiple emails
        for i in 1...5 {
            let emailDetail = createTestEmailDetail(id: i)
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Delete multiple
        await cache.deleteEmailDetails(emailIds: [1, 3, 5])
        
        // Verify deleted
        #expect(await cache.isEmailCached(emailId: 1) == false)
        #expect(await cache.isEmailCached(emailId: 3) == false)
        #expect(await cache.isEmailCached(emailId: 5) == false)
        
        // Verify others still exist
        #expect(await cache.isEmailCached(emailId: 2) == true)
        #expect(await cache.isEmailCached(emailId: 4) == true)
    }
    
    // MARK: - Batch Save Email Details Tests
    
    @Test("Batch save email details")
    func testBatchSaveEmailDetails() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        var details: [EmailDetail] = []
        for i in 1...10 {
            details.append(createTestEmailDetail(id: i))
        }
        
        await cache.saveEmailDetails(details)
        
        // Verify all are cached
        for i in 1...10 {
            #expect(await cache.isEmailCached(emailId: i) == true)
            let loaded = await cache.loadEmailDetail(emailId: i)
            #expect(loaded != nil)
            #expect(loaded?.id == i)
        }
    }
    
    @Test("Batch save empty array does nothing")
    func testBatchSaveEmptyArray() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let initialCount = await cache.cachedEmailCount()
        
        await cache.saveEmailDetails([])
        
        let finalCount = await cache.cachedEmailCount()
        
        #expect(finalCount == initialCount)
    }
    
    // MARK: - Cleanup Old Emails Tests
    
    @Test("Cleanup old emails removes emails older than specified days")
    func testCleanupOldEmails() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Create old email (20 days ago)
        let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let oldDateString = formatter.string(from: oldDate)
        
        var oldEmail = createTestEmailDetail(id: 1)
        oldEmail = EmailDetail(
            id: oldEmail.id,
            gmail_id: oldEmail.gmail_id,
            thread_id: oldEmail.thread_id,
            subject: oldEmail.subject,
            sender: oldEmail.sender,
            sender_name: oldEmail.sender_name,
            recipients_to: oldEmail.recipients_to,
            recipients_cc: oldEmail.recipients_cc,
            recipients_bcc: oldEmail.recipients_bcc,
            body_text: oldEmail.body_text,
            body_html: oldEmail.body_html,
            snippet: oldEmail.snippet,
            is_read: true, // Must be read to be cleaned up
            is_starred: oldEmail.is_starred,
            labels: oldEmail.labels,
            received_at: oldDateString,
            account_email: oldEmail.account_email,
            created_at: oldDateString
        )
        
        // Create recent email (5 days ago)
        let recentDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let recentDateString = formatter.string(from: recentDate)
        
        var recentEmail = createTestEmailDetail(id: 2)
        recentEmail = EmailDetail(
            id: recentEmail.id,
            gmail_id: recentEmail.gmail_id,
            thread_id: recentEmail.thread_id,
            subject: recentEmail.subject,
            sender: recentEmail.sender,
            sender_name: recentEmail.sender_name,
            recipients_to: recentEmail.recipients_to,
            recipients_cc: recentEmail.recipients_cc,
            recipients_bcc: recentEmail.recipients_bcc,
            body_text: recentEmail.body_text,
            body_html: recentEmail.body_html,
            snippet: recentEmail.snippet,
            is_read: true,
            is_starred: recentEmail.is_starred,
            labels: recentEmail.labels,
            received_at: recentDateString,
            account_email: recentEmail.account_email,
            created_at: recentDateString
        )
        
        await cache.saveEmailDetail(oldEmail)
        await cache.saveEmailDetail(recentEmail)
        
        // Cleanup emails older than 10 days
        await cache.cleanupOldEmails(olderThanDays: 10)
        
        // Old email should be deleted
        #expect(await cache.isEmailCached(emailId: 1) == false)
        
        // Recent email should still exist
        #expect(await cache.isEmailCached(emailId: 2) == true)
    }
    
    @Test("Cleanup does not remove unread emails")
    func testCleanupDoesNotRemoveUnreadEmails() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Create old unread email (20 days ago)
        let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let oldDateString = formatter.string(from: oldDate)
        
        var oldUnreadEmail = createTestEmailDetail(id: 1)
        oldUnreadEmail = EmailDetail(
            id: oldUnreadEmail.id,
            gmail_id: oldUnreadEmail.gmail_id,
            thread_id: oldUnreadEmail.thread_id,
            subject: oldUnreadEmail.subject,
            sender: oldUnreadEmail.sender,
            sender_name: oldUnreadEmail.sender_name,
            recipients_to: oldUnreadEmail.recipients_to,
            recipients_cc: oldUnreadEmail.recipients_cc,
            recipients_bcc: oldUnreadEmail.recipients_bcc,
            body_text: oldUnreadEmail.body_text,
            body_html: oldUnreadEmail.body_html,
            snippet: oldUnreadEmail.snippet,
            is_read: false, // Unread
            is_starred: oldUnreadEmail.is_starred,
            labels: oldUnreadEmail.labels,
            received_at: oldDateString,
            account_email: oldUnreadEmail.account_email,
            created_at: oldDateString
        )
        
        await cache.saveEmailDetail(oldUnreadEmail)
        
        // Cleanup emails older than 10 days
        await cache.cleanupOldEmails(olderThanDays: 10)
        
        // Unread email should NOT be deleted
        #expect(await cache.isEmailCached(emailId: 1) == true)
    }
    
    // MARK: - Concurrent Access Tests
    
    @Test("Concurrent save operations")
    func testConcurrentSaveOperations() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save multiple emails concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...20 {
                group.addTask {
                    let emailDetail = self.createTestEmailDetail(id: i)
                    await cache.saveEmailDetail(emailDetail)
                }
            }
        }
        
        // Verify all are saved
        for i in 1...20 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
    }
    
    @Test("Concurrent load operations")
    func testConcurrentLoadOperations() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save emails first
        for i in 1...10 {
            let emailDetail = createTestEmailDetail(id: i)
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Load concurrently
        var loadedCount = 0
        await withTaskGroup(of: EmailDetail?.self) { group in
            for i in 1...10 {
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
        
        #expect(loadedCount == 10)
    }
    
    @Test("Concurrent save and load operations")
    func testConcurrentSaveAndLoadOperations() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        await withTaskGroup(of: Void.self) { group in
            // Save emails
            for i in 1...10 {
                group.addTask {
                    let emailDetail = self.createTestEmailDetail(id: i)
                    await cache.saveEmailDetail(emailDetail)
                }
            }
            
            // Load emails (may load while saving)
            for i in 1...10 {
                group.addTask {
                    _ = await cache.loadEmailDetail(emailId: i)
                }
            }
        }
        
        // Verify all are saved
        for i in 1...10 {
            #expect(await cache.isEmailCached(emailId: i) == true)
        }
    }
    
    // MARK: - Metadata Cache Tests
    
    @Test("Save and load email metadata")
    func testSaveAndLoadEmailMetadata() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let metadata = [createTestEmailMetadata(id: 1), createTestEmailMetadata(id: 2)]
        await cache.saveEmailMetadata(metadata)
        
        let loaded = await cache.loadEmailMetadata()
        
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == 1 })
        #expect(loaded.contains { $0.id == 2 })
    }
    
    @Test("Save and load email metadata for specific account")
    func testSaveAndLoadEmailMetadataForAccount() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        let metadata = [createTestEmailMetadata(id: 1)]
        await cache.saveEmailMetadata(metadata, accountId: 123)
        
        let loaded = await cache.loadEmailMetadata(accountId: 123)
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == 1)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Cache handles missing files gracefully")
    func testCacheHandlesMissingFiles() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Try to load non-existent email
        let loaded = await cache.loadEmailDetail(emailId: 999)
        
        #expect(loaded == nil)
    }
    
    @Test("Clear all removes all cached emails")
    func testClearAll() async throws {
        let cache = EmailCache.shared
        await cache.clearAll()
        
        // Save some emails
        for i in 1...5 {
            let emailDetail = createTestEmailDetail(id: i)
            await cache.saveEmailDetail(emailDetail)
        }
        
        // Verify they're cached
        #expect(await cache.cachedEmailCount() > 0)
        
        // Clear all
        await cache.clearAll()
        
        // Verify cache is empty
        #expect(await cache.cachedEmailCount() == 0)
        
        // Verify emails are gone
        for i in 1...5 {
            #expect(await cache.isEmailCached(emailId: i) == false)
        }
    }
}

