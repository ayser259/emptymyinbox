import Foundation

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
}
