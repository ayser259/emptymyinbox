//
//  Theme.swift
//  ProjectJade
//
//  Theme and styling system for the app
//

import SwiftUI
import ProjectJadeShared

/// App-wide theme configuration (delegates to shared dynamic palette).
struct AppTheme {
    static var primaryBackground: Color { SharedAppTheme.primaryBackground }
    static var secondaryBackground: Color { SharedAppTheme.secondaryBackground }
    static var cardBackground: Color { SharedAppTheme.cardBackground }
    static var elevatedSurface: Color { SharedAppTheme.elevatedSurface }
    static var primaryText: Color { SharedAppTheme.primaryText }
    static var secondaryText: Color { SharedAppTheme.secondaryText }
    static var accent: Color { SharedAppTheme.accent }
    static var accentMuted: Color { SharedAppTheme.accentMuted }
    static var accentPressed: Color { SharedAppTheme.accentPressed }

    static let spacingUnit: CGFloat = SharedAppTheme.spacingUnit
    static let spacingSmall: CGFloat = SharedAppTheme.spacingExtraSmall
    static let spacingMedium: CGFloat = SharedAppTheme.spacingMedium
    static let spacingLarge: CGFloat = SharedAppTheme.spacingLarge
    static let spacingXLarge: CGFloat = SharedAppTheme.spacingXLarge
    static let cornerRadiusSmall: CGFloat = SharedAppTheme.cornerRadiusSmall
    static let cornerRadiusMedium: CGFloat = SharedAppTheme.cornerRadiusMedium
    static let cornerRadiusLarge: CGFloat = SharedAppTheme.cornerRadiusLarge

    static let largeTitle: Font = .system(size: 34, weight: .bold, design: .default)
    static let title: Font = .system(size: 28, weight: .bold, design: .default)
    static let title2: Font = .system(size: 22, weight: .bold, design: .default)
    static let title3: Font = .system(size: 20, weight: .semibold, design: .default)
    static let headline: Font = .system(size: 17, weight: .semibold, design: .default)
    static let body: Font = .system(size: 17, weight: .regular, design: .default)
    static let callout: Font = .system(size: 16, weight: .regular, design: .default)
    static let subheadline: Font = .system(size: 15, weight: .regular, design: .default)
    static let footnote: Font = .system(size: 13, weight: .regular, design: .default)
    static let caption: Font = .system(size: 12, weight: .regular, design: .default)

    static let shadow: ShadowStyle = .init(
        color: .black.opacity(0.3),
        radius: 8,
        x: 0,
        y: 4
    )

    static let shadowLight: ShadowStyle = .init(
        color: .black.opacity(0.2),
        radius: 4,
        x: 0,
        y: 2
    )
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func appShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func primaryBackground() -> some View {
        self.background(AppTheme.primaryBackground)
    }

    func secondaryBackground() -> some View {
        self.background(AppTheme.secondaryBackground)
    }

    func accentColor() -> some View {
        self.foregroundColor(AppTheme.accent)
    }
}
