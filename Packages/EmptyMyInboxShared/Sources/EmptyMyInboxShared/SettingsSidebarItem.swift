import Foundation

/// Sidebar destinations for the Obsidian-style settings split view.
public enum SettingsSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case general
    case connectedAccounts
    case shortcuts
    case storage
    case keys
    case corePlugins

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .connectedAccounts: return "Connected Accounts"
        case .shortcuts: return "Shortcuts"
        case .storage: return "Storage"
        case .keys: return "Keys"
        case .corePlugins: return "Core Plugins"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .connectedAccounts: return "person.crop.circle.badge.checkmark"
        case .shortcuts: return "keyboard"
        case .storage: return "internaldrive"
        case .keys: return "key.fill"
        case .corePlugins: return "puzzlepiece.extension"
        }
    }
}
