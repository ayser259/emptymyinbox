//
//  MacTheme.swift
//  ProjectJadeMac
//

import SwiftUI
import ProjectJadeShared

enum MacAppTheme {
    static var primaryBackground: Color { SharedAppTheme.primaryBackground }
    static var secondaryBackground: Color { SharedAppTheme.secondaryBackground }
    static var primaryText: Color { SharedAppTheme.primaryText }
    static var secondaryText: Color { SharedAppTheme.secondaryText }
    static var accent: Color { SharedAppTheme.accent }
    static var sidebarSelectionBackground: Color { SharedAppTheme.sidebarSelectionBackground }
    static let cornerRadiusSmall: CGFloat = SharedAppTheme.cornerRadiusSmall
    static let spacingMedium: CGFloat = SharedAppTheme.spacingMedium
}

extension View {
    func macPrimaryBackground() -> some View {
        background(MacAppTheme.primaryBackground)
    }
}
