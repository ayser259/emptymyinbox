import SwiftUI

/// User-customizable color palette persisted as hex strings.
public struct AppThemePalette: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var primaryBackgroundHex: String
    public var secondaryBackgroundHex: String
    public var cardBackgroundHex: String
    public var elevatedSurfaceHex: String
    public var primaryTextHex: String
    public var secondaryTextHex: String
    public var accentHex: String
    public var accentPressedHex: String
    public var mailboxRowUnreadBackgroundHex: String
    public var mailboxRowReadBackgroundHex: String

    public init(
        id: String,
        name: String,
        primaryBackgroundHex: String,
        secondaryBackgroundHex: String,
        cardBackgroundHex: String,
        elevatedSurfaceHex: String,
        primaryTextHex: String,
        secondaryTextHex: String,
        accentHex: String,
        accentPressedHex: String,
        mailboxRowUnreadBackgroundHex: String,
        mailboxRowReadBackgroundHex: String
    ) {
        self.id = id
        self.name = name
        self.primaryBackgroundHex = primaryBackgroundHex
        self.secondaryBackgroundHex = secondaryBackgroundHex
        self.cardBackgroundHex = cardBackgroundHex
        self.elevatedSurfaceHex = elevatedSurfaceHex
        self.primaryTextHex = primaryTextHex
        self.secondaryTextHex = secondaryTextHex
        self.accentHex = accentHex
        self.accentPressedHex = accentPressedHex
        self.mailboxRowUnreadBackgroundHex = mailboxRowUnreadBackgroundHex
        self.mailboxRowReadBackgroundHex = mailboxRowReadBackgroundHex
    }

    public var primaryBackground: Color { HexColorUtilities.color(from: primaryBackgroundHex) }
    public var secondaryBackground: Color { HexColorUtilities.color(from: secondaryBackgroundHex) }
    public var cardBackground: Color { HexColorUtilities.color(from: cardBackgroundHex) }
    public var elevatedSurface: Color { HexColorUtilities.color(from: elevatedSurfaceHex) }
    public var primaryText: Color { HexColorUtilities.color(from: primaryTextHex) }
    public var secondaryText: Color { HexColorUtilities.color(from: secondaryTextHex) }
    public var accent: Color { HexColorUtilities.color(from: accentHex) }
    public var accentPressed: Color { HexColorUtilities.color(from: accentPressedHex) }
    public var accentMuted: Color { accent.opacity(0.3) }
    public var sidebarSelectionBackground: Color { Color.white.opacity(0.1) }
    public var selectionHighlight: Color { accent.opacity(0.22) }

    public var mailboxRowUnreadBackground: Color {
        HexColorUtilities.color(from: mailboxRowUnreadBackgroundHex)
    }

    public var mailboxRowReadBackground: Color {
        HexColorUtilities.color(from: mailboxRowReadBackgroundHex).opacity(0.65)
    }

    public func mailboxRowBackground(isRead: Bool) -> Color {
        isRead ? mailboxRowReadBackground : mailboxRowUnreadBackground
    }

    /// Current default: dark background with gold accent.
    public static let defaultDarkGold = AppThemePalette(
        id: "default-dark-gold",
        name: "Gold",
        primaryBackgroundHex: "#000000",
        secondaryBackgroundHex: "#0A0A0A",
        cardBackgroundHex: "#252525",
        elevatedSurfaceHex: "#1E1E1E",
        primaryTextHex: "#FFFFFF",
        secondaryTextHex: "#E0E0E0",
        accentHex: "#F6AC0A",
        accentPressedHex: "#D99A08",
        mailboxRowUnreadBackgroundHex: "#262628",
        mailboxRowReadBackgroundHex: "#0E0E0E"
    )

    public static let presetOcean = AppThemePalette(
        id: "preset-ocean",
        name: "Ocean",
        primaryBackgroundHex: "#000000",
        secondaryBackgroundHex: "#0A1018",
        cardBackgroundHex: "#152030",
        elevatedSurfaceHex: "#101820",
        primaryTextHex: "#FFFFFF",
        secondaryTextHex: "#C8D8E8",
        accentHex: "#3B9EFF",
        accentPressedHex: "#2A7FD4",
        mailboxRowUnreadBackgroundHex: "#1A2838",
        mailboxRowReadBackgroundHex: "#0A1018"
    )

    public static let presetForest = AppThemePalette(
        id: "preset-forest",
        name: "Forest",
        primaryBackgroundHex: "#000000",
        secondaryBackgroundHex: "#0A120A",
        cardBackgroundHex: "#1A2A1A",
        elevatedSurfaceHex: "#121A12",
        primaryTextHex: "#FFFFFF",
        secondaryTextHex: "#D0E8D0",
        accentHex: "#4ADE80",
        accentPressedHex: "#22C55E",
        mailboxRowUnreadBackgroundHex: "#1E2E1E",
        mailboxRowReadBackgroundHex: "#0A120A"
    )

    public static let presetViolet = AppThemePalette(
        id: "preset-violet",
        name: "Violet",
        primaryBackgroundHex: "#000000",
        secondaryBackgroundHex: "#100A18",
        cardBackgroundHex: "#221A30",
        elevatedSurfaceHex: "#181020",
        primaryTextHex: "#FFFFFF",
        secondaryTextHex: "#E0D0F0",
        accentHex: "#A855F7",
        accentPressedHex: "#9333EA",
        mailboxRowUnreadBackgroundHex: "#2A1A38",
        mailboxRowReadBackgroundHex: "#100A18"
    )

    public static let presets: [AppThemePalette] = [
        .defaultDarkGold,
        .presetOcean,
        .presetForest,
        .presetViolet
    ]

    public static func preset(withID id: String) -> AppThemePalette? {
        presets.first { $0.id == id }
    }

    /// Sanitizes each hex field, falling back to the default palette for invalid values.
    public func sanitized(defaults: AppThemePalette = .defaultDarkGold) -> AppThemePalette {
        AppThemePalette(
            id: id,
            name: name,
            primaryBackgroundHex: HexColorUtilities.normalizedHex(primaryBackgroundHex) ?? defaults.primaryBackgroundHex,
            secondaryBackgroundHex: HexColorUtilities.normalizedHex(secondaryBackgroundHex) ?? defaults.secondaryBackgroundHex,
            cardBackgroundHex: HexColorUtilities.normalizedHex(cardBackgroundHex) ?? defaults.cardBackgroundHex,
            elevatedSurfaceHex: HexColorUtilities.normalizedHex(elevatedSurfaceHex) ?? defaults.elevatedSurfaceHex,
            primaryTextHex: HexColorUtilities.normalizedHex(primaryTextHex) ?? defaults.primaryTextHex,
            secondaryTextHex: HexColorUtilities.normalizedHex(secondaryTextHex) ?? defaults.secondaryTextHex,
            accentHex: HexColorUtilities.normalizedHex(accentHex) ?? defaults.accentHex,
            accentPressedHex: HexColorUtilities.normalizedHex(accentPressedHex) ?? defaults.accentPressedHex,
            mailboxRowUnreadBackgroundHex: HexColorUtilities.normalizedHex(mailboxRowUnreadBackgroundHex) ?? defaults.mailboxRowUnreadBackgroundHex,
            mailboxRowReadBackgroundHex: HexColorUtilities.normalizedHex(mailboxRowReadBackgroundHex) ?? defaults.mailboxRowReadBackgroundHex
        )
    }
}
