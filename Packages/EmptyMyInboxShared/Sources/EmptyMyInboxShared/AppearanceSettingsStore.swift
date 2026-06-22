import Foundation
import SwiftUI

public enum AppearanceColorSchemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum AppearancePaletteMode: String, Codable, Sendable {
    case preset
    case custom
}

/// Persists and publishes user appearance preferences across iOS and macOS.
@MainActor
public final class AppearanceSettingsStore: ObservableObject {
    public static let shared = AppearanceSettingsStore()

    private enum Keys {
        static let displayName = "appearance.displayName"
        static let logoChoiceID = "appearance.logoChoiceID"
        static let iosOSIconChoiceID = "appearance.iosOSIconChoiceID"
        static let macDockIconChoiceID = "appearance.macDockIconChoiceID"
        static let colorSchemeMode = "appearance.colorSchemeMode"
        static let paletteMode = "appearance.paletteMode"
        static let presetPaletteID = "appearance.presetPaletteID"
        static let customPaletteJSON = "appearance.customPaletteJSON"
    }

    @Published public private(set) var paletteRevision = 0

    @Published public var displayName: String {
        didSet {
            persistDisplayName()
            publishPaletteChange()
        }
    }

    @Published public var logoChoiceID: String {
        didSet {
            UserDefaults.standard.set(logoChoiceID, forKey: Keys.logoChoiceID)
            publishPaletteChange()
        }
    }

    @Published public var iosOSIconChoiceID: String {
        didSet {
            UserDefaults.standard.set(iosOSIconChoiceID, forKey: Keys.iosOSIconChoiceID)
            applyIOSAppIconIfNeeded()
        }
    }

    @Published public var macDockIconChoiceID: String {
        didSet {
            UserDefaults.standard.set(macDockIconChoiceID, forKey: Keys.macDockIconChoiceID)
            applyMacDockIconIfNeeded()
        }
    }

    @Published public var colorSchemeMode: AppearanceColorSchemeMode {
        didSet {
            UserDefaults.standard.set(colorSchemeMode.rawValue, forKey: Keys.colorSchemeMode)
            publishPaletteChange()
        }
    }

    @Published public var paletteMode: AppearancePaletteMode {
        didSet {
            UserDefaults.standard.set(paletteMode.rawValue, forKey: Keys.paletteMode)
            publishPaletteChange()
        }
    }

    @Published public var presetPaletteID: String {
        didSet {
            UserDefaults.standard.set(presetPaletteID, forKey: Keys.presetPaletteID)
            publishPaletteChange()
        }
    }

    @Published public var customPalette: AppThemePalette {
        didSet {
            persistCustomPalette()
            publishPaletteChange()
        }
    }

    public var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppBranding.defaultDisplayName : trimmed
    }

    public var resolvedVaultDisplayName: String {
        AppBranding.vaultDisplayName(using: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName)
    }

    public var selectedLogoChoice: AppLogoChoice {
        AppIconRegistry.inAppLogo(withID: logoChoiceID)
    }

    public var resolvedPalette: AppThemePalette {
        switch paletteMode {
        case .preset:
            return AppThemePalette.preset(withID: presetPaletteID)?.sanitized() ?? .defaultDarkGold
        case .custom:
            return customPalette.sanitized()
        }
    }

    public var swiftUIColorScheme: ColorScheme? {
        colorSchemeMode.swiftUIColorScheme
    }

    private init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: Keys.displayName) ?? AppBranding.defaultDisplayName
        logoChoiceID = defaults.string(forKey: Keys.logoChoiceID) ?? AppIconRegistry.inAppLogos[0].id
        iosOSIconChoiceID = defaults.string(forKey: Keys.iosOSIconChoiceID) ?? AppIconRegistry.iosOSIcons[0].id
        macDockIconChoiceID = defaults.string(forKey: Keys.macDockIconChoiceID) ?? AppIconRegistry.macDockIcons[0].id

        if let raw = defaults.string(forKey: Keys.colorSchemeMode),
           let mode = AppearanceColorSchemeMode(rawValue: raw) {
            colorSchemeMode = mode
        } else {
            colorSchemeMode = .dark
        }

        if let raw = defaults.string(forKey: Keys.paletteMode),
           let mode = AppearancePaletteMode(rawValue: raw) {
            paletteMode = mode
        } else {
            paletteMode = .preset
        }

        presetPaletteID = defaults.string(forKey: Keys.presetPaletteID) ?? AppThemePalette.defaultDarkGold.id

        if let data = defaults.data(forKey: Keys.customPaletteJSON),
           let decoded = try? JSONDecoder().decode(AppThemePalette.self, from: data) {
            customPalette = decoded.sanitized()
        } else {
            customPalette = .defaultDarkGold
        }

        applyPlatformIconsOnLaunch()
        publishPaletteChange()
    }

    public func selectPreset(_ preset: AppThemePalette) {
        paletteMode = .preset
        presetPaletteID = preset.id
        publishPaletteChange()
    }

    public func updateCustomHex(_ keyPath: WritableKeyPath<AppThemePalette, String>, value: String) {
        paletteMode = .custom
        customPalette[keyPath: keyPath] = value
    }

    public func resetToDefaults() {
        displayName = AppBranding.defaultDisplayName
        logoChoiceID = AppIconRegistry.inAppLogos[0].id
        iosOSIconChoiceID = AppIconRegistry.iosOSIcons[0].id
        macDockIconChoiceID = AppIconRegistry.macDockIcons[0].id
        colorSchemeMode = .dark
        paletteMode = .preset
        presetPaletteID = AppThemePalette.defaultDarkGold.id
        customPalette = .defaultDarkGold
        applyPlatformIconsOnLaunch()
        publishPaletteChange()
    }

    private func persistDisplayName() {
        UserDefaults.standard.set(displayName, forKey: Keys.displayName)
    }

    private func persistCustomPalette() {
        paletteMode = .custom
        if let data = try? JSONEncoder().encode(customPalette.sanitized()) {
            UserDefaults.standard.set(data, forKey: Keys.customPaletteJSON)
        }
    }

    private func applyPlatformIconsOnLaunch() {
        applyIOSAppIconIfNeeded()
        applyMacDockIconIfNeeded()
    }

    private func applyIOSAppIconIfNeeded() {
        #if os(iOS)
        let choice = AppIconRegistry.iosOSIcon(withID: iosOSIconChoiceID)
        AppIconService.setIOSAlternateIcon(name: choice.alternateIconName)
        #endif
    }

    private func applyMacDockIconIfNeeded() {
        #if os(macOS)
        let choice = AppIconRegistry.macDockIcon(withID: macDockIconChoiceID)
        AppIconService.setMacDockIcon(assetName: choice.alternateIconName)
        #endif
    }

    private func publishPaletteChange() {
        ThemePaletteBridge.sync(from: self)
        paletteRevision += 1
        NativeAccentSynchronizer.applyAccent(resolvedPalette.accent)
    }
}
