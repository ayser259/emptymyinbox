import Foundation

public extension Notification.Name {
    static let accountAdded = Notification.Name("AccountAdded")
    /// Reserved for future cross-device merge flows (not used while sync is a no-op).
    static let appStateCloudKitDidMerge = Notification.Name("AppStateCloudKitDidMerge")
}
