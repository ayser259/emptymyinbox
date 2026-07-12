import Foundation

public extension Notification.Name {
    static let accountAdded = Notification.Name("AccountAdded")
    /// Reserved for future cross-device merge flows (not used while sync is a no-op).
    static let appStateCloudKitDidMerge = Notification.Name("AppStateCloudKitDidMerge")
    /// Posted after a vault sync completes successfully (e.g. Google Drive pull/push).
    static let vaultDidSync = Notification.Name("VaultDidSync")
    /// Local email / dashboard caches were cleared.
    static let cacheCleared = Notification.Name("CacheCleared")
    /// Daily inbox metrics file was updated (refresh or catch-up session).
    static let inboxMetricsDidUpdate = Notification.Name("InboxMetricsDidUpdate")
}
