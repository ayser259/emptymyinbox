import Foundation

extension Notification.Name {
    /// `object` is `Int` (`MacRootTab.rawValue`).
    static let macSelectRootTab = Notification.Name("MacSelectRootTab")
    /// `object` is `String` (`MailTool.rawValue`).
    static let macSelectMailTool = Notification.Name("MacSelectMailTool")
    /// Cycle Mail → Calendar → Action Items (⌃Tab). `⌘Tab` is reserved by macOS for the app switcher.
    static let macCycleRootTabForward = Notification.Name("MacCycleRootTabForward")
    static let macRefreshCurrentRootTab = Notification.Name("MacRefreshCurrentRootTab")
}

/// Sidebar “Shortcuts” panel rows shared across Mail, Calendar, and Action Items sidebars.
enum MacSidebarShortcutLibrary {
    /// Primary navigation + refresh + next tab (shown on every primary-tab sidebar).
    static let global: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Mail", shortcutDisplay: "⌘1"),
        MacSidebarContextualShortcut(title: "Calendar", shortcutDisplay: "⌘2"),
        MacSidebarContextualShortcut(title: "Action Items", shortcutDisplay: "⌘3"),
        MacSidebarContextualShortcut(title: "Refresh", shortcutDisplay: "⌘R"),
        MacSidebarContextualShortcut(title: "Next primary tab", shortcutDisplay: "⌃Tab"),
    ]

    /// Mail detail tools.
    static let mailTools: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Catch Up", shortcutDisplay: "⌥C"),
        MacSidebarContextualShortcut(title: "Stories", shortcutDisplay: "⌥S"),
        MacSidebarContextualShortcut(title: "Brief", shortcutDisplay: "⌥B"),
    ]

    /// Calendar detail modes (Calendar tab, Tools **Calendar** or **Starred**).
    static let calendarModes: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Events", shortcutDisplay: "E"),
        MacSidebarContextualShortcut(title: "Day", shortcutDisplay: "D"),
        MacSidebarContextualShortcut(title: "Week", shortcutDisplay: "W"),
        MacSidebarContextualShortcut(title: "Month", shortcutDisplay: "M"),
    ]
}
