import SwiftUI

/// Shared Calendar tab: mode picker, date navigation, week strip, and Events / Day / Week / Month layouts.
public struct GoogleCalendarTabContent: View {
    @ObservedObject public var model: GoogleCalendarViewModel
    public var onOpenVisibility: () -> Void
    public var accentColor: Color
    /// When `false`, hide the built-in segmented mode control (e.g. Mac sidebar or iOS carousel provides modes).
    public var showsBuiltInModePicker: Bool

    public init(
        model: GoogleCalendarViewModel,
        onOpenVisibility: @escaping () -> Void,
        accentColor: Color = .red,
        showsBuiltInModePicker: Bool = true
    ) {
        self.model = model
        self.onOpenVisibility = onOpenVisibility
        self.accentColor = accentColor
        self.showsBuiltInModePicker = showsBuiltInModePicker
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsBuiltInModePicker {
                modePicker
            }
            dateChrome
            weekStrip
            Divider().opacity(0.25)
            content
        }
        .task {
            await model.refresh()
        }
        .onChange(of: model.mode) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: model.selectedDate) { _, _ in
            if model.mode != .events {
                Task { await model.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task { await model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarVisibilityDidChange)) { _ in
            Task { await model.refresh() }
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $model.mode) {
            ForEach(GoogleCalendarViewModel.ViewMode.allCases, id: \.self) { m in
                Text(m.rawValue.capitalized).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var dateChrome: some View {
        HStack {
            Button {
                navigateBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(titleForChrome)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button {
                navigateForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Button(action: onOpenVisibility) {
                Image(systemName: "eye.slash.circle")
            }
            .buttonStyle(.plain)
            .help("Calendar visibility")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var weekStrip: some View {
        let days = daysInWeek(containing: model.selectedDate)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let cal = Calendar.current
                    let isSel = cal.isDate(day, inSameDayAs: model.selectedDate)
                    Button {
                        model.selectedDate = day
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(day.formatted(.dateTime.day()))
                                .font(.subheadline.weight(isSel ? .bold : .regular))
                                .foregroundStyle(isSel ? accentColor : .primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .strokeBorder(isSel ? accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .frame(minWidth: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.events.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if let err = model.errorMessage, model.events.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(err)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Open visibility") {
                    onOpenVisibility()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        } else {
            switch model.mode {
            case .events:
                eventsListView
            case .day:
                dayScheduleView
            case .week:
                weekColumnsView
            case .month:
                monthGridView
            }
        }
    }

    private var eventsListView: some View {
        let filtered = model.eventsForCurrentMode()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        let overdue = filtered.filter { $0.end < startOfToday }
        let today = filtered.filter { $0.start < endOfToday && $0.end > startOfToday }
        let upcoming = filtered.filter { $0.start >= endOfToday }

        return List {
            if !overdue.isEmpty {
                Section("Overdue") {
                    ForEach(overdue) { ev in
                        eventRow(ev, timeUsesAccent: true)
                    }
                }
            }
            if !today.isEmpty {
                Section("Today") {
                    ForEach(today) { ev in
                        eventRow(ev, timeUsesAccent: false)
                    }
                }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { ev in
                        eventRow(ev, timeUsesAccent: false)
                    }
                }
            }
            if overdue.isEmpty && today.isEmpty && upcoming.isEmpty {
                Section {
                    Text("No events in this view.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #endif
    }

    private func eventRow(_ ev: GoogleCalendarDisplayEvent, timeUsesAccent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(ev.title)
                    .font(.body.weight(.medium))
                Text(timeRangeString(ev))
                    .font(.caption)
                    .foregroundStyle(timeUsesAccent ? accentColor : .secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(ev.calendarTitle)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func timeRangeString(_ ev: GoogleCalendarDisplayEvent) -> String {
        if ev.isAllDay {
            return "All day"
        }
        if Calendar.current.isDate(ev.start, inSameDayAs: ev.end) {
            let d = ev.start.formatted(date: .abbreviated, time: .omitted)
            let t0 = ev.start.formatted(date: .omitted, time: .shortened)
            let t1 = ev.end.formatted(date: .omitted, time: .shortened)
            return "\(d) \(t0) – \(t1)"
        }
        return "\(ev.start.formatted(date: .abbreviated, time: .shortened)) – \(ev.end.formatted(date: .abbreviated, time: .shortened))"
    }

    private var dayScheduleView: some View {
        let items = model.eventsForCurrentMode().sorted { $0.start < $1.start }
        return List {
            Section(model.selectedDate.formatted(date: .complete, time: .omitted)) {
                if items.isEmpty {
                    Text("No events this day.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { ev in
                        eventRow(ev, timeUsesAccent: false)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #endif
    }

    @ViewBuilder
    private var weekColumnsView: some View {
        let cal = Calendar.current
        if let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: model.selectedDate)) {
            let ws = cal.startOfDay(for: weekStart)
            let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: ws) }
            let all = model.eventsForCurrentMode()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let start = cal.startOfDay(for: day)
                        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                        let dayEvents = all.filter { $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            Divider()
                            ForEach(dayEvents) { ev in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(2)
                                    Text(shortTime(ev))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 120, alignment: .top)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        } else {
            Text("Unable to compute week.")
                .foregroundStyle(.secondary)
        }
    }

    private func shortTime(_ ev: GoogleCalendarDisplayEvent) -> String {
        if ev.isAllDay { return "All day" }
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        return tf.string(from: ev.start)
    }

    @ViewBuilder
    private var monthGridView: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: model.selectedDate)
        if let monthStart = cal.date(from: comps) {
            let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<29
            let firstWeekday = cal.component(.weekday, from: monthStart)
            let leading = (firstWeekday - cal.firstWeekday + 7) % 7
            let daysInMonth = range.count
            let totalCells = leading + daysInMonth
            let rows = Int(ceil(Double(totalCells) / 7.0))
            let all = model.eventsForCurrentMode()
            VStack(spacing: 4) {
                HStack {
                    ForEach(weekdaySymbols(), id: \.self) { s in
                        Text(s)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let idx = row * 7 + col
                            if idx < leading || idx >= leading + daysInMonth {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                let dayNum = idx - leading + 1
                                let dayDate = cal.date(byAdding: .day, value: dayNum - 1, to: monthStart).map { cal.startOfDay(for: $0) } ?? monthStart
                                let next = cal.date(byAdding: .day, value: 1, to: dayDate) ?? dayDate
                                let count = all.filter { $0.start < next && $0.end > dayDate }.count
                                VStack(spacing: 2) {
                                    Text("\(dayNum)")
                                        .font(.caption.weight(cal.isDateInToday(dayDate) ? .bold : .regular))
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundStyle(accentColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(cal.isDate(dayDate, inSameDayAs: model.selectedDate) ? accentColor.opacity(0.15) : Color.clear)
                                )
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private func weekdaySymbols() -> [String] {
        let cal = Calendar.current
        return cal.shortWeekdaySymbols
    }

    private var titleForChrome: String {
        switch model.mode {
        case .events:
            return model.selectedDate.formatted(.dateTime.month(.wide).year())
        case .day:
            return model.selectedDate.formatted(date: .complete, time: .omitted)
        case .week:
            return model.selectedDate.formatted(.dateTime.month(.wide).year())
        case .month:
            return model.selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func navigateBack() {
        switch model.mode {
        case .events, .day:
            model.navigateDate(byDays: -1)
        case .week:
            model.navigateWeek(by: -1)
        case .month:
            model.navigateMonth(by: -1)
        }
    }

    private func navigateForward() {
        switch model.mode {
        case .events, .day:
            model.navigateDate(byDays: 1)
        case .week:
            model.navigateWeek(by: 1)
        case .month:
            model.navigateMonth(by: 1)
        }
    }

    private func daysInWeek(containing date: Date) -> [Date] {
        let cal = Calendar.current
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) else {
            return []
        }
        let s = cal.startOfDay(for: weekStart)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: s) }
    }
}
