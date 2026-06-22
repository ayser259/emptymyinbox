import Foundation

/// In-app logo and OS icon choices available to the user.
public struct AppLogoChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Asset catalog image name in the host app bundle, if any.
    public let assetName: String?
    /// SF Symbol used when no asset is available.
    public let systemImage: String

    public init(id: String, title: String, assetName: String?, systemImage: String) {
        self.id = id
        self.title = title
        self.assetName = assetName
        self.systemImage = systemImage
    }
}

/// iOS alternate app icon name (`nil` = primary icon).
public struct AppOSIconChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// `CFBundleAlternateIcons` name; `nil` restores the primary icon.
    public let alternateIconName: String?
    /// Preview asset in host bundle for settings UI.
    public let previewAssetName: String?

    public init(id: String, title: String, alternateIconName: String?, previewAssetName: String?) {
        self.id = id
        self.title = title
        self.alternateIconName = alternateIconName
        self.previewAssetName = previewAssetName
    }
}

public enum AppIconRegistry {
    public static let inAppLogos: [AppLogoChoice] = [
        AppLogoChoice(id: "logo-default", title: "Default", assetName: "Logo", systemImage: "envelope.fill"),
        AppLogoChoice(id: "logo-envelope-circle", title: "Envelope", assetName: nil, systemImage: "envelope.circle.fill"),
        AppLogoChoice(id: "logo-tray", title: "Tray", assetName: nil, systemImage: "tray.full.fill"),
        AppLogoChoice(id: "logo-sparkles", title: "Sparkles", assetName: nil, systemImage: "sparkles"),
        AppLogoChoice(id: "logo-bolt", title: "Bolt", assetName: nil, systemImage: "bolt.fill")
    ]

    /// Bundled alternate iOS icons. Add matching app icon sets + build setting entries to enable more.
    public static let iosOSIcons: [AppOSIconChoice] = [
        AppOSIconChoice(id: "ios-primary", title: "Default", alternateIconName: nil, previewAssetName: "Logo"),
        AppOSIconChoice(id: "ios-gold", title: "Gold", alternateIconName: "AppIconGold", previewAssetName: "Logo")
    ]

    /// Mac Dock icon choices (runtime only; does not change Finder bundle icon).
    public static let macDockIcons: [AppOSIconChoice] = [
        AppOSIconChoice(id: "mac-primary", title: "Default", alternateIconName: nil, previewAssetName: "Logo"),
        AppOSIconChoice(id: "mac-gold", title: "Gold", alternateIconName: "Logo", previewAssetName: "Logo")
    ]

    public static func inAppLogo(withID id: String) -> AppLogoChoice {
        inAppLogos.first { $0.id == id } ?? inAppLogos[0]
    }

    public static func iosOSIcon(withID id: String) -> AppOSIconChoice {
        iosOSIcons.first { $0.id == id } ?? iosOSIcons[0]
    }

    public static func macDockIcon(withID id: String) -> AppOSIconChoice {
        macDockIcons.first { $0.id == id } ?? macDockIcons[0]
    }
}
