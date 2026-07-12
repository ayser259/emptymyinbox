import Foundation

/// Per-account calendar feature visibility and per-calendar toggles.
public struct CalendarAccountVisibilityRecord: Codable, Identifiable, Hashable {
    public var accountEmail: String
    /// When false, no calendars from this account appear in the Calendar tab.
    public var showAccountInCalendar: Bool
    /// Explicit visibility per Google `calendarId`. Absent keys default to visible when the account is enabled.
    public var calendarVisibility: [String: Bool]
    /// Google `calendarId`s the user starred (e.g. Mac sidebar “Starred” filter).
    public var starredCalendarIds: [String]

    public var id: String { accountEmail.lowercased() }

    public init(
        accountEmail: String,
        showAccountInCalendar: Bool = true,
        calendarVisibility: [String: Bool] = [:],
        starredCalendarIds: [String] = []
    ) {
        self.accountEmail = accountEmail
        self.showAccountInCalendar = showAccountInCalendar
        self.calendarVisibility = calendarVisibility
        self.starredCalendarIds = starredCalendarIds
    }

    enum CodingKeys: String, CodingKey {
        case accountEmail
        case showAccountInCalendar
        case calendarVisibility
        case starredCalendarIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountEmail = try c.decode(String.self, forKey: .accountEmail)
        showAccountInCalendar = try c.decodeIfPresent(Bool.self, forKey: .showAccountInCalendar) ?? true
        calendarVisibility = try c.decodeIfPresent([String: Bool].self, forKey: .calendarVisibility) ?? [:]
        starredCalendarIds = try c.decodeIfPresent([String].self, forKey: .starredCalendarIds) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountEmail, forKey: .accountEmail)
        try c.encode(showAccountInCalendar, forKey: .showAccountInCalendar)
        try c.encode(calendarVisibility, forKey: .calendarVisibility)
        try c.encode(starredCalendarIds, forKey: .starredCalendarIds)
    }
}
