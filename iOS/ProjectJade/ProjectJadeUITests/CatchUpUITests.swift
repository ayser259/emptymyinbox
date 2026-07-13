//
//  CatchUpUITests.swift
//  ProjectJadeUITests
//
//  UI tests for Catch Up view
//

import XCTest

final class CatchUpUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Set up launch arguments for testing
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    @MainActor
    func testCatchUpViewDisplays() throws {
        // Wait for app to launch
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: app, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Basic test: app should launch without crashing
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }
    
    @MainActor
    func testCatchUpViewHasElements() throws {
        // Wait for app to launch
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: app, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // App should have some UI elements
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }

    @MainActor
    func testIPadCatchUpExitReturnsToDashboard() throws {
        let catchUpSidebar = app.buttons["ipad_sidebar_tool_catchUp"]
        guard catchUpSidebar.waitForExistence(timeout: 8) else {
            throw XCTSkip("Wide iPad layout is required for this navigation test")
        }

        catchUpSidebar.tap()

        let returnButton = app.buttons["catchup_return_to_dashboard"]
        let backButton = app.buttons["navigation_back_button"]
        let exitControl = returnButton.waitForExistence(timeout: 8)
            ? returnButton
            : (backButton.waitForExistence(timeout: 3) ? backButton : nil)

        XCTAssertNotNil(exitControl, "Catch Up should expose a return or back control on iPad")
        exitControl?.tap()

        let dashboardSidebar = app.buttons["ipad_sidebar_tool_dashboard"]
        XCTAssertTrue(
            dashboardSidebar.waitForExistence(timeout: 5),
            "Dashboard sidebar item should remain available after exiting Catch Up"
        )
        XCTAssertFalse(
            app.navigationBars["Catch Up"].waitForExistence(timeout: 2),
            "Catch Up detail should no longer be visible after exit"
        )
    }
}
