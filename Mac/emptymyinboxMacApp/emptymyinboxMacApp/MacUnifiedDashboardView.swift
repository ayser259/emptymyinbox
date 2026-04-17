//
//  MacUnifiedDashboardView.swift
//  emptymyinboxMacApp
//
//  Dashboard: inbox feed by account (left) + mini calendar & upcoming events (right).
//

import SwiftUI
import EmptyMyInboxShared

struct MacUnifiedDashboardView: View {
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let snapshot: DashboardDataSnapshot?
    let actionItems: [VaultActionItemRecord]
    let isRefreshing: Bool
    let refreshMessage: String?
    /// When set (Mail tab), opens that account’s mailbox in the middle column.
    var onOpenMailbox: ((String) -> Void)?
    /// When set (Mail tab), switches to Catch Up.
    var onOpenCatchUp: (() -> Void)?

    private var calendar: Calendar { Calendar.current }

    private var openTasks: [VaultActionItemRecord] {
        actionItems.filter { !$0.isDone }
    }

    private var upcomingEvents: [GoogleCalendarDisplayEvent] {
        let now = Date()
        guard let horizon = calendar.date(byAdding: .day, value: 21, to: now) else { return [] }
        return calendarModel.events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .prefix(16)
            .map { $0 }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            twoColumnLayout
            stackedLayout
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

    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            leftFeedColumn
                .frame(maxWidth: .infinity)
            rightCalendarColumn
                .frame(width: 300)
        }
        .padding(24)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            leftFeedColumn
            rightCalendarColumn
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var leftFeedColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                if let snapshot, !snapshot.accounts.isEmpty {
                    sectionTitle("Inbox feed")
                    Text("By account")
                        .font(.caption)
                        .foregroundStyle(MacAppTheme.secondaryText.opacity(0.9))

                    accountSections(snapshot: snapshot)
                } else {
                    Text("No accounts loaded — refresh your mailbox.")
                        .font(.body)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }

                actionItemsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rightCalendarColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Calendar")
                MacCalendarMiniMonthView(
                    selectedDate: $calendarModel.selectedDate,
                    accentColor: MacAppTheme.accent,
                    hasEventOnDay: { day in
                        !calendarModel.eventsOverlapping(dayContaining: day).isEmpty
                    }
                )

                sectionTitle("Upcoming")
                Group {
                    if calendarModel.isLoading && calendarModel.events.isEmpty {
                        ProgressView("Loading calendar…")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else if upcomingEvents.isEmpty {
                        Text("No upcoming events in the next few weeks.")
                            .font(.body)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(upcomingEvents) { ev in
                                MacDashboardUpcomingEventRow(event: ev)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(MacAppTheme.secondaryBackground.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func accountSections(snapshot: DashboardDataSnapshot) -> some View {
        ForEach(snapshot.accounts, id: \.id) { account in
            accountRow(account: account, snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func accountRow(account: EmailAccount, snapshot: DashboardDataSnapshot) -> some View {
        MacDashboardAccountSection(
            account: account,
            unread: unreadCount(for: account, snapshot: snapshot),
            starred: starredCount(for: account, snapshot: snapshot),
            total: totalCount(for: account, snapshot: snapshot),
            unreadSenderCount: unreadSenderCount(for: account, snapshot: snapshot),
            onViewMore: onOpenMailbox.map { open in { open(account.email) } },
            onCatchUp: (onOpenCatchUp != nil && unreadCount(for: account, snapshot: snapshot) > 0) ? onOpenCatchUp : nil
        )
    }

    private func unreadCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.allEmails.filter {
            $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred
        }.count
    }

    private func starredCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.starredEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }

    private func totalCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }

    private func unreadSenderCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        let unread = snapshot.allEmails.filter {
            $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred
        }
        return Set(unread.map(\.sender)).count
    }
}

// MARK: - Account section

private struct MacDashboardAccountSection: View {
    let account: EmailAccount
    let unread: Int
    let starred: Int
    let total: Int
    let unreadSenderCount: Int
    var onViewMore: (() -> Void)?
    var onCatchUp: (() -> Void)?

    private var summaryLine: String {
        ["\(unread) unread", "\(starred) starred", "\(total) total"].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(account.email)
                .font(.body.weight(.semibold))
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(1)

            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(MacAppTheme.secondaryText)

            if unreadSenderCount > 0 {
                Text("\(unreadSenderCount) senders with unread")
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText.opacity(0.85))
            }

            HStack(spacing: 12) {
                if let onViewMore {
                    Button("View more") {
                        onViewMore()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacAppTheme.accent)
                    .controlSize(.small)
                }

                if let onCatchUp, unread > 0 {
                    Button {
                        onCatchUp()
                    } label: {
                        Label("Catch up", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
    }
}

// MARK: - Upcoming row

private struct MacDashboardUpcomingEventRow: View {
    let event: GoogleCalendarDisplayEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeRange)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacAppTheme.accent)

            Text(event.title.isEmpty ? "(No title)" : event.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(2)

            Text(event.calendarTitle)
                .font(.caption2)
                .foregroundStyle(MacAppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var timeRange: String {
        if event.isAllDay {
            return event.start.formatted(date: .abbreviated, time: .omitted) + " · All day"
        }
        let start = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
