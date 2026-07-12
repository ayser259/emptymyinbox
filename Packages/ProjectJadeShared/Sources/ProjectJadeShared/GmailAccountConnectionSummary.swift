//
//  GmailAccountConnectionSummary.swift
//  ProjectJadeShared
//
//  Per-account Google service + vault linkage for Settings.
//

import Foundation

extension GmailAccount {
    /// What this signed-in account can reach (Mail / Drive) and whether the active vault is tied to it.
    public struct ConnectionSummary: Sendable, Equatable {
        /// Gmail API (always true while the account is connected in the app).
        public var gmail: Bool
        /// Google Drive app data (`drive.file`), used for Drive-backed vault.
        public var drive: Bool
        /// Active vault’s `ownerAccountEmail` / `driveAccountEmail` matches this account.
        public var vaultLinked: Bool
        /// One-line description when `vaultLinked` (e.g. name + backend).
        public var vaultDetailLine: String?

        public init(
            gmail: Bool,
            drive: Bool,
            vaultLinked: Bool,
            vaultDetailLine: String?
        ) {
            self.gmail = gmail
            self.drive = drive
            self.vaultLinked = vaultLinked
            self.vaultDetailLine = vaultDetailLine
        }
    }

    public func connectionSummary(activeVault: VaultActiveConfiguration?) -> ConnectionSummary {
        let owner = activeVault?.resolvedOwnerEmail
        let vaultLinked = owner != nil && owner?.caseInsensitiveCompare(email) == .orderedSame
        let vaultLine: String?
        if vaultLinked, let v = activeVault {
            let title = (v.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (v.displayName ?? "Vault")
                : "Vault"
            vaultLine = "\(title) — \(v.backend.settingsDisplayName)"
        } else {
            vaultLine = nil
        }
        return ConnectionSummary(
            gmail: true,
            drive: hasDriveFileAccessForSettings,
            vaultLinked: vaultLinked,
            vaultDetailLine: vaultLine
        )
    }
}
