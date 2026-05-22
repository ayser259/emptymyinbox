import Foundation

/// Read-only shortcut rows for the Settings reference screen (mirrors Mac sidebar / menu shortcuts).
public struct SettingsShortcutReference: Identifiable, Hashable, Sendable {
    public let title: String
    public let shortcutDisplay: String

    public var id: String { "\(title)|\(shortcutDisplay)" }

    public init(title: String, shortcutDisplay: String) {
        self.title = title
        self.shortcutDisplay = shortcutDisplay
    }
}

public enum SettingsShortcutsReference {
    /// Primary navigation + refresh (every tab).
    public static let global: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Mail", shortcutDisplay: "⌘1"),
        SettingsShortcutReference(title: "Calendar", shortcutDisplay: "⌘2"),
        SettingsShortcutReference(title: "Action Items", shortcutDisplay: "⌘3"),
        SettingsShortcutReference(title: "Refresh", shortcutDisplay: "⌘R"),
        SettingsShortcutReference(title: "Next primary tab", shortcutDisplay: "⌃Tab"),
    ]

    /// Mail tab — detail tools.
    public static let mailTools: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Catch Up", shortcutDisplay: "⌥C"),
        SettingsShortcutReference(title: "Stories", shortcutDisplay: "⌥S"),
        SettingsShortcutReference(title: "Brief", shortcutDisplay: "⌥B"),
    ]

    /// Mail — reading a message in a mailbox (inbox list + detail).
    public static let mailMailboxDetail: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Reply", shortcutDisplay: "R"),
        SettingsShortcutReference(title: "Reply All (when others are on the thread)", shortcutDisplay: "⇧R"),
    ]

    /// Calendar tab — Calendar or Starred tools.
    public static let calendarModes: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Events", shortcutDisplay: "E"),
        SettingsShortcutReference(title: "Day", shortcutDisplay: "D"),
        SettingsShortcutReference(title: "Week", shortcutDisplay: "W"),
        SettingsShortcutReference(title: "Month", shortcutDisplay: "M"),
    ]

    /// Mail — Catch Up contextual shortcuts (when viewing Catch Up).
    public static let mailCatchUp: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Review Later", shortcutDisplay: "F"),
        SettingsShortcutReference(title: "Star", shortcutDisplay: "S"),
        SettingsShortcutReference(title: "Mark as read", shortcutDisplay: "J"),
        SettingsShortcutReference(title: "Reply", shortcutDisplay: "R"),
        SettingsShortcutReference(title: "Reply All (when others are on the thread)", shortcutDisplay: "⇧R"),
        SettingsShortcutReference(title: "Unsubscribe", shortcutDisplay: "⌘⇧U"),
    ]

    /// Mail — Reply composer (when composing a reply).
    public static let mailReplyComposer: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Quick Reply", shortcutDisplay: "⌥Q"),
        SettingsShortcutReference(title: "Save draft", shortcutDisplay: "⌘S"),
        SettingsShortcutReference(title: "Send", shortcutDisplay: "⌘↩"),
    ]

    /// Action Items tab — sidebar hints.
    public static let actionItems: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Priority", shortcutDisplay: "p0–p4"),
        SettingsShortcutReference(title: "Urgency", shortcutDisplay: "u0–u4"),
        SettingsShortcutReference(title: "Labels", shortcutDisplay: "@"),
        SettingsShortcutReference(title: "Projects", shortcutDisplay: "#"),
    ]
}
