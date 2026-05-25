//
//  AdaptiveRootStateTests.swift
//  emptyMyInboxTests
//

import XCTest
@testable import emptyMyInbox
import EmptyMyInboxShared

@MainActor
final class AdaptiveRootStateTests: XCTestCase {
    func testSelectMailSidebarClearsThreadSelection() {
        let state = AdaptiveRootState()
        state.selectedThreadId = 42
        state.mailNavigationPath.append(99)

        state.selectMailSidebar(.mailbox(.allUnread))

        XCTAssertNil(state.selectedThreadId)
        XCTAssertNil(state.selectedThread)
        XCTAssertTrue(state.mailNavigationPath.isEmpty)
        XCTAssertEqual(state.mailSidebarSelection, .mailbox(.allUnread))
    }

    func testRootTabRoundTrip() {
        let state = AdaptiveRootState()
        state.rootTab = .calendar
        XCTAssertEqual(state.selectedTab, AdaptiveRootState.RootTab.calendar.rawValue)
        XCTAssertEqual(state.rootTab, .calendar)
    }
}
