import Foundation

/// User-facing branding strings and defaults.
public enum AppBranding {
    public static let defaultDisplayName = "Empty My Inbox"
    public static let defaultVaultDisplayName = "Empty My Inbox Vault"

    public static func vaultDisplayName(using customName: String?) -> String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return defaultVaultDisplayName }
        return "\(trimmed) Vault"
    }
}
