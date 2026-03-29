//
//  AppStateCloudSync.swift
//  EmptyMyInboxShared
//
//  CloudKit sync for durable app-specific state (not Gmail mail data).
//  Conflict strategy: last-write-wins per record using modificationDate.
//

import CloudKit
import Foundation

/// Shared CloudKit container identifier — must match **iCloud** capability on iOS and macOS targets.
public enum AppCloudKitConfiguration {
    public static let containerIdentifier = "iCloud.aysersHobbies.emptyMyInbox"
}

/// Namespaced record types in the app's CloudKit schema.
public enum AppCloudRecordType: String {
    case interestProfile = "InterestProfile"
    case accountInclusions = "AccountInclusions"
    case storiesFeed = "StoriesFeed"
    case llmSettings = "LLMSettings"
    case actionOutboxSummary = "ActionOutboxSummary"
}

/// Orchestrates push/pull of JSON payloads stored under Application Support.
public actor AppStateCloudSync {
    public static let shared = AppStateCloudSync()

    private let container: CKContainer
    private let database: CKDatabase

    public init(container: CKContainer = CKContainer(identifier: AppCloudKitConfiguration.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    /// Pull remote records, write JSON under Application Support, then refresh in-memory actors.
    public func pullMergeAndReloadStores() async {
        for type in AppCloudRecordType.allCases {
            await pullRecord(type: type)
        }
        await reloadStoresAfterCloudMerge()
    }

    /// Pull remote records and apply to local files (best-effort) without touching in-memory stores.
    public func pullAndMerge() async {
        for type in AppCloudRecordType.allCases {
            await pullRecord(type: type)
        }
    }

    private func reloadStoresAfterCloudMerge() async {
        await InterestProfileStore.shared.invalidateAfterExternalFileChange()
        await AccountInclusionStore.shared.invalidateAfterExternalFileChange()
        await StoriesFeedStore.shared.invalidateAfterExternalFileChange()
        await LLMSettingsStore.shared.invalidateAfterExternalFileChange()
        NotificationCenter.default.post(name: .appStateCloudKitDidMerge, object: nil)
    }

    /// Push current local JSON files to CloudKit.
    public func pushLocalSnapshots(
        interestProfileData: Data?,
        accountInclusionsData: Data?,
        storiesFeedData: Data?,
        llmSettingsData: Data?,
        actionOutboxSummaryData: Data?
    ) async {
        await upsertPayload(type: .interestProfile, data: interestProfileData)
        await upsertPayload(type: .accountInclusions, data: accountInclusionsData)
        await upsertPayload(type: .storiesFeed, data: storiesFeedData)
        await upsertPayload(type: .llmSettings, data: llmSettingsData)
        await upsertPayload(type: .actionOutboxSummary, data: actionOutboxSummaryData)
    }

    /// Reads current JSON files from Application Support (same paths as the stores) and uploads to CloudKit.
    public func pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: Data? = nil) async {
        let base = Self.applicationSupportEmptyMyInboxDirectory()
        let interest = try? Data(contentsOf: base.appendingPathComponent("interest_profile.json"))
        let inclusions = try? Data(contentsOf: base.appendingPathComponent("feature_account_inclusions.json"))
        let stories = try? Data(contentsOf: base.appendingPathComponent("stories_feed_state.json"))
        let llm = try? Data(contentsOf: base.appendingPathComponent("llm_settings.json"))
        let summary = actionOutboxSummary ?? (try? Data(contentsOf: base.appendingPathComponent("pending_actions_cloudkit_summary.json")))
        await pushLocalSnapshots(
            interestProfileData: interest,
            accountInclusionsData: inclusions,
            storiesFeedData: stories,
            llmSettingsData: llm,
            actionOutboxSummaryData: summary
        )
    }

    private static func applicationSupportEmptyMyInboxDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func upsertPayload(type: AppCloudRecordType, data: Data?) async {
        guard let data, !data.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: "singleton-\(type.rawValue)")
        do {
            let record: CKRecord
            if let existing = try await fetchRecord(id: recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: type.rawValue, recordID: recordID)
            }
            record["payload"] = data as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await database.save(record)
            logInfo("CloudKit: saved \(type.rawValue)", category: "CloudSync")
        } catch {
            logWarning("CloudKit: save failed for \(type.rawValue): \(error)", category: "CloudSync")
        }
    }

    private func pullRecord(type: AppCloudRecordType) async {
        let recordID = CKRecord.ID(recordName: "singleton-\(type.rawValue)")
        do {
            guard let record = try await fetchRecord(id: recordID) else { return }
            let data = (record["payload"] as? Data)
                ?? (record["payload"] as? NSData).map { $0 as Data }
            guard let data, !data.isEmpty else { return }
            try await applyPayload(type: type, data: data)
            logInfo("CloudKit: merged \(type.rawValue)", category: "CloudSync")
        } catch {
            logInfo("CloudKit: no remote for \(type.rawValue) or fetch error: \(error)", category: "CloudSync")
        }
    }

    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func applyPayload(type: AppCloudRecordType, data: Data) async throws {
        let base = Self.applicationSupportEmptyMyInboxDirectory()

        let url: URL
        switch type {
        case .interestProfile:
            url = base.appendingPathComponent("interest_profile.json")
        case .accountInclusions:
            url = base.appendingPathComponent("feature_account_inclusions.json")
        case .storiesFeed:
            url = base.appendingPathComponent("stories_feed_state.json")
        case .llmSettings:
            url = base.appendingPathComponent("llm_settings.json")
        case .actionOutboxSummary:
            url = base.appendingPathComponent("pending_actions_cloudkit_summary.json")
        }
        try data.write(to: url, options: .atomic)
    }
}

extension AppCloudRecordType: CaseIterable {}
