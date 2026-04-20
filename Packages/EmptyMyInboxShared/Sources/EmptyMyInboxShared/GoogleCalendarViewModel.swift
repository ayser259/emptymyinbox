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
    /// True while a fetch is in flight and `events` is non-empty (background sync).
    @Published public private(set) var isSyncing = false
    @Published public var selectedDate: Date = Date()
    @Published public var mode: ViewMode = .events
    @Published public var errorMessage: String?
    /// When true (e.g. Mac sidebar “Starred”), only events from starred calendars are shown.
    @Published public private(set) var restrictToStarredCalendars: Bool = false

    /// Precomputed for week columns (keys are start-of-day).
    @Published public private(set) var weekDayBuckets: [Date: [GoogleCalendarDisplayEvent]] = [:]
    /// 1-based day-of-month -> event count for month grid.
    @Published public private(set) var monthDayEventCounts: [Int: Int] = [:]

    private var inFlightRefreshID: UUID?
    private var lastRefreshAt: Date?
    private let automaticRefreshInterval: TimeInterval = 1800

    /// Cached Google Calendar list per account (email lowercased).
    private var calendarListCache: [String: (items: [GoogleCalendarListItem], fetchedAt: Date)] = [:]
    private let calendarListTTL: TimeInterval = 300
    private let eventWindowCacheTTL: TimeInterval = 300

    /// Loaded event window from last successful fetch (expanded fetch window) for hot in-memory navigation.
    private var loadedTimeMin: Date?
    private var loadedTimeMax: Date?

    /// Lowercased account email + "|" + calendarId for starred calendars (from `CalendarVisibilityStore`).
    private var starredCalendarKeys: Set<String> = []

    public init() {}

    // MARK: - Public API

    /// Refresh on first load or if stale; otherwise reuse loaded/cached state.
    public func refreshIfNeeded(forceCalendarListCache: Bool = false) async {
        if let lastRefreshAt,
           !events.isEmpty,
           Date().timeIntervalSince(lastRefreshAt) < automaticRefreshInterval {
            await refreshStarredKeysFromStore()
            recomputeDerivedCaches()
            return
        }
        await refreshNow(forceCalendarListCache: forceCalendarListCache)
    }

    /// Immediate refresh; use after account/visibility changes or pull-to-refresh.
    public func refreshNow(forceCalendarListCache: Bool = true) async {
        await performFetch(forceCalendarListCache: forceCalendarListCache)
    }

    /// Legacy entry: full invalidate + fetch (used by Mac/iOS explicit refresh).
    public func refresh() async {
        invalidateAllCaches()
        await performFetch(forceCalendarListCache: true)
    }

    public func invalidateCalendarListCacheAndRefresh() async {
        calendarListCache.removeAll()
        loadedTimeMin = nil
        loadedTimeMax = nil
        await performFetch(forceCalendarListCache: true)
    }

    /// Events filtered for the current mode and `selectedDate` (subset of loaded `events`).
    public func eventsForCurrentMode() -> [GoogleCalendarDisplayEvent] {
        let cal = Calendar.current
        let base: [GoogleCalendarDisplayEvent]
        switch mode {
        case .events:
            base = events
        case .day:
            let s = cal.startOfDay(for: selectedDate)
            guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return applyStarredFilter(events) }
            base = events.filter { $0.start < e && $0.end > s }
        case .week:
            guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else {
                return applyStarredFilter(events)
            }
            let ws = cal.startOfDay(for: weekStart)
            guard let we = cal.date(byAdding: .day, value: 7, to: ws) else { return applyStarredFilter(events) }
            base = events.filter { $0.start < we && $0.end > ws }
        case .month:
            let comps = cal.dateComponents([.year, .month], from: selectedDate)
            guard let monthStart = cal.date(from: comps) else { return applyStarredFilter(events) }
            let ms = cal.startOfDay(for: monthStart)
            guard let monthEnd = cal.date(byAdding: .month, value: 1, to: ms) else { return applyStarredFilter(events) }
            base = events.filter { $0.start < monthEnd && $0.end > ms }
        }
        return applyStarredFilter(base)
    }

    /// Events overlapping a local calendar day (for month grid cells, including leading/trailing days when loaded).
    public func eventsOverlapping(dayContaining anchor: Date) -> [GoogleCalendarDisplayEvent] {
        let cal = Calendar.current
        let s = cal.startOfDay(for: anchor)
        guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return [] }
        let list = events.filter { $0.start < e && $0.end > s }.sorted { $0.start < $1.start }
        return applyStarredFilter(list)
    }

    public func setRestrictToStarredCalendars(_ value: Bool) {
        restrictToStarredCalendars = value
        recomputeDerivedCaches()
    }

    public func refreshStarredKeysFromStore() async {
        let records = await CalendarVisibilityStore.shared.allRecords()
        var keys = Set<String>()
        for r in records {
            let e = r.accountEmail.lowercased()
            for cid in r.starredCalendarIds {
                keys.insert("\(e)|\(cid)")
            }
        }
        starredCalendarKeys = keys
        recomputeDerivedCaches()
    }

    private func applyStarredFilter(_ list: [GoogleCalendarDisplayEvent]) -> [GoogleCalendarDisplayEvent] {
        guard restrictToStarredCalendars else { return list }
        return list.filter { ev in
            let k = "\(ev.accountEmail.lowercased())|\(ev.calendarId)"
            return starredCalendarKeys.contains(k)
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

    /// Call when `selectedDate` or `mode` changes without going through refresh (cache hit path updates UI buckets).
    public func updateDerivedCaches() {
        recomputeDerivedCaches()
    }

    // MARK: - Fetch window (expanded for fewer round-trips)

    /// Window we actually request from the API (may be wider than the visible slice).
    private func fetchTimeWindow() -> (Date, Date) {
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
            guard let start = cal.date(byAdding: .day, value: -7, to: s),
                  let end = cal.date(byAdding: .day, value: 8, to: s) else { return (s, s) }
            return (start, end)
        case .week:
            guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) else {
                return (anchor, anchor)
            }
            let ws = cal.startOfDay(for: weekStart)
            guard let start = cal.date(byAdding: .weekOfYear, value: -1, to: ws),
                  let end = cal.date(byAdding: .weekOfYear, value: 2, to: ws) else { return (ws, ws) }
            return (start, end)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: anchor)
            guard let monthStart = cal.date(from: comps) else { return (anchor, anchor) }
            let ms = cal.startOfDay(for: monthStart)
            // Include prior month so month-grid leading days can show events; extend forward for trailing days.
            guard let start = cal.date(byAdding: .month, value: -1, to: ms),
                  let end = cal.date(byAdding: .month, value: 2, to: ms) else { return (ms, ms) }
            return (start, end)
        }
    }

    private func invalidateAllCaches() {
        calendarListCache.removeAll()
        loadedTimeMin = nil
        loadedTimeMax = nil
    }

    private func performFetch(forceCalendarListCache: Bool) async {
        let fetchID = UUID()
        inFlightRefreshID = fetchID

        let needed = fetchTimeWindow()

        // Range cache: skip network if expanded window already loaded (unless calendar list must reload).
        if !forceCalendarListCache,
           let loadedTimeMin, let loadedTimeMax,
           needed.0 >= loadedTimeMin && needed.1 <= loadedTimeMax,
           inFlightRefreshID == fetchID {
            await refreshStarredKeysFromStore()
            recomputeDerivedCaches()
            lastRefreshAt = Date()
            return
        }

        let hadEvents = !events.isEmpty
        if !hadEvents {
            isLoading = true
        } else {
            isSyncing = true
        }
        errorMessage = nil

        let accounts = GmailAPIService.shared.getAllAccounts()
        if accounts.isEmpty {
            events = []
            errorMessage = "No Google accounts connected."
            loadedTimeMin = nil
            loadedTimeMax = nil
            weekDayBuckets = [:]
            monthDayEventCounts = [:]
            isLoading = false
            isSyncing = false
            lastRefreshAt = Date()
            return
        }

        if forceCalendarListCache {
            calendarListCache.removeAll()
        }

        typealias FetchTask = (account: GmailAccount, calendar: GoogleCalendarListItem)
        var fetchPairs: [FetchTask] = []

        for account in accounts {
            guard inFlightRefreshID == fetchID else { return }
            let enabled = await CalendarVisibilityStore.shared.isAccountEnabledForCalendar(accountEmail: account.email)
            guard enabled else { continue }

            do {
                let list = try await listCalendarsCached(for: account, force: forceCalendarListCache)
                for calItem in list {
                    let vis = await CalendarVisibilityStore.shared.isCalendarVisible(accountEmail: account.email, calendarId: calItem.id)
                    guard vis else { continue }
                    fetchPairs.append((account, calItem))
                }
            } catch {
                if error.isURLSessionCancellation { continue }
                logWarning("Calendar list failed for \(account.email): \(error)", category: "Calendar")
                if errorMessage == nil {
                    errorMessage = "Could not load calendars for \(account.email). Reconnect your account to grant Calendar access."
                }
            }
        }

        guard inFlightRefreshID == fetchID else { return }

        if fetchPairs.isEmpty {
            events = []
            loadedTimeMin = nil
            loadedTimeMax = nil
            weekDayBuckets = [:]
            monthDayEventCounts = [:]
            if errorMessage == nil {
                errorMessage = "No calendars visible. Turn on accounts or calendars in Visibility settings."
            }
            isLoading = false
            isSyncing = false
            lastRefreshAt = Date()
            return
        }

        let timeMin = needed.0
        let timeMax = needed.1

        var merged: [GoogleCalendarDisplayEvent] = []
        let maxConcurrent = 5
        var uncachedPairs: [FetchTask] = []

        for pair in fetchPairs {
            if !forceCalendarListCache,
               let cachedEvents = await CalendarCache.shared.loadEvents(
                accountEmail: pair.account.email,
                calendarId: pair.calendar.id,
                covering: (timeMin, timeMax),
                maxAge: eventWindowCacheTTL
               ) {
                merged.append(contentsOf: cachedEvents)
            } else {
                uncachedPairs.append(pair)
            }
        }

        for chunkStart in stride(from: 0, to: uncachedPairs.count, by: maxConcurrent) {
            guard inFlightRefreshID == fetchID else { return }
            let end = min(chunkStart + maxConcurrent, uncachedPairs.count)
            let chunk = Array(uncachedPairs[chunkStart..<end])
            await withTaskGroup(of: (accountEmail: String, calendarId: String, events: [GoogleCalendarDisplayEvent])?.self) { group in
                for pair in chunk {
                    group.addTask {
                        do {
                            let events = try await GoogleCalendarAPIService.listEvents(
                                for: pair.account,
                                calendarId: pair.calendar.id,
                                calendarTitle: pair.calendar.summary,
                                calendarColorHex: pair.calendar.backgroundColor,
                                timeMin: timeMin,
                                timeMax: timeMax
                            )
                            return (pair.account.email, pair.calendar.id, events)
                        } catch {
                            if !error.isURLSessionCancellation {
                                logWarning(
                                    "Events list failed \(pair.account.email) / \(pair.calendar.id): \(error)",
                                    category: "Calendar"
                                )
                            }
                            return nil
                        }
                    }
                }
                for await part in group {
                    guard let part else { continue }
                    merged.append(contentsOf: part.events)
                    await CalendarCache.shared.saveEvents(
                        part.events,
                        accountEmail: part.accountEmail,
                        calendarId: part.calendarId,
                        timeMin: timeMin,
                        timeMax: timeMax
                    )
                }
            }
        }

        guard inFlightRefreshID == fetchID else { return }

        merged.sort { $0.start < $1.start }
        merged = dedupeEvents(merged)
        events = merged
        loadedTimeMin = timeMin
        loadedTimeMax = timeMax

        if !merged.isEmpty {
            errorMessage = nil
        } else if errorMessage == nil {
            errorMessage = "No events in this range."
        }

        await refreshStarredKeysFromStore()

        recomputeDerivedCaches()

        isLoading = false
        isSyncing = false
        lastRefreshAt = Date()
    }

    private func listCalendarsCached(for account: GmailAccount, force: Bool) async throws -> [GoogleCalendarListItem] {
        let key = account.email.lowercased()
        if !force, let cached = calendarListCache[key], Date().timeIntervalSince(cached.fetchedAt) < calendarListTTL {
            return cached.items
        }
        if !force,
           let persisted = await CalendarCache.shared.loadCalendarList(accountEmail: key, maxAge: calendarListTTL) {
            calendarListCache[key] = (persisted, Date())
            return persisted
        }
        let list = try await GoogleCalendarAPIService.listCalendars(for: account)
        calendarListCache[key] = (list, Date())
        await CalendarCache.shared.saveCalendarList(list, accountEmail: key)
        return list
    }

    private func dedupeEvents(_ items: [GoogleCalendarDisplayEvent]) -> [GoogleCalendarDisplayEvent] {
        var seen = Set<String>()
        var out: [GoogleCalendarDisplayEvent] = []
        for e in items {
            if seen.insert(e.compositeId).inserted {
                out.append(e)
            }
        }
        return out
    }

    private func recomputeDerivedCaches() {
        let cal = Calendar.current
        switch mode {
        case .week:
            let days = GoogleCalendarDerivedMetrics.weekStartDays(containing: selectedDate, calendar: cal)
            let filtered = eventsForCurrentMode()
            weekDayBuckets = GoogleCalendarDerivedMetrics.eventsByDay(days: days, events: filtered, calendar: cal)
            monthDayEventCounts = [:]
        case .month:
            weekDayBuckets = [:]
            let filtered = eventsForCurrentMode()
            monthDayEventCounts = GoogleCalendarDerivedMetrics.monthDayEventCounts(monthContaining: selectedDate, events: filtered, calendar: cal)
        default:
            weekDayBuckets = [:]
            monthDayEventCounts = [:]
        }
    }
}
