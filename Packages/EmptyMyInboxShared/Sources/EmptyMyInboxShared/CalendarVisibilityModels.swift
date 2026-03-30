import Foundation

/// Per-account calendar feature visibility and per-calendar toggles.
public struct CalendarAccountVisibilityRecord: Codable, Identifiable, Hashable {
    public var accountEmail: String
    /// When false, no calendars from this account appear in the Calendar tab.
    public var showAccountInCalendar: Bool
    /// Explicit visibility per Google `calendarId`. Absent keys default to visible when the account is enabled.
    public var calendarVisibility: [String: Bool]

    public var id: String { accountEmail.lowercased() }

    public init(accountEmail: String, showAccountInCalendar: Bool = true, calendarVisibility: [String: Bool] = [:]) {
        self.accountEmail = accountEmail
        self.showAccountInCalendar = showAccountInCalendar
        self.calendarVisibility = calendarVisibility
    }
}
