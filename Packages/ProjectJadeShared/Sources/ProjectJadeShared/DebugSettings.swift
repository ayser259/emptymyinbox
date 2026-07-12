import Foundation
import SwiftUI

/// Persists debug mode (used by settings and email debug UI).
public final class DebugSettings: ObservableObject {
    public static let shared = DebugSettings()

    private let debugModeKey = "debugModeEnabled"

    @Published public var isDebugModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDebugModeEnabled, forKey: debugModeKey)
        }
    }

    private init() {
        self.isDebugModeEnabled = UserDefaults.standard.bool(forKey: debugModeKey)
    }

    public func toggle() {
        isDebugModeEnabled.toggle()
    }
}
