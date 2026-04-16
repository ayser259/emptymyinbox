//
//  MacUnifiedDashboardView.swift
//  emptymyinboxMacApp
//
//  Shared “Today” dashboard: mail unread, calendar, open action items.
//

import SwiftUI
import EmptyMyInboxShared

struct MacUnifiedDashboardView: View {
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let snapshot: DashboardDataSnapshot?
    let actionItems: [VaultActionItemRecord]
    let isRefreshing: Bool
    let refreshMessage: String?

    private var calendar: Calendar { Calendar.current }

    /// `DashboardDataSnapshot.emails` is the merged unread-only list from refresh (see `DashboardDataManager`).
    private var unreadAcrossInboxes: Int {
        snapshot?.emails.count ?? 0
    }

    private var openTasks: [VaultActionItemRecord] {
        actionItems.filter { !$0.isDone }
    }

    private var todaysCalendarEvents: [GoogleCalendarDisplayEvent] {
        Self.events(on: Date(), from: calendarModel.events, calendar: calendar)
    }

    /// Events overlapping the given calendar day (not filtered by starred calendars; uses raw `events`).
    static func events(on day: Date, from events: [GoogleCalendarDisplayEvent], calendar: Calendar) -> [GoogleCalendarDisplayEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                todayHeader

                if isRefreshing {
                    HStack {
                        Spacer(minLength: 0)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.caption)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Calendar")
                    MacCalendarMiniMonthView(selectedDate: $calendarModel.selectedDate, accentColor: MacAppTheme.accent)
                }

                unreadSection

                eventsSection

                actionItemsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .navigationTitle("Dashboard")
        .task {
            if calendarModel.events.isEmpty && !calendarModel.isLoading {
                await calendarModel.refresh()
            }
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.title2.weight(.semibold))
                .foregroundStyle(MacAppTheme.primaryText)
            Text(Date().formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(MacAppTheme.secondaryText)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MacAppTheme.secondaryText)
    }

    private var unreadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Mail")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(unreadAcrossInboxes)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacAppTheme.accent)
                Text("unread across inboxes")
                    .font(.body)
                    .foregroundStyle(MacAppTheme.primaryText)
            }
            if let snapshot {
                Text("Last mailbox sync: \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(MacAppTheme.secondaryText.opacity(0.85))
            } else {
                Text("No mailbox data yet — use Refresh in the toolbar.")
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Events today")
            if calendarModel.isLoading && calendarModel.events.isEmpty {
                ProgressView("Loading calendar…")
                    .foregroundStyle(MacAppTheme.secondaryText)
            } else if todaysCalendarEvents.isEmpty {
                Text("No events scheduled for today.")
                    .font(.body)
                    .foregroundStyle(MacAppTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(todaysCalendarEvents) { ev in
                        HStack(alignment: .top, spacing: 10) {
                            Text(ev.isAllDay ? "All day" : ev.start.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MacAppTheme.accent)
                                .frame(width: 72, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.title.isEmpty ? "(No title)" : ev.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(MacAppTheme.primaryText)
                                Text(ev.calendarTitle)
                                    .font(.caption2)
                                    .foregroundStyle(MacAppTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Action items")
            Text("Per-day scheduling is not wired yet — showing all open tasks.")
                .font(.caption)
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.9))

            if openTasks.isEmpty {
                Text("No open tasks.")
                    .font(.body)
                    .foregroundStyle(MacAppTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(openTasks.prefix(12)) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(MacAppTheme.secondaryText)
                                .padding(.top, 2)
                            Text(item.title)
                                .font(.subheadline)
                                .foregroundStyle(MacAppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if openTasks.count > 12 {
                        Text("… and \(openTasks.count - 12) more")
                            .font(.caption)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
    }
}
