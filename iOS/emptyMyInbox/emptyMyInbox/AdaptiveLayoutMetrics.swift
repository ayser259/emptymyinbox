//
//  AdaptiveLayoutMetrics.swift
//  emptyMyInbox
//
//  Breakpoints for compact (phone-style) vs wide (desktop-style) layouts on iPad.
//

import SwiftUI

enum AdaptiveLayoutMetrics {
    /// Minimum width to show the Mac-like split interface (sidebar + list + detail).
    static let wideLayoutMinWidth: CGFloat = 900

    /// Uses size class first, then explicit width so Split View / Stage Manager stay correct.
    static func shouldUseWideLayout(horizontalSizeClass: UserInterfaceSizeClass?, width: CGFloat) -> Bool {
        if horizontalSizeClass == .compact {
            return false
        }
        return width >= wideLayoutMinWidth
    }
}
