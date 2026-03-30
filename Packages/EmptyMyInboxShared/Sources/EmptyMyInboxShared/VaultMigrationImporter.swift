//
//  VaultMigrationImporter.swift
//  EmptyMyInboxShared
//
//  One-time import of existing on-device JSON into the vault (idempotent).
//

import Foundation

private let migrationInterestKey = "vault_import_interest_profile_v1_done"

public enum VaultMigrationImporter {
    /// Copies current `InterestProfile` into `Inbox/interest_profile_import.json` as a vault envelope (once per install).
    public static func importInterestProfileOnce(
        folderBackend: any VaultFolderBackend,
        userDefaults: UserDefaults = .standard
    ) async throws {
        guard !userDefaults.bool(forKey: migrationInterestKey) else { return }
        let profile = await InterestProfileStore.shared.currentProfile()
        let token = VaultLWWHelpers.nextWriteToken(existingData: nil)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: profile
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await folderBackend.write(relativePath: "\(VaultLayout.inboxFolder)/interest_profile_import.json", data: data)
        userDefaults.set(true, forKey: migrationInterestKey)
    }
}
