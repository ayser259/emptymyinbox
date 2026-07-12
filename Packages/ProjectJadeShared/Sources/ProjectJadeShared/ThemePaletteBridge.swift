import SwiftUI

/// Thread-safe palette cache updated by `AppearanceSettingsStore` for nonisolated theme reads.
public enum ThemePaletteBridge {
    nonisolated(unsafe) private(set) static var current: AppThemePalette = .defaultDarkGold

    @MainActor
    static func sync(from store: AppearanceSettingsStore) {
        current = store.resolvedPalette
    }
}
