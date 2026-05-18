//
//  ActionItemsNavigation.swift
//  EmptyMyInboxShared
//
//  Primary navigation routes for the Action Items feature (macOS now; iOS later).
//
//  **Future iOS:** bind root navigation to `ActionItemsSection` only — do not duplicate route
//  lists in platform SwiftUI. Grouping and board data come from `ActionItemsFeatureModel`
//  (`boardColumnsForPriority`, `boardColumnsForUrgency`, subject/project helpers). Shared code
//  must not reference macOS-only types (e.g. `MacAppTheme`).
//

import Foundation

/// Sidebar routes for Action Items: **Tools** (dashboard, planner, sticky board, today) and **Categories** (priority, urgency, labels, projects).
/// User-facing **Labels** maps to context/subject buckets in `ActionItemsFeatureModel` (`contextBucketKey`, etc.).
public enum ActionItemsSection: String, Hashable, CaseIterable, Sendable {
    case planner
    case priority
    case urgency
    case labels
    case projects

    /// Window / detail title for the current route.
    public var navigationTitle: String {
        switch self {
        case .planner: return "Planner"
        case .priority: return "Priority"
        case .urgency: return "Urgency"
        case .labels: return "Labels"
        case .projects: return "Projects"
        }
    }

    /// SF Symbol for sidebar rows (macOS / iOS can adjust size).
    public var sidebarSystemImage: String {
        switch self {
        case .planner: return "calendar"
        case .priority: return "exclamationmark.circle"
        case .urgency: return "bolt.fill"
        case .labels: return "tag.fill"
        case .projects: return "folder.fill"
        }
    }

    /// Rows under **Categories** (excludes Tools).
    public static var categoryCases: [ActionItemsSection] {
        [.priority, .urgency, .labels, .projects]
    }
}

/// Full sidebar + detail route for Action Items (category home, channel, Tools).
public enum ActionItemsSidebarDestination: Hashable, Sendable {
    case dashboard
    case planner
    case stickyBoard
    case today
    case priorityHome
    case priorityChannel(boardId: String)
    case urgencyHome
    case urgencyChannel(boardId: String)
    case labelsHome
    case labelChannel(subjectKey: String)
    case projectsHome
    case projectChannel(projectKey: String)

    public var navigationTitle: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .planner:
            return "Planner"
        case .stickyBoard:
            return "Sticky Board"
        case .today:
            return "Today"
        case .priorityHome:
            return "Priority"
        case .priorityChannel(let boardId):
            return "Priority — \(ActionItemsFeatureModel.priorityBoardTitle(forBoardId: boardId))"
        case .urgencyHome:
            return "Urgency"
        case .urgencyChannel(let boardId):
            return "Urgency — \(ActionItemsFeatureModel.urgencyBoardTitle(forBoardId: boardId))"
        case .labelsHome:
            return "Labels"
        case .labelChannel(let key):
            return ActionItemsFeatureModel.displaySubjectHash(key)
        case .projectsHome:
            return "Projects"
        case .projectChannel(let key):
            return ActionItemsFeatureModel.displayProjectPath(key)
        }
    }

    /// `true` when the user is on this category’s overview or one of its channels (sidebar shows channel rows).
    public var isPriorityCategorySelected: Bool {
        switch self {
        case .priorityHome, .priorityChannel: return true
        default: return false
        }
    }

    public var isUrgencyCategorySelected: Bool {
        switch self {
        case .urgencyHome, .urgencyChannel: return true
        default: return false
        }
    }

    public var isLabelsCategorySelected: Bool {
        switch self {
        case .labelsHome, .labelChannel: return true
        default: return false
        }
    }

    public var isProjectsCategorySelected: Bool {
        switch self {
        case .projectsHome, .projectChannel: return true
        default: return false
        }
    }
}

/// Pinned category channel under the **Starred** sidebar section; synced via `ActionItems/starred_channels.json`.
public struct ActionItemsSidebarPin: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case priorityChannel
        case urgencyChannel
        case labelChannel
        case projectChannel
    }

    public var kind: Kind
    /// `p0`…`none`…; label subject key; project key from `groupedByProject`.
    public var identifier: String

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    public var sortKey: String { "\(kind.rawValue)|\(identifier)" }

    public func toRoute() -> ActionItemsSidebarDestination {
        switch kind {
        case .priorityChannel:
            return .priorityChannel(boardId: identifier)
        case .urgencyChannel:
            return .urgencyChannel(boardId: identifier)
        case .labelChannel:
            return .labelChannel(subjectKey: identifier)
        case .projectChannel:
            return .projectChannel(projectKey: identifier)
        }
    }

    /// Title for sidebar rows (matches `navigationTitle` for the pin’s route).
    public var pinRowTitle: String { toRoute().navigationTitle }
}

/// One column on a category “board” view — same shape for Mac boards and future iPad/iOS layouts.
public struct ActionItemsBoardColumn: Equatable {
    public var boardId: String
    public var title: String
    public var items: [VaultActionItemRecord]

    public init(boardId: String, title: String, items: [VaultActionItemRecord]) {
        self.boardId = boardId
        self.title = title
        self.items = items
    }
}
