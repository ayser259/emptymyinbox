//
//  MacTheme.swift
//  emptymyinboxMacApp
//
//  Matches iOS Theme.swift so the Mac app shares the same look (dark + gold accent).
//

import SwiftUI
import EmptyMyInboxShared

enum MacAppTheme {
    static let primaryBackground = Color.black
    static let secondaryBackground = Color(hex: "#0a0a0a")
    static let primaryText = Color.white
    static let secondaryText = Color(hex: "#e0e0e0")
    /// Gold accent (toolbar, selection labels). Avoid tinting large sidebar areas with this — use `sidebarSelectionBackground`.
    static let accent = Color(hex: "#f6ac0a")
    /// Subtle highlight behind the selected sidebar row (neutral, not accent-tinted).
    static let sidebarSelectionBackground = Color.white.opacity(0.1)
    static let cornerRadiusSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
}

extension View {
    func macPrimaryBackground() -> some View {
        background(MacAppTheme.primaryBackground)
    }
}
