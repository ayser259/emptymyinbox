import Foundation
import SwiftUI

/// Primary window tabs (toolbar segmented control + **Go** menu shortcuts ⌘1–⌘3).
enum MacRootTab: Int, CaseIterable, Identifiable, Hashable {
    case mail = 0
    case calendar = 1
    case actionItems = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .actionItems: return "Action Items"
        }
    }

    var shortcutDisplay: String {
        switch self {
        case .mail: return "⌘1"
        case .calendar: return "⌘2"
        case .actionItems: return "⌘3"
        }
    }

    var keyboardShortcutKey: KeyEquivalent {
        switch self {
        case .mail: return "1"
        case .calendar: return "2"
        case .actionItems: return "3"
        }
    }
}
