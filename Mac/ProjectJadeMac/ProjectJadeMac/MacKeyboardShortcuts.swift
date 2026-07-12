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

    /// Shown in the sidebar while reading a message in a mailbox list.
    static let mailMailboxDetail: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Reply", shortcutDisplay: "R"),
        MacSidebarContextualShortcut(title: "Reply All", shortcutDisplay: "⇧R"),
    ]

    /// Shown while the reply composer slide-in panel is open.
    static let mailReplyComposer: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Quick Reply", shortcutDisplay: "⌥Q"),
        MacSidebarContextualShortcut(title: "Generate quick reply", shortcutDisplay: "⌥G"),
        MacSidebarContextualShortcut(title: "Update quick reply", shortcutDisplay: "⌥U"),
        MacSidebarContextualShortcut(title: "Insert quick reply", shortcutDisplay: "⌥I"),
        MacSidebarContextualShortcut(title: "Save draft", shortcutDisplay: "⌘S"),
        MacSidebarContextualShortcut(title: "Send", shortcutDisplay: "⌘↩"),
        MacSidebarContextualShortcut(title: "Close composer", shortcutDisplay: "Esc"),
    ]

    /// Shown after sending a reply from Catch Up.
    static let mailReplySentOutcome: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Mark read & next", shortcutDisplay: "J"),
        MacSidebarContextualShortcut(title: "Review later & next", shortcutDisplay: "F"),
        MacSidebarContextualShortcut(title: "Stay on this email", shortcutDisplay: "Esc"),
    ]

    /// Calendar detail modes (Calendar tab, Tools **Calendar** or **Starred**).
    static let calendarModes: [MacSidebarContextualShortcut] = [
        MacSidebarContextualShortcut(title: "Events", shortcutDisplay: "E"),
        MacSidebarContextualShortcut(title: "Day", shortcutDisplay: "D"),
        MacSidebarContextualShortcut(title: "Week", shortcutDisplay: "W"),
        MacSidebarContextualShortcut(title: "Month", shortcutDisplay: "M"),
    ]
}
