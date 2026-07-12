import Foundation

/// App icon and logo assets tied to a theme preset.
public struct ThemeAppIcon: Sendable, Equatable {
    public let paletteID: String
    /// Asset catalog image name for in-app logo and Mac Dock icon preview.
    public let logoAssetName: String
    /// iOS alternate app icon name; `nil` restores the primary (Gold) icon.
    public let iosAlternateIconName: String?
    /// Mac Dock icon asset name; `nil` restores the bundled app icon.
    public let macDockAssetName: String?

    public init(
        paletteID: String,
        logoAssetName: String,
        iosAlternateIconName: String?,
        macDockAssetName: String?
    ) {
        self.paletteID = paletteID
        self.logoAssetName = logoAssetName
        self.iosAlternateIconName = iosAlternateIconName
        self.macDockAssetName = macDockAssetName
    }
}

public enum AppIconRegistry {
    public static let themeIcons: [ThemeAppIcon] = [
        ThemeAppIcon(
            paletteID: AppThemePalette.defaultDarkGold.id,
            logoAssetName: "ThemeIconGold",
            iosAlternateIconName: nil,
            macDockAssetName: "ThemeIconGold"
        ),
        ThemeAppIcon(
            paletteID: AppThemePalette.presetOcean.id,
            logoAssetName: "ThemeIconOcean",
            iosAlternateIconName: "AppIconOcean",
            macDockAssetName: "ThemeIconOcean"
        ),
        ThemeAppIcon(
            paletteID: AppThemePalette.presetForest.id,
            logoAssetName: "ThemeIconForest",
            iosAlternateIconName: "AppIconForest",
            macDockAssetName: "ThemeIconForest"
        ),
        ThemeAppIcon(
            paletteID: AppThemePalette.presetViolet.id,
            logoAssetName: "ThemeIconViolet",
            iosAlternateIconName: "AppIconViolet",
            macDockAssetName: "ThemeIconViolet"
        )
    ]

    private static let goldThemeIcon: ThemeAppIcon = themeIcons[0]

    /// Returns the icon mapping for a palette ID. Custom and unknown IDs fall back to Gold.
    public static func themeIcon(forPaletteID id: String) -> ThemeAppIcon {
        if id == AppThemePalette.customPaletteID {
            return goldThemeIcon
        }
        return themeIcons.first { $0.paletteID == id } ?? goldThemeIcon
    }
}
