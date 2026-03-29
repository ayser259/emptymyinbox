import Foundation

/// App entry-point helpers for CloudKit round-trips (call from `App` `.task` / scene activation).
public enum AppLifecycleCloudSync {
    /// Pull remote JSON → disk → reload in-memory stores, then push local files + action summary.
    public static func performStartupSync() async {
        await AppStateCloudSync.shared.pullMergeAndReloadStores()
        let summary = await EmailActionSynchronizer.shared.exportCloudSyncSummaryData()
        await AppStateCloudSync.shared.pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: summary)
    }

    /// Push current Application Support JSON and outbox summary without pulling first.
    public static func pushLocalStateOnly() async {
        let summary = await EmailActionSynchronizer.shared.exportCloudSyncSummaryData()
        await AppStateCloudSync.shared.pushLocalSnapshotsFromApplicationSupport(actionOutboxSummary: summary)
    }
}
