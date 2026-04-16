//
//  MacCalendarMiniMonthView.swift
//  emptymyinboxMacApp
//
//  Compact month grid for the calendar sidebar (today highlighted).
//

import SwiftUI

struct MacCalendarMiniMonthView: View {
    @Binding var selectedDate: Date
    var accentColor: Color

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
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)

                Spacer()

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(weekdayInitials(), id: \.self) { s in
                    Text(s)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacAppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            let grid = monthGridDates()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<42, id: \.self) { idx in
                    if idx < grid.count, let day = grid[idx] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
        }
        .padding(10)
        .background(MacAppTheme.secondaryBackground.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            syncDisplayMonthFromSelection()
        }
        .onChange(of: selectedDate) { _, _ in
            syncDisplayMonthFromSelection()
        }
    }

    private func weekdayInitials() -> [String] {
        let syms = calendar.shortWeekdaySymbols
        return syms.map { String($0.prefix(1)) }
    }

    private func syncDisplayMonthFromSelection() {
        if let m = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) {
            displayMonth = m
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let d = calendar.date(byAdding: .month, value: delta, to: displayMonth) else { return }
        displayMonth = d
    }

    /// Flat array of 42 optional day dates (nil = padding).
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
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let dayNum = calendar.component(.day, from: day)

        return Button {
            selectedDate = calendar.startOfDay(for: day)
        } label: {
            Text("\(dayNum)")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? MacAppTheme.primaryText : MacAppTheme.primaryText.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    Circle()
                        .fill(isToday ? accentColor.opacity(0.35) : (isSelected ? accentColor.opacity(0.15) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .help(day.formatted(date: .complete, time: .omitted))
    }
}
