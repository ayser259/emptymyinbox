import Foundation

public enum DailyBriefingDefaults {
    public static let persistedPayloadKey = "persistedDailyBriefingPayload"
    public static let lastCheckDateKey = "lastDailyBriefingCheckDate"
}

public extension Notification.Name {
    /// Posted after a new daily briefing is saved to UserDefaults (so dashboard badges can refresh).
    static let briefingPayloadDidPersist = Notification.Name("BriefingPayloadDidPersist")
}
