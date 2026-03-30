import Combine
import Foundation

@MainActor
public final class GoogleCalendarViewModel: ObservableObject {
    public enum ViewMode: String, CaseIterable, Sendable {
        case events
        case day
        case week
        case month
    }

    @Published public private(set) var events: [GoogleCalendarDisplayEvent] = []
    @Published public private(set) var isLoading = false
    @Published public var selectedDate: Date = Date()
    @Published public var mode: ViewMode = .events
    @Published public var errorMessage: String?

    public init() {}

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let (timeMin, timeMax) = currentTimeWindow()
        let accounts = GmailAPIService.shared.getAllAccounts()

        if accounts.isEmpty {
            events = []
            errorMessage = "No Google accounts connected."
            return
        }

        typealias FetchTask = (account: GmailAccount, calendar: GoogleCalendarListItem)
        var fetchPairs: [FetchTask] = []

        for account in accounts {
            let enabled = await CalendarVisibilityStore.shared.isAccountEnabledForCalendar(accountEmail: account.email)
            guard enabled else { continue }

            do {
                let list = try await GoogleCalendarAPIService.listCalendars(for: account)
                for cal in list {
                    let vis = await CalendarVisibilityStore.shared.isCalendarVisible(accountEmail: account.email, calendarId: cal.id)
                    guard vis else { continue }
                    fetchPairs.append((account, cal))
                }
            } catch {
                logWarning("Calendar list failed for \(account.email): \(error)", category: "Calendar")
                if errorMessage == nil {
                    errorMessage = "Could not load calendars for \(account.email). Reconnect your account to grant Calendar access."
                }
            }
        }

        if fetchPairs.isEmpty {
            events = []
            if errorMessage == nil {
                errorMessage = "No calendars visible. Turn on accounts or calendars in Visibility settings."
            }
            return
        }

        var merged: [GoogleCalendarDisplayEvent] = []
        let maxConcurrent = 5

        for chunkStart in stride(from: 0, to: fetchPairs.count, by: maxConcurrent) {
            let end = min(chunkStart + maxConcurrent, fetchPairs.count)
            let chunk = Array(fetchPairs[chunkStart..<end])
            await withTaskGroup(of: [GoogleCalendarDisplayEvent].self) { group in
                for pair in chunk {
                    group.addTask {
                        do {
                            return try await GoogleCalendarAPIService.listEvents(
                                for: pair.account,
                                calendarId: pair.calendar.id,
                                calendarTitle: pair.calendar.summary,
                                calendarColorHex: pair.calendar.backgroundColor,
                                timeMin: timeMin,
                                timeMax: timeMax
                            )
                        } catch {
                            logWarning(
                                "Events list failed \(pair.account.email) / \(pair.calendar.id): \(error)",
                                category: "Calendar"
                            )
                            return []
                        }
                    }
                }
                for await part in group {
                    merged.append(contentsOf: part)
                }
            }
        }

        merged.sort { $0.start < $1.start }
        events = merged
        if !merged.isEmpty {
            errorMessage = nil
        } else if errorMessage == nil {
            errorMessage = "No events in this range."
        }
    }

    /// Events filtered for the current mode and `selectedDate` (subset of loaded `events`).
    public func eventsForCurrentMode() -> [GoogleCalendarDisplayEvent] {
        let cal = Calendar.current
        switch mode {
        case .events:
            return events
        case .day:
            let s = cal.startOfDay(for: selectedDate)
            guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return events }
            return events.filter { $0.start < e && $0.end > s }
        case .week:
            guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else {
                return events
            }
            let ws = cal.startOfDay(for: weekStart)
            guard let we = cal.date(byAdding: .day, value: 7, to: ws) else { return events }
            return events.filter { $0.start < we && $0.end > ws }
        case .month:
            let comps = cal.dateComponents([.year, .month], from: selectedDate)
            guard let monthStart = cal.date(from: comps) else { return events }
            let ms = cal.startOfDay(for: monthStart)
            guard let monthEnd = cal.date(byAdding: .month, value: 1, to: ms) else { return events }
            return events.filter { $0.start < monthEnd && $0.end > ms }
        }
    }

    public func navigateDate(byDays days: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = d
    }

    public func navigateMonth(by delta: Int) {
        guard let d = Calendar.current.date(byAdding: .month, value: delta, to: selectedDate) else { return }
        selectedDate = d
    }

    public func navigateWeek(by delta: Int) {
        guard let d = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: selectedDate) else { return }
        selectedDate = d
    }

    private func currentTimeWindow() -> (Date, Date) {
        let cal = Calendar.current
        let anchor = selectedDate
        let now = Date()
        switch mode {
        case .events:
            let start = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)) ?? now
            let end = cal.date(byAdding: .day, value: 120, to: now) ?? now
            return (start, end)
        case .day:
            let s = cal.startOfDay(for: anchor)
            let e = cal.date(byAdding: .day, value: 1, to: s) ?? s
            return (s, e)
        case .week:
            let raw = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
            let s = cal.startOfDay(for: raw)
            let e = cal.date(byAdding: .day, value: 7, to: s) ?? s
            return (s, e)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: anchor)
            let s = cal.date(from: comps).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: anchor)
            let e = cal.date(byAdding: .month, value: 1, to: s) ?? s
            return (s, e)
        }
    }
}
