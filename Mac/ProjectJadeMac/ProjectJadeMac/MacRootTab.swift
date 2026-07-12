import Foundation
import SwiftUI

/// Primary window tab (toolbar segmented control + **Go** menu shortcut ⌘1).
enum MacRootTab: Int, CaseIterable, Identifiable, Hashable {
    case mail = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mail: return "Mail"
        }
    }

    var shortcutDisplay: String {
        switch self {
        case .mail: return "⌘1"
        }
    }

    var keyboardShortcutKey: KeyEquivalent {
        switch self {
        case .mail: return "1"
        }
    }
}
