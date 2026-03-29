//
//  AppStateCloudSync.swift
//  EmptyMyInboxShared
//
//  Cross-device sync of durable app state is **disabled by default**: iCloud/CloudKit
//  requires an Apple Developer Program membership. The public API is kept as no-ops so
//  app entry points can call `AppLifecycleCloudSync` unchanged. To re-enable CloudKit
//  later, restore a CloudKit-backed implementation and add iCloud entitlements.
//

import Foundation

/// Reserved for optional CloudKit container ID if you enable iCloud in Xcode.
public enum AppCloudKitConfiguration {
    public static let containerIdentifier = "iCloud.aysersHobbies.emptyMyInbox"
}

/// Record types that would map to a CloudKit schema if sync were enabled.
public enum AppCloudRecordType: String {
    case interestProfile = "InterestProfile"
    case accountInclusions = "AccountInclusions"
    case storiesFeed = "StoriesFeed"
    case llmSettings = "LLMSettings"
    case actionOutboxSummary = "ActionOutboxSummary"
}

/// No-op sync engine: local JSON and stores stay on-device unless you add another backend.
public actor AppStateCloudSync {
    public static let shared = AppStateCloudSync()

    public init() {}

    public func pullMergeAndReloadStores() async {}

    public func pullAndMerge() async {}

    public func pushLocalSnapshots(
        interestProfileData: Data?,
        accountInclusionsData: Data?,
        storiesFeedData: Data?,
        llmSettingsData: Data?,
        actionOutboxSummaryData: Data?
    ) async {
        _ = interestProfileData
        _ = accountInclusionsData
        _ = storiesFeedData
        _ = llmSettingsData
        _ = actionOutboxSummaryData
    }

    public func pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: Data? = nil) async {
        _ = actionOutboxSummary
    }
}

extension AppCloudRecordType: CaseIterable {}
