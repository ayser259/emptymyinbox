import SwiftUI

/// Cross-platform colors and typography aligned with iOS `AppTheme` and macOS `MacAppTheme`.
public enum SharedAppTheme {
    public static let primaryBackground = Color.black
    public static let secondaryBackground = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    public static let primaryText = Color.white
    public static let secondaryText = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255)
    public static let accent = Color(red: 246 / 255, green: 172 / 255, blue: 10 / 255)

    public static let spacingUnit: CGFloat = 8
    /// Tight spacing (4pt) — matches iOS `AppTheme.spacingSmall`.
    public static let spacingExtraSmall: CGFloat = 4
    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 16
    public static let spacingLarge: CGFloat = 24
    public static let spacingXLarge: CGFloat = 32
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16

    /// Dynamic Type–aware text styles (prefer these over fixed `system(size:)` in forms).
    public static let title2: Font = .title2.weight(.bold)
    public static let title3: Font = .title3.weight(.semibold)
    public static let headline: Font = .headline
    public static let body: Font = .body
    public static let subheadline: Font = .subheadline
    public static let caption: Font = .caption
}

// MARK: - Text styles (match iOS Theme.swift)

public extension View {
    func primaryText() -> some View {
        foregroundStyle(SharedAppTheme.primaryText)
    }

    func secondaryText() -> some View {
        foregroundStyle(SharedAppTheme.secondaryText)
    }
}

// MARK: - Hex colors (match iOS / Mac theme helpers)

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
