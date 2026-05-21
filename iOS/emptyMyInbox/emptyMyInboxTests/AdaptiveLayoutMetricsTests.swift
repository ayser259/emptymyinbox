//
//  AdaptiveLayoutMetricsTests.swift
//  emptyMyInboxTests
//

import SwiftUI
import XCTest
@testable import emptyMyInbox

final class AdaptiveLayoutMetricsTests: XCTestCase {
    func testCompactSizeClassNeverUsesWideLayout() {
        XCTAssertFalse(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: .compact,
                width: 1200
            )
        )
    }

    func testRegularSizeClassUsesWideLayoutAboveBreakpoint() {
        XCTAssertTrue(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: .regular,
                width: AdaptiveLayoutMetrics.wideLayoutMinWidth
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: .regular,
                width: AdaptiveLayoutMetrics.wideLayoutMinWidth - 1
            )
        )
    }

    func testNilSizeClassFallsBackToWidth() {
        XCTAssertTrue(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: nil,
                width: 1000
            )
        )
        XCTAssertFalse(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: nil,
                width: 500
            )
        )
    }

    /// Split View / Stage Manager: landscape can still be narrow.
    func testSplitViewNarrowLandscapeStaysCompact() {
        XCTAssertFalse(
            AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: .compact,
                width: 700
            )
        )
    }
}
