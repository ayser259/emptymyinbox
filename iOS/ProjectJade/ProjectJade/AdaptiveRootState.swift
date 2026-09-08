//
//  AdaptiveRootState.swift
//  ProjectJade
//
//  Shared navigation state preserved across compact ↔ wide layout transitions.
//

import SwiftUI
import ProjectJadeShared

@MainActor
final class AdaptiveRootState: ObservableObject {
    enum MailTool: String, CaseIterable, Identifiable, Hashable {
        case dashboard
        case catchUp
        case stories
        case brief

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .catchUp: return "Catch Up"
            case .stories: return "Stories"
            case .brief: return "Brief"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.33percent"
            case .catchUp: return "tray.full"
            case .stories: return "rectangle.stack.fill"
            case .brief: return "sparkles"
            }
        }
    }

    enum MailSidebarSelection: Hashable {
        case tool(MailTool)
        case mailbox(MailboxScope)
    }

    @Published var showMenu = false
    /// True when `iPadWideRootView` chrome is active (hide compact duplicate top bars).
    @Published var usesWideChrome = false

    @Published var mailSidebarSelection: MailSidebarSelection = .tool(.dashboard)
    @Published var selectedThreadId: Int?
    @Published var selectedThread: EmailThreadSummary?
    @Published var mailNavigationPath = NavigationPath()

    func resetMailSelection() {
        selectedThreadId = nil
        selectedThread = nil
        mailNavigationPath = NavigationPath()
    }

    func selectMailSidebar(_ selection: MailSidebarSelection) {
        mailSidebarSelection = selection
        resetMailSelection()
    }
}
