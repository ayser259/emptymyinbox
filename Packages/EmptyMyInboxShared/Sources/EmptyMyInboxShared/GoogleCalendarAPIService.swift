import Foundation

/// Google Calendar API v3 (REST) using bearer tokens from `GmailAPIService`.
public enum GoogleCalendarAPIService {
    private static let baseURL = "https://www.googleapis.com/calendar/v3"

    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let rfc3339FormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let allDayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Lists calendars the user can access (calendar list).
    public static func listCalendars(for account: GmailAccount) async throws -> [GoogleCalendarListItem] {
        let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
        var all: [GCalCalendarListEntry] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(baseURL)/users/me/calendarList")!
            var items: [URLQueryItem] = [
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "showHidden", value: "false")
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = items
            guard let url = components.url else { throw GoogleCalendarAPIError.invalidURL }

            let (data, response) = try await authorizedGET(url: url, token: token)
            try throwIfNeeded(response, data)
            let decoded = try JSONDecoder().decode(GCalCalendarListResponse.self, from: data)
            if let batch = decoded.items {
                all.append(contentsOf: batch.filter { !($0.deleted == true) })
            }
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return all.compactMap { entry in
            let title = entry.summaryOverride ?? entry.summary ?? entry.id
            if entry.hidden == true { return nil }
            if let role = entry.accessRole, !["owner", "writer", "reader"].contains(role) {
                return nil
            }
            return GoogleCalendarListItem(
                id: entry.id,
                summary: title,
                backgroundColor: entry.backgroundColor,
                isPrimary: entry.primary == true
            )
        }
    }

    /// Lists instances in a time window. Uses `singleEvents=true` and `orderBy=startTime`.
    public static func listEvents(
        for account: GmailAccount,
        calendarId: String,
        calendarTitle: String,
        calendarColorHex: String?,
        timeMin: Date,
        timeMax: Date
    ) async throws -> [GoogleCalendarDisplayEvent] {
        let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
        let minStr = rfc3339String(for: timeMin)
        let maxStr = rfc3339String(for: timeMax)
        let encodedId = calendarId.encodedForGoogleCalendarPath()

        var allEvents: [GCalEvent] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(baseURL)/calendars/\(encodedId)/events")!
            var q: [URLQueryItem] = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: minStr),
                URLQueryItem(name: "timeMax", value: maxStr),
                URLQueryItem(name: "maxResults", value: "250")
            ]
            if let pageToken {
                q.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = q
            guard let url = components.url else { throw GoogleCalendarAPIError.invalidURL }

            let (data, response) = try await authorizedGET(url: url, token: token)
            try throwIfNeeded(response, data)
            let decoded = try JSONDecoder().decode(GCalEventsListResponse.self, from: data)
            if let items = decoded.items {
                allEvents.append(contentsOf: items)
            }
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        let email = account.email
        return allEvents.compactMap { ev in
            guard ev.status != "cancelled" else { return nil }
            guard let (start, end, allDay) = parseEventBounds(ev) else { return nil }
            let title = (ev.summary?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "(No title)"
            return GoogleCalendarDisplayEvent(
                eventId: ev.id,
                calendarId: calendarId,
                accountEmail: email,
                title: title,
                start: start,
                end: end,
                isAllDay: allDay,
                calendarTitle: calendarTitle,
                colorHex: calendarColorHex
            )
        }
    }

    // MARK: - Private

    private static func authorizedGET(url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await urlSession.data(for: request)
    }

    private static func throwIfNeeded(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GoogleCalendarAPIError.httpError(http.statusCode, body)
        }
    }

    private static func rfc3339String(for date: Date) -> String {
        let s = rfc3339Formatter.string(from: date)
        if !s.isEmpty { return s }
        return rfc3339FormatterNoFrac.string(from: date)
    }

    private static func parseEventBounds(_ ev: GCalEvent) -> (Date, Date, Bool)? {
        if let day = ev.start.date {
            let cal = Calendar.current
            guard let parsedStart = allDayDateFormatter.date(from: day) else { return nil }
            let start = cal.startOfDay(for: parsedStart)
            let endDayString = ev.end.date ?? day
            guard let parsedEndExclusive = allDayDateFormatter.date(from: endDayString) else { return nil }
            let endExclusiveStart = cal.startOfDay(for: parsedEndExclusive)
            let lastIncludedDay = cal.date(byAdding: .day, value: -1, to: endExclusiveStart) ?? start
            let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: lastIncludedDay) ?? start
            return (start, end, true)
        }
        guard let startStr = ev.start.dateTime else { return nil }
        let endStr = ev.end.dateTime ?? startStr
        guard let start = parseISO8601(startStr) else { return nil }
        guard let end = parseISO8601(endStr) else { return nil }
        return (start, end, false)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        if let d = rfc3339Formatter.date(from: string) { return d }
        return rfc3339FormatterNoFrac.date(from: string)
    }
}

private extension String {
    /// Percent-encode for use as a single path segment (calendar IDs may contain `@`, `#`, etc.).
    func encodedForGoogleCalendarPath() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
