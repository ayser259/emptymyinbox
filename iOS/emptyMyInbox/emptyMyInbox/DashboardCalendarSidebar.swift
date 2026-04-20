//
//  DashboardCalendarSidebar.swift
//  emptyMyInbox
//
//  Right column: compact month grid + upcoming events (Homebase-style dashboard).
//

import SwiftUI
import EmptyMyInboxShared

struct DashboardCalendarSidebar: View {
    @ObservedObject var model: GoogleCalendarViewModel

    private var calendar: Calendar { Calendar.current }

    private var upcomingEvents: [GoogleCalendarDisplayEvent] {
        let now = Date()
        guard let horizon = calendar.date(byAdding: .day, value: 21, to: now) else { return [] }
        return model.events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .prefix(14)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
            DashboardMiniMonthCalendar(model: model)

            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                Text("Upcoming")
                    .font(AppTheme.subheadline.weight(.semibold))
                    .primaryText()
                Text("Connected calendars")
                    .font(AppTheme.caption)
                    .secondaryText()

                if model.isLoading && model.events.isEmpty {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingMedium)
                } else if upcomingEvents.isEmpty {
                    Text("No upcoming events in the next few weeks.")
                        .font(AppTheme.caption)
                        .secondaryText()
                        .padding(.vertical, AppTheme.spacingSmall)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                        ForEach(upcomingEvents) { ev in
                            DashboardUpcomingEventRow(event: ev)
                        }
                    }
                }
            }
            .padding(AppTheme.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - Mini month

private struct DashboardMiniMonthCalendar: View {
    @ObservedObject var model: GoogleCalendarViewModel
    @State private var displayMonth: Date = Date()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.caption.weight(.semibold))
                    .primaryText()

                Spacer()

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(Array(weekdayThreeLetterLabels().enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }

            let grid = monthGridDates()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<42, id: \.self) { idx in
                    if idx < grid.count, let day = grid[idx] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            syncDisplayMonthFromSelection()
        }
        .onChange(of: model.selectedDate) { _, _ in
            syncDisplayMonthFromSelection()
        }
    }

    /// Short weekday names truncated to three characters (e.g. Sat Sun Mon …), ordered by `firstWeekday`.
    private func weekdayThreeLetterLabels() -> [String] {
        let syms = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { i in String(syms[(first + i) % 7].prefix(3)) }
    }

    private func syncDisplayMonthFromSelection() {
        if let m = calendar.date(from: calendar.dateComponents([.year, .month], from: model.selectedDate)) {
            displayMonth = m
        }
    }

    private func shiftMonth(_ delta: Int) {
        model.navigateMonth(by: delta)
        syncDisplayMonthFromSelection()
    }

    private func monthGridDates() -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayMonth)
        guard let monthStart = calendar.date(from: comps) else { return Array(repeating: nil, count: 42) }
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<29
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = range.count
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for dayNum in 1...daysInMonth {
            if let d = calendar.date(byAdding: .day, value: dayNum - 1, to: monthStart) {
                cells.append(d)
            }
        }
        while cells.count < 42 {
            cells.append(nil)
        }
        return Array(cells.prefix(42))
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: model.selectedDate)
        let dayNum = calendar.component(.day, from: day)
        let hasEvents = !model.eventsOverlapping(dayContaining: day).isEmpty

        return Button {
            model.selectedDate = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular))
                    .foregroundColor(AppTheme.primaryText.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .background(
                        Circle()
                            .fill(isToday ? AppTheme.accent.opacity(0.35) : (isSelected ? AppTheme.accent.opacity(0.15) : Color.clear))
                    )

                Circle()
                    .fill(hasEvents ? AppTheme.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
    }
}

// MARK: - Event row

private struct DashboardUpcomingEventRow: View {
    let event: GoogleCalendarDisplayEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeRange)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .textCase(.uppercase)

            Text(event.title.isEmpty ? "(No title)" : event.title)
                .font(.subheadline.weight(.medium))
                .primaryText()
                .lineLimit(2)

            Text(event.calendarTitle)
                .font(.caption2)
                .secondaryText()
                .lineLimit(1)
        }
        .padding(AppTheme.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
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
