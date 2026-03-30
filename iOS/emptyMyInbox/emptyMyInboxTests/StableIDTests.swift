//
//  StableIDTests.swift
//  emptyMyInboxTests
//

import Testing
import EmptyMyInboxShared

struct StableIDTests {
    @Test("StableID account IDs are deterministic and positive")
    func testStableAccountIdDeterministic() {
        let id1 = StableID.accountId(email: "User@Example.com")
        let id2 = StableID.accountId(email: "user@example.com")
        
        #expect(id1 == id2)
        #expect(id1 > 0)
    }
    
    @Test("StableID email IDs are deterministic and distinct")
    func testStableEmailIdDeterministicAndDistinct() {
        let id1a = StableID.emailId(gmailId: "gmail_message_1")
        let id1b = StableID.emailId(gmailId: "gmail_message_1")
        let id2 = StableID.emailId(gmailId: "gmail_message_2")
        
        #expect(id1a == id1b)
        #expect(id1a != id2)
        #expect(id1a > 0)
        #expect(id2 > 0)
    }
    
    @Test("GmailAccount numericId uses stable ID")
    func testGmailAccountNumericIdStable() {
        let account = GmailAccount(
            id: "test@example.com",
            email: "test@example.com",
            name: "Test",
            accessToken: "token",
            refreshToken: "refresh",
            tokenExpiry: nil,
            lastSync: nil,
            unreadEmailsNextPageToken: nil
        )
        
        #expect(account.numericId == StableID.accountId(email: "test@example.com"))
    }
}
