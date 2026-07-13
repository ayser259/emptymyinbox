//
//  AdaptiveRootStateTests.swift
//  ProjectJadeTests
//

import XCTest
@testable import ProjectJade

@MainActor
final class AdaptiveRootStateTests: XCTestCase {
    func testDefaultTabIsMail() {
        let state = AdaptiveRootState()
        XCTAssertEqual(state.selectedTab, AdaptiveRootState.RootTab.mail.rawValue)
        XCTAssertEqual(state.rootTab, .mail)
    }

    func testRootTabSetter() {
        let state = AdaptiveRootState()
        state.rootTab = .mail
        XCTAssertEqual(state.selectedTab, AdaptiveRootState.RootTab.mail.rawValue)
        XCTAssertEqual(state.rootTab, .mail)
    }

    func testSelectMailSidebarUpdatesSelectionAndClearsNavigation() {
        let state = AdaptiveRootState()
        state.selectedThreadId = 42
        state.mailNavigationPath.append(99)

        state.selectMailSidebar(.tool(.catchUp))

        XCTAssertEqual(state.mailSidebarSelection, .tool(.catchUp))
        XCTAssertNil(state.selectedThreadId)
        XCTAssertNil(state.selectedThread)
        XCTAssertTrue(state.mailNavigationPath.isEmpty)
    }

    func testSelectMailSidebarReturnsToDashboard() {
        let state = AdaptiveRootState()
        state.selectMailSidebar(.tool(.catchUp))
        state.selectMailSidebar(.tool(.dashboard))
        XCTAssertEqual(state.mailSidebarSelection, .tool(.dashboard))
    }
}
