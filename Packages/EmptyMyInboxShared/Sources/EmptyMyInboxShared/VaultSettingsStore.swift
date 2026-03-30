//
//  VaultSettingsStore.swift
//  EmptyMyInboxShared
//
//  Persists which vault is active (no secrets).
//

import Foundation

private struct VaultPreferencesFile: Codable, Sendable {
    var activeConfiguration: VaultActiveConfiguration?
}

public actor VaultSettingsStore {
    public static let shared = VaultSettingsStore()

    private let fileName = "vault_preferences.json"
    private var cached: VaultPreferencesFile = .init(activeConfiguration: nil)
    private var didLoad = false

    public init() {}

    public func activeConfiguration() async -> VaultActiveConfiguration? {
        await ensureLoaded()
        return cached.activeConfiguration
    }

    public func setActiveConfiguration(_ config: VaultActiveConfiguration?) async {
        await ensureLoaded()
        cached.activeConfiguration = config
        await persist()
    }

    public func clearActiveConfiguration() async {
        await setActiveConfiguration(nil)
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        cached = await loadFromDisk() ?? .init(activeConfiguration: nil)
    }

    private func loadFromDisk() async -> VaultPreferencesFile? {
        let url = preferencesURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? VaultJSON.decoder().decode(VaultPreferencesFile.self, from: data)
    }

    private func persist() async {
        let url = preferencesURL()
        do {
            let data = try VaultJSON.encoder().encode(cached)
            try data.write(to: url, options: .atomic)
        } catch {
            logError("VaultSettingsStore persist failed: \(error)", category: "Vault")
        }
    }

    private func preferencesURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }
}
