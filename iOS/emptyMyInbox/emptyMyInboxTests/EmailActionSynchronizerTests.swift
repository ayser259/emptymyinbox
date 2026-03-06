//
//  EmailActionSynchronizerTests.swift
//  emptyMyInboxTests
//

import Testing
@testable import emptyMyInbox

struct EmailActionSynchronizerTests {
    @Test("Star actions coalesce to latest intent")
    func testStarActionsCoalesce() async {
        let synchronizer = EmailActionSynchronizer.shared
        await synchronizer.setTestingDisableProcessing(true)
        await synchronizer.testingClearPendingActions()
        
        await synchronizer.enqueueStar(
            emailId: 1,
            gmailId: "gmail-1",
            accountEmail: "test@example.com",
            shouldStar: true
        )
        await synchronizer.enqueueStar(
            emailId: 1,
            gmailId: "gmail-1",
            accountEmail: "test@example.com",
            shouldStar: false
        )
        
        let actions = await synchronizer.testingPendingActions()
        #expect(actions.count == 1)
        #expect(actions.first?.kind == .unstar)
        
        await synchronizer.testingClearPendingActions()
        await synchronizer.setTestingDisableProcessing(false)
    }
    
    @Test("Read actions coalesce to latest intent")
    func testReadActionsCoalesce() async {
        let synchronizer = EmailActionSynchronizer.shared
        await synchronizer.setTestingDisableProcessing(true)
        await synchronizer.testingClearPendingActions()
        
        await synchronizer.enqueueMarkRead(
            emailId: 2,
            gmailId: "gmail-2",
            accountEmail: "test@example.com"
        )
        await synchronizer.enqueueMarkUnread(
            emailId: 2,
            gmailId: "gmail-2",
            accountEmail: "test@example.com"
        )
        
        let actions = await synchronizer.testingPendingActions()
        #expect(actions.count == 1)
        #expect(actions.first?.kind == .markUnread)
        
        await synchronizer.testingClearPendingActions()
        await synchronizer.setTestingDisableProcessing(false)
    }
}
