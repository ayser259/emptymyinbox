import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Platform-specific app icon changes.
public enum AppIconService {
    #if os(iOS)
    public static var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    public static func setIOSAlternateIcon(name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != name else { return }

        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                logWarning("Failed to set alternate app icon: \(error.localizedDescription)", category: "Appearance")
            }
        }
    }
    #endif

    #if os(macOS)
    public static func setMacDockIcon(assetName: String?) {
        if let assetName, let image = NSImage(named: assetName) {
            NSApplication.shared.applicationIconImage = image
        } else {
            NSApplication.shared.applicationIconImage = nil
        }
    }
    #endif
}
