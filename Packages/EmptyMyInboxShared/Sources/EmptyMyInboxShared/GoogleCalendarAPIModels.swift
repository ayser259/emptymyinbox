import Foundation

// MARK: - API DTOs (subset of Google Calendar API)

struct GCalCalendarListResponse: Codable {
    let items: [GCalCalendarListEntry]?
    let nextPageToken: String?
}

struct GCalCalendarListEntry: Codable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let backgroundColor: String?
    let foregroundColor: String?
    let primary: Bool?
    let accessRole: String?
    let hidden: Bool?
    let deleted: Bool?
}

struct GCalEventDateTime: Codable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GCalEvent: Codable {
    let id: String
    let status: String?
    let summary: String?
    let start: GCalEventDateTime
    let end: GCalEventDateTime
}

struct GCalEventsListResponse: Codable {
    let items: [GCalEvent]?
    let nextPageToken: String?
}

// MARK: - App models

public struct GoogleCalendarListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let summary: String
    public let backgroundColor: String?
    public let isPrimary: Bool

    public init(id: String, summary: String, backgroundColor: String?, isPrimary: Bool) {
        self.id = id
        self.summary = summary
        self.backgroundColor = backgroundColor
        self.isPrimary = isPrimary
    }
}

public struct GoogleCalendarDisplayEvent: Identifiable, Hashable, Sendable {
    public let compositeId: String
    public let eventId: String
    public let calendarId: String
    public let accountEmail: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let colorHex: String?

    public var id: String { compositeId }

    public init(
        eventId: String,
        calendarId: String,
        accountEmail: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarTitle: String,
        colorHex: String?
    ) {
        self.eventId = eventId
        self.calendarId = calendarId
        self.accountEmail = accountEmail
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.compositeId = "\(accountEmail.lowercased())|\(calendarId)|\(eventId)"
    }
}

public enum GoogleCalendarAPIError: LocalizedError {
    case invalidURL
    case httpError(Int, String?)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Calendar API URL"
        case .httpError(let code, let body):
            if let body, !body.isEmpty {
                return "Calendar API error (\(code)): \(body)"
            }
            return "Calendar API error (\(code))"
        case .decodingFailed:
            return "Failed to decode Calendar API response"
        }
    }
}
