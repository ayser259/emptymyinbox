//
//  DashboardUITests.swift
//  ProjectJadeUITests
//
//  UI tests for Dashboard view
//

import XCTest

final class DashboardUITests: XCTestCase {
    
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
    func testDashboardDisplays() throws {
        // Wait for app to launch
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: app, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Basic test: app should launch without crashing
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }
    
    @MainActor
    func testDashboardHasElements() throws {
        // Wait for app to launch
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: app, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // App should have some UI elements
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }

    @MainActor
    func testHamburgerMenuNavigatesToSettingsPane() throws {
        let menuButton = app.buttons["main_menu_button"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 8), "Hamburger menu button should be visible")

        menuButton.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5), "Settings sheet should be visible")

        let appearanceRow = app.buttons["settings_sidebar_appearance"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5), "Appearance settings row should be visible")
        appearanceRow.tap()

        let appearanceDetail = app.descendants(matching: .any)["settings_detail_appearance"]
        let appearanceHeader = app.staticTexts["Appearance"]
        let appearanceField = app.textFields["App name"]
        let didNavigate = appearanceDetail.waitForExistence(timeout: 5)
            || appearanceHeader.waitForExistence(timeout: 5)
            || appearanceField.waitForExistence(timeout: 5)
        XCTAssertTrue(didNavigate, "Appearance detail should be shown")

        let closeButton = app.buttons["settings_close_button"]
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        } else {
            app.buttons["Close"].tap()
        }

        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Dashboard should be visible after closing settings")
    }
}
