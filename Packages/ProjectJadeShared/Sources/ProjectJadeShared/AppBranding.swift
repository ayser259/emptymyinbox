import Foundation

/// User-facing branding strings and defaults.
public enum AppBranding {
    public static let defaultDisplayName = "Jade"
    public static let defaultVaultDisplayName = "Jade Vault"

    public static func vaultDisplayName(using customName: String?) -> String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return defaultVaultDisplayName }
        return "\(trimmed) Vault"
    }
}
