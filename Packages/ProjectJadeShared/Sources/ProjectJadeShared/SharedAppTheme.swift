import SwiftUI

/// Cross-platform colors and typography driven by user appearance settings.
public enum SharedAppTheme {
    private static var palette: AppThemePalette {
        ThemePaletteBridge.current
    }

    public static var primaryBackground: Color { palette.primaryBackground }
    public static var secondaryBackground: Color { palette.secondaryBackground }
    public static var cardBackground: Color { palette.cardBackground }
    public static var elevatedSurface: Color { palette.elevatedSurface }
    public static var primaryText: Color { palette.primaryText }
    public static var secondaryText: Color { palette.secondaryText }
    public static var accent: Color { palette.accent }
    public static var accentHex: String { palette.accentHex }
    public static var accentPressed: Color { palette.accentPressed }
    public static var accentMuted: Color { palette.accentMuted }
    public static var sidebarSelectionBackground: Color { palette.sidebarSelectionBackground }
    public static var selectionHighlight: Color { palette.selectionHighlight }

    public static var mailboxRowUnreadBackground: Color { palette.mailboxRowUnreadBackground }
    public static var mailboxRowReadBackground: Color { palette.mailboxRowReadBackground }

    public static func mailboxRowBackground(isRead: Bool) -> Color {
        palette.mailboxRowBackground(isRead: isRead)
    }

    public static let spacingUnit: CGFloat = 8
    public static let spacingExtraSmall: CGFloat = 4
    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 16
    public static let spacingLarge: CGFloat = 24
    public static let spacingXLarge: CGFloat = 32
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16

    public static let title2: Font = .title2.weight(.bold)
    public static let title3: Font = .title3.weight(.semibold)
    public static let headline: Font = .headline
    public static let body: Font = .body
    public static let subheadline: Font = .subheadline
    public static let caption: Font = .caption
}

// MARK: - Text styles

public extension View {
    func primaryText() -> some View {
        foregroundStyle(SharedAppTheme.primaryText)
    }

    func secondaryText() -> some View {
        foregroundStyle(SharedAppTheme.secondaryText)
    }

    func appPrimaryBackground() -> some View {
        background(SharedAppTheme.primaryBackground)
    }

    func appSecondaryBackground() -> some View {
        background(SharedAppTheme.secondaryBackground)
    }

    func appCardBackground() -> some View {
        background(SharedAppTheme.cardBackground)
    }
}

// MARK: - Hex colors

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
