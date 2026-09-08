import Foundation

/// Hooks for optional cross-device sync. Currently **no-ops** (no iCloud without Apple Developer Program).
/// Call sites can stay as-is; enabling CloudKit or another backend can plug in here later.
public enum AppLifecycleCloudSync {
    public static func performStartupSync() async {
        await AppStateCloudSync.shared.pullMergeAndReloadStores()
        let summary = await EmailActionSynchronizer.shared.exportCloudSyncSummaryData()
        await AppStateCloudSync.shared.pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: summary)
    }

    public static func pushLocalStateOnly() async {
        let summary = await EmailActionSynchronizer.shared.exportCloudSyncSummaryData()
        await AppStateCloudSync.shared.pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: summary)
    }
}
