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
}
