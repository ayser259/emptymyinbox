import Foundation
import SwiftUI

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

    /// Persisted palette baseline; draft fields below preview live until Apply.
    private var savedPaletteMode: AppearancePaletteMode
    private var savedPresetPaletteID: String
    private var savedCustomPalette: AppThemePalette

    @Published public var paletteMode: AppearancePaletteMode {
        didSet { publishPaletteChange() }
    }

    @Published public var presetPaletteID: String {
        didSet { publishPaletteChange() }
    }

    @Published public var customPalette: AppThemePalette {
        didSet { publishPaletteChange() }
    }

    public var hasUnsavedPaletteChanges: Bool {
        paletteMode != savedPaletteMode
            || presetPaletteID != savedPresetPaletteID
            || customPalette != savedCustomPalette
    }

    public var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppBranding.defaultDisplayName : trimmed
    }

    public var resolvedVaultDisplayName: String {
        AppBranding.vaultDisplayName(using: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName)
    }

    public var resolvedPalette: AppThemePalette {
        switch paletteMode {
        case .preset:
            return AppThemePalette.preset(withID: presetPaletteID)?.sanitized() ?? .defaultDarkGold
        case .custom:
            return customPalette.sanitized()
        }
    }

    /// Saved palette used for platform icon application (not draft preview).
    public var savedResolvedPalette: AppThemePalette {
        switch savedPaletteMode {
        case .preset:
            return AppThemePalette.preset(withID: savedPresetPaletteID)?.sanitized() ?? .defaultDarkGold
        case .custom:
            return savedCustomPalette.sanitized()
        }
    }

    /// In-app logo asset name derived from the current (possibly draft) palette.
    public var resolvedLogoAssetName: String {
        AppIconRegistry.themeIcon(forPaletteID: resolvedPalette.id).logoAssetName
    }

    /// App always runs in dark mode to match the dark-only palettes.
    public var swiftUIColorScheme: ColorScheme? {
        .dark
    }

    private init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: Keys.displayName) ?? AppBranding.defaultDisplayName

        let loadedPaletteMode: AppearancePaletteMode
        if let raw = defaults.string(forKey: Keys.paletteMode),
           let mode = AppearancePaletteMode(rawValue: raw) {
            loadedPaletteMode = mode
        } else {
            loadedPaletteMode = .preset
        }

        let loadedPresetPaletteID = defaults.string(forKey: Keys.presetPaletteID) ?? AppThemePalette.defaultDarkGold.id

        let loadedCustomPalette: AppThemePalette
        if let data = defaults.data(forKey: Keys.customPaletteJSON),
           let decoded = try? JSONDecoder().decode(AppThemePalette.self, from: data) {
            loadedCustomPalette = decoded.sanitized()
        } else {
            loadedCustomPalette = .defaultDarkGold
        }

        savedPaletteMode = loadedPaletteMode
        savedPresetPaletteID = loadedPresetPaletteID
        savedCustomPalette = loadedCustomPalette
        paletteMode = loadedPaletteMode
        presetPaletteID = loadedPresetPaletteID
        customPalette = loadedCustomPalette

        applyPlatformIconsOnLaunch()
        publishPaletteChange()
    }

    public func selectPreset(_ preset: AppThemePalette) {
        paletteMode = .preset
        presetPaletteID = preset.id
    }

    public func selectCustom() {
        paletteMode = .custom
    }

    public func applyPaletteChanges() {
        savedPaletteMode = paletteMode
        savedPresetPaletteID = presetPaletteID
        savedCustomPalette = customPalette
        persistPaletteToUserDefaults()
        applyPlatformIconsFromSavedPalette()
        publishPaletteChange()
    }

    public func revertPaletteChanges() {
        paletteMode = savedPaletteMode
        presetPaletteID = savedPresetPaletteID
        customPalette = savedCustomPalette
        publishPaletteChange()
    }

    public func updateCustomHex(_ keyPath: WritableKeyPath<AppThemePalette, String>, value: String) {
        if paletteMode != .custom {
            var seeded = resolvedPalette.sanitized()
            seeded.id = AppThemePalette.customPaletteID
            seeded.name = "Custom"
            customPalette = seeded
            paletteMode = .custom
        }
        customPalette[keyPath: keyPath] = value
    }

    public func resetToDefaults() {
        displayName = AppBranding.defaultDisplayName
        paletteMode = .preset
        presetPaletteID = AppThemePalette.defaultDarkGold.id
        customPalette = .defaultDarkGold
        savedPaletteMode = paletteMode
        savedPresetPaletteID = presetPaletteID
        savedCustomPalette = customPalette
        persistPaletteToUserDefaults()
        applyPlatformIconsFromSavedPalette()
        publishPaletteChange()
    }

    private func persistDisplayName() {
        UserDefaults.standard.set(displayName, forKey: Keys.displayName)
    }

    private func persistPaletteToUserDefaults() {
        UserDefaults.standard.set(paletteMode.rawValue, forKey: Keys.paletteMode)
        UserDefaults.standard.set(presetPaletteID, forKey: Keys.presetPaletteID)
        if let data = try? JSONEncoder().encode(customPalette.sanitized()) {
            UserDefaults.standard.set(data, forKey: Keys.customPaletteJSON)
        }
    }

    private func applyPlatformIconsOnLaunch() {
        applyPlatformIconsFromSavedPalette()
    }

    private func applyPlatformIconsFromSavedPalette() {
        let themeIcon = AppIconRegistry.themeIcon(forPaletteID: savedResolvedPalette.id)
        #if os(iOS)
        AppIconService.setIOSAlternateIcon(name: themeIcon.iosAlternateIconName)
        #endif
        #if os(macOS)
        AppIconService.setMacDockIcon(assetName: themeIcon.macDockAssetName)
        #endif
    }

    private func publishPaletteChange() {
        ThemePaletteBridge.sync(from: self)
        paletteRevision += 1
        NativeAccentSynchronizer.applyAccent(resolvedPalette.accent)
    }
}
