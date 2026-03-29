import Foundation

public extension Notification.Name {
    static let accountAdded = Notification.Name("AccountAdded")
    /// Posted after CloudKit merged remote JSON into Application Support and stores were invalidated.
    static let appStateCloudKitDidMerge = Notification.Name("AppStateCloudKitDidMerge")
}
