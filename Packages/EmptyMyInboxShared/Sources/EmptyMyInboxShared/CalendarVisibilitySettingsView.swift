import SwiftUI

/// Cross-platform settings: per-account and per-calendar visibility for the Calendar tab.
public struct CalendarVisibilitySettingsView: View {
    @State private var records: [CalendarAccountVisibilityRecord] = []
    @State private var calendarsByAccount: [String: [GoogleCalendarListItem]] = [:]
    @State private var accountLoadErrors: [String: String] = [:]
    @State private var isLoading = true

    public init() {}

    public var body: some View {
        List {
            if isLoading && records.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if records.isEmpty {
                Text("No connected accounts.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    Section {
                        Toggle(
                            "Show this account in Calendar",
                            isOn: bindingShowAccount(record.accountEmail)
                        )

                        if let err = accountLoadErrors[record.accountEmail] {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        let cals = calendarsByAccount[record.accountEmail] ?? []
                        if cals.isEmpty && accountLoadErrors[record.accountEmail] == nil && !isLoading {
                            Text("No calendars loaded.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(cals) { cal in
                            Toggle(
                                cal.summary,
                                isOn: bindingCalendar(record.accountEmail, cal.id)
                            )
                        }
                    } header: {
                        Text(record.accountEmail)
                    }
                }
            }
        }
        .navigationTitle("Calendar visibility")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        await CalendarVisibilityStore.shared.refreshFromConnectedAccounts()
        let loaded = await CalendarVisibilityStore.shared.allRecords()
        await MainActor.run {
            records = loaded
        }

        var byAccount: [String: [GoogleCalendarListItem]] = [:]
        var errors: [String: String] = [:]

        for record in loaded {
            guard let account = GmailAPIService.shared.getAccount(byEmail: record.accountEmail) else { continue }
            do {
                let list = try await GoogleCalendarAPIService.listCalendars(for: account)
                byAccount[record.accountEmail] = list.sorted { lhs, rhs in
                    if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                    return lhs.summary.localizedCaseInsensitiveCompare(rhs.summary) == .orderedAscending
                }
            } catch {
                errors[record.accountEmail] = error.localizedDescription
            }
        }

        await MainActor.run {
            calendarsByAccount = byAccount
            accountLoadErrors = errors
            isLoading = false
        }
    }

    private func bindingShowAccount(_ email: String) -> Binding<Bool> {
        Binding(
            get: {
                records.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.showAccountInCalendar ?? true
            },
            set: { newValue in
                Task {
                    await CalendarVisibilityStore.shared.setShowAccountInCalendar(accountEmail: email, show: newValue)
                    await refreshRecordsOnly()
                }
            }
        )
    }

    private func bindingCalendar(_ email: String, _ calendarId: String) -> Binding<Bool> {
        Binding(
            get: {
                let rec = records.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })
                return rec?.calendarVisibility[calendarId] ?? true
            },
            set: { newValue in
                Task {
                    await CalendarVisibilityStore.shared.setCalendarVisible(accountEmail: email, calendarId: calendarId, visible: newValue)
                    await refreshRecordsOnly()
                }
            }
        )
    }

    private func refreshRecordsOnly() async {
        let loaded = await CalendarVisibilityStore.shared.allRecords()
        await MainActor.run {
            records = loaded
        }
    }
}
