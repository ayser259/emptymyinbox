import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Applies the dynamic theme accent to UIKit global appearance proxies.
public enum NativeAccentSynchronizer {
    public static func applyAccent(_ color: Color) {
        #if os(iOS)
        let uiColor = UIColor(color)
        UIView.appearance().tintColor = uiColor
        UITabBar.appearance().tintColor = uiColor
        UINavigationBar.appearance().tintColor = uiColor
        UISegmentedControl.appearance().selectedSegmentTintColor = uiColor
        #endif
    }
}
