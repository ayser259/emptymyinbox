import SwiftUI

/// Month grid with weekday headers, week numbers, per-day event lines, and overflow counts.
struct CalendarMonthGridView: View {
    @ObservedObject var model: GoogleCalendarViewModel
    var accentColor: Color

    private let weekColumnWidth: CGFloat = 28
    private let maxEventLines = 4

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        let comps = calendar.dateComponents([.year, .month], from: model.selectedDate)
        Group {
            if let monthStart = calendar.date(from: comps) {
                monthBody(monthStart: monthStart)
            } else {
                Text("Unable to compute month.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monthBody(monthStart: Date) -> some View {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<29
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = range.count
        let totalCells = leading + daysInMonth
        let rows = Int(ceil(Double(totalCells) / 7.0))
        let headers = orderedShortWeekdaySymbols()

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: weekColumnWidth)
                ForEach(0..<7, id: \.self) { i in
                    Text(headers[i].uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)

            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 0) {
                    weekNumberLabel(monthStart: monthStart, leading: leading, row: row, totalCells: totalCells)
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        monthCell(
                            monthStart: monthStart,
                            leading: leading,
                            daysInMonth: daysInMonth,
                            totalCells: totalCells,
                            idx: idx
                        )
                    }
                }
            }
        }
        .padding(10)
    }

    private func orderedShortWeekdaySymbols() -> [String] {
        let s = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { i in s[(first + i) % 7] }
    }

    @ViewBuilder
    private func weekNumberLabel(monthStart: Date, leading: Int, row: Int, totalCells: Int) -> some View {
        let idx = row * 7
        if idx >= totalCells {
            Color.clear.frame(width: weekColumnWidth)
        } else {
            let firstOfRow = calendar.date(byAdding: .day, value: idx - leading, to: monthStart) ?? monthStart
            let w = calendar.component(.weekOfYear, from: firstOfRow)
            Text("\(w)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: weekColumnWidth, alignment: .center)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func monthCell(monthStart: Date, leading: Int, daysInMonth: Int, totalCells: Int, idx: Int) -> some View {
        if idx >= totalCells {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 88)
        } else {
            let cellDate = calendar.date(byAdding: .day, value: idx - leading, to: monthStart).map { calendar.startOfDay(for: $0) } ?? monthStart
            let isInDisplayedMonth = calendar.isDate(cellDate, equalTo: monthStart, toGranularity: .month)
            let dayNum = calendar.component(.day, from: cellDate)
            let isToday = calendar.isDateInToday(cellDate)
            monthDayCell(
                dayNumber: dayNum,
                cellDate: cellDate,
                isInDisplayedMonth: isInDisplayedMonth,
                isToday: isToday
            )
        }
    }

    private func monthDayCell(
        dayNumber: Int,
        cellDate: Date,
        isInDisplayedMonth: Bool,
        isToday: Bool
    ) -> some View {
        let events = model.eventsOverlapping(dayContaining: cellDate)
        let isSel = calendar.isDate(cellDate, inSameDayAs: model.selectedDate)

        return Button {
            model.selectedDate = cellDate
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Spacer(minLength: 0)
                    Text("\(dayNumber)")
                        .font(.caption.weight(isToday ? .bold : .medium))
                        .foregroundStyle(labelColor(isInDisplayedMonth: isInDisplayedMonth, isToday: isToday))
                        .frame(minWidth: 26, minHeight: 26)
                        .background(
                            Circle()
                                .fill(isToday ? accentColor : Color.clear)
                        )
                    Spacer(minLength: 0)
                }

                let visible = Array(events.prefix(maxEventLines))
                let remaining = events.count - visible.count

                ForEach(visible) { ev in
                    monthEventLine(ev)
                }

                if remaining > 0 {
                    Text("\(remaining) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSel ? accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(isInDisplayedMonth ? 1 : 0.45)
    }

    private func labelColor(isInDisplayedMonth: Bool, isToday: Bool) -> Color {
        if isToday { return Color.white }
        return isInDisplayedMonth ? Color.primary : Color.secondary
    }

    @ViewBuilder
    private func monthEventLine(_ ev: GoogleCalendarDisplayEvent) -> some View {
        let dot = calendarDotColor(ev)
        if ev.isAllDay {
            Text(ev.title)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.primary)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(dot.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(dot.opacity(0.85), lineWidth: 1)
                )
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle()
                    .fill(dot)
                    .frame(width: 5, height: 5)
                Text(compactTime(ev.start))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(ev.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func calendarDotColor(_ ev: GoogleCalendarDisplayEvent) -> Color {
        if let hex = ev.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            return Color(hex: hex)
        }
        return accentColor
    }

    private func compactTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date).replacingOccurrences(of: " ", with: "")
    }
}
