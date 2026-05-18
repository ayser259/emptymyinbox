import Foundation

public actor CalendarVisibilityStore {
    public static let shared = CalendarVisibilityStore()

    private let fileName = "calendar_visibility.json"
    private var cached: [CalendarAccountVisibilityRecord] = []
    private var didLoad = false

    public func allRecords() async -> [CalendarAccountVisibilityRecord] {
        await ensureLoaded()
        return cached.sorted { $0.accountEmail.lowercased() < $1.accountEmail.lowercased() }
    }

    public func refreshFromConnectedAccounts() async {
        await ensureLoaded()
        let connectedEmails = GmailAPIService.shared.getAllAccounts().map { $0.email }
        var updated = cached.filter { record in
            connectedEmails.contains(where: { $0.caseInsensitiveCompare(record.accountEmail) == .orderedSame })
        }

        for email in connectedEmails {
            if !updated.contains(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame }) {
                updated.append(CalendarAccountVisibilityRecord(accountEmail: email, showAccountInCalendar: true, calendarVisibility: [:], starredCalendarIds: []))
            }
        }

        cached = updated
        await persist()
    }

    public func setShowAccountInCalendar(accountEmail: String, show: Bool) async {
        await ensureLoaded()
        await ensureRecord(for: accountEmail)
        guard let index = indexOf(email: accountEmail) else { return }
        cached[index].showAccountInCalendar = show
        await persist()
        notifyVisibilityChanged()
    }

    public func setCalendarVisible(accountEmail: String, calendarId: String, visible: Bool) async {
        await ensureLoaded()
        await ensureRecord(for: accountEmail)
        guard let index = indexOf(email: accountEmail) else { return }
        cached[index].calendarVisibility[calendarId] = visible
        await persist()
        notifyVisibilityChanged()
    }

    public func setCalendarStarred(accountEmail: String, calendarId: String, starred: Bool) async {
        await ensureLoaded()
        await ensureRecord(for: accountEmail)
        guard let index = indexOf(email: accountEmail) else { return }
        var ids = Set(cached[index].starredCalendarIds)
        if starred {
            ids.insert(calendarId)
        } else {
            ids.remove(calendarId)
        }
        cached[index].starredCalendarIds = ids.sorted()
        await persist()
        notifyVisibilityChanged()
    }

    public func isCalendarStarred(accountEmail: String, calendarId: String) async -> Bool {
        await ensureLoaded()
        guard let record = cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame }) else {
            return false
        }
        return record.starredCalendarIds.contains(calendarId)
    }

    public func isAccountEnabledForCalendar(accountEmail: String) async -> Bool {
        await ensureLoaded()
        return cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame })?.showAccountInCalendar ?? true
    }

    public func isCalendarVisible(accountEmail: String, calendarId: String) async -> Bool {
        await ensureLoaded()
        guard let record = cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame }) else {
            return true
        }
        guard record.showAccountInCalendar else { return false }
        if let explicit = record.calendarVisibility[calendarId] {
            return explicit
        }
        return true
    }

    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    private func indexOf(email: String) -> Int? {
        cached.firstIndex(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })
    }

    /// Ensures `cached` has a row for this account. Without it, mutators would no-op while readers
    /// still default to “visible”, so toggles in the UI snap back (e.g. after a new account connects
    /// before `refreshFromConnectedAccounts` has run).
    private func ensureRecord(for accountEmail: String) async {
        if indexOf(email: accountEmail) != nil { return }
        await refreshFromConnectedAccounts()
        if indexOf(email: accountEmail) != nil { return }
        cached.append(
            CalendarAccountVisibilityRecord(
                accountEmail: accountEmail,
                showAccountInCalendar: true,
                calendarVisibility: [:],
                starredCalendarIds: []
            )
        )
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        cached = await loadFromDisk()
        await refreshFromConnectedAccounts()
    }

    private func loadFromDisk() async -> [CalendarAccountVisibilityRecord] {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([CalendarAccountVisibilityRecord].self, from: data)) ?? []
    }

    private func persist() async {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("Failed to persist calendar visibility: \(error)", category: "Settings")
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func notifyVisibilityChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .calendarVisibilityDidChange, object: nil)
        }
    }
}
