import SwiftUI

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue: AppThemePalette = .defaultDarkGold
}

public extension EnvironmentValues {
    var appThemePalette: AppThemePalette {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }
}

public extension View {
    func appThemePalette(_ palette: AppThemePalette) -> some View {
        environment(\.appThemePalette, palette)
    }
}
