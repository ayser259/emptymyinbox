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
    /// Refresh (Mac / iPad with keyboard).
    public static let global: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Refresh", shortcutDisplay: "⌘R"),
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
        SettingsShortcutReference(title: "Generate quick reply", shortcutDisplay: "⌥G"),
        SettingsShortcutReference(title: "Update quick reply", shortcutDisplay: "⌥U"),
        SettingsShortcutReference(title: "Insert quick reply", shortcutDisplay: "⌥I"),
        SettingsShortcutReference(title: "Save draft", shortcutDisplay: "⌘S"),
        SettingsShortcutReference(title: "Send", shortcutDisplay: "⌘↩"),
    ]

    /// Mail — after sending a reply from Catch Up.
    public static let mailReplySentOutcome: [SettingsShortcutReference] = [
        SettingsShortcutReference(title: "Mark read & next", shortcutDisplay: "J"),
        SettingsShortcutReference(title: "Review later & next", shortcutDisplay: "F"),
        SettingsShortcutReference(title: "Stay on this email", shortcutDisplay: "Esc"),
    ]

}
