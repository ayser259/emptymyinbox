import SwiftUI
#if os(iOS)
import UIKit
#endif

private enum EventTimelineRole {
    case past
    case current
    case next
    case upcoming
}

private struct CalendarDaySection: Identifiable {
    let id: TimeInterval
    let dayStart: Date
    let events: [GoogleCalendarDisplayEvent]

    init(dayStart: Date, events: [GoogleCalendarDisplayEvent]) {
        self.dayStart = dayStart
        self.events = events
        self.id = dayStart.timeIntervalSince1970
    }
}

/// Shared Calendar tab: segmented mode picker at the bottom when enabled; Day/Week/Month get date chrome + week strip; Events mode is timeline-only (no week/date chrome) with visibility + sync bar. Day and Week use proportional timelines with dual time zones; Month uses a dense agenda-style grid.
public struct GoogleCalendarTabContent: View {
    @ObservedObject public var model: GoogleCalendarViewModel
    public var onOpenVisibility: () -> Void
    public var accentColor: Color
    /// When `false`, hide the built-in segmented mode control (e.g. Mac sidebar or iOS carousel provides modes).
    public var showsBuiltInModePicker: Bool

    /// Secondary time column for Day / Week schedules (paired with `TimeZone.current`).
    @AppStorage("calendar.dayView.secondaryTimeZoneIdentifier") private var dayViewSecondaryTimeZoneIdentifier = "UTC"
    @State private var focusNowRequestToken = 0

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
            if model.mode == .events {
                eventsModeTopBar
                Divider().opacity(0.25)
            } else {
                dateChrome
                Divider().opacity(0.25)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsBuiltInModePicker {
                Divider().opacity(0.25)
                modePicker
            }
        }
        .task {
            await model.refreshIfNeeded(forceCalendarListCache: false)
        }
        .onChange(of: model.mode) { _, newMode in
#if os(iOS)
            selectionHaptic()
#endif
            if newMode == .day || newMode == .week {
                model.selectedDate = Date()
            }
            model.updateDerivedCaches()
            if newMode == .day || newMode == .week {
                focusNowRequestToken += 1
            }
        }
        .onChange(of: model.selectedDate) { _, _ in
            model.updateDerivedCaches()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task { await model.invalidateCalendarListCacheAndRefresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarVisibilityDidChange)) { _ in
            Task { await model.invalidateCalendarListCacheAndRefresh() }
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

    /// Events timeline: no week strip or month/year chrome — keep visibility + sync only.
    private var eventsModeTopBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if model.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Button(action: onOpenVisibility) {
                Image(systemName: "eye.slash.circle")
            }
            .buttonStyle(.plain)
            .help("Calendar visibility")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: model.isSyncing)
    }

    private var dateChrome: some View {
        HStack(spacing: 8) {
            Button {
                navigateBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(titleForChrome)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if model.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Spacer(minLength: 8)

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
        .animation(.easeInOut(duration: 0.2), value: model.isSyncing)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.events.isEmpty {
            Spacer(minLength: 0)
            calendarLoadingPlaceholder
            Spacer(minLength: 0)
        } else if let err = model.errorMessage, model.events.isEmpty {
            Spacer(minLength: 0)
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
            Spacer(minLength: 0)
        } else {
            Group {
                switch model.mode {
                case .events:
                    eventsListView
                case .day:
                    dayScheduleView
                case .week:
                    weekScheduleView
                case .month:
                    monthScheduleView
                }
            }
            .id(model.mode)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeInOut(duration: 0.22), value: model.mode)
        }
    }

    private var calendarLoadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView("Loading calendar…")
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 56)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var eventsListView: some View {
        eventsTimelineView
    }

    /// Chronological sections by calendar day; past days above, today and future below. Scroll lands on today.
    private var eventsTimelineView: some View {
        let events = model.eventsForCurrentMode().sorted { $0.start < $1.start }
        let sections = groupedEventsByDay(events)
        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let nextId = nextUpcomingEventCompositeId(in: events, now: now)
        let scrollTargetId = eventsTimelineScrollTargetId(sections: sections, todayStart: todayStart, calendar: cal)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if sections.isEmpty {
                        Text("No events in this view.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(sections) { section in
                            Section {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(section.events.enumerated()), id: \.element.id) { idx, ev in
                                        let role = eventTimelineRole(for: ev, now: now, nextCompositeId: nextId)
                                        eventTimelineRow(
                                            ev,
                                            role: role,
                                            isFirstInDay: idx == 0,
                                            isLastInDay: idx == section.events.count - 1
                                        )
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)
                            } header: {
                                eventsDaySectionHeader(dayStart: section.dayStart, calendar: cal)
                            }
                            .id(section.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                scrollEventsTimelineToToday(proxy: proxy, targetId: scrollTargetId)
            }
            .onChange(of: model.events.count) { _, _ in
                scrollEventsTimelineToToday(proxy: proxy, targetId: scrollTargetId)
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .refreshable {
            await model.refresh()
        }
        #endif
    }

    private func scrollEventsTimelineToToday(proxy: ScrollViewProxy, targetId: TimeInterval?) {
        guard let targetId else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.35)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
        }
    }

    private func eventsTimelineScrollTargetId(
        sections: [CalendarDaySection],
        todayStart: Date,
        calendar: Calendar
    ) -> TimeInterval? {
        guard !sections.isEmpty else { return nil }
        if let s = sections.first(where: { calendar.isDate($0.dayStart, inSameDayAs: Date()) }) {
            return s.id
        }
        if let s = sections.first(where: { $0.dayStart >= todayStart }) {
            return s.id
        }
        return sections.last?.id
    }

    private func groupedEventsByDay(_ events: [GoogleCalendarDisplayEvent]) -> [CalendarDaySection] {
        let cal = Calendar.current
        var map: [Date: [GoogleCalendarDisplayEvent]] = [:]
        for ev in events {
            let day = cal.startOfDay(for: ev.start)
            map[day, default: []].append(ev)
        }
        let days = map.keys.sorted()
        return days.map { d in
            let list = (map[d] ?? []).sorted { $0.start < $1.start }
            return CalendarDaySection(dayStart: d, events: list)
        }
    }

    private func nextUpcomingEventCompositeId(in events: [GoogleCalendarDisplayEvent], now: Date) -> String? {
        events.sorted { $0.start < $1.start }.first(where: { $0.start > now })?.compositeId
    }

    private func eventTimelineRole(for ev: GoogleCalendarDisplayEvent, now: Date, nextCompositeId: String?) -> EventTimelineRole {
        if ev.end <= now { return .past }
        if ev.start <= now && ev.end > now { return .current }
        if ev.compositeId == nextCompositeId { return .next }
        return .upcoming
    }

    private func eventsDaySectionHeader(dayStart: Date, calendar: Calendar) -> some View {
        let label = eventsSectionHeaderLabel(dayStart: dayStart, calendar: calendar)

        return HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
    }

    /// "Today — Apr 15, 2026" style; other days use full weekday + date.
    private func eventsSectionHeaderLabel(dayStart: Date, calendar: Calendar) -> String {
        let now = Date()
        let todaySod = calendar.startOfDay(for: now)
        let datePart = eventsSectionHeaderDatePart(dayStart: dayStart, calendar: calendar, referenceNow: now)

        if calendar.isDate(dayStart, inSameDayAs: todaySod) {
            return "Today — \(datePart)"
        }
        if let y = calendar.date(byAdding: .day, value: -1, to: todaySod),
           calendar.isDate(dayStart, inSameDayAs: y) {
            return "Yesterday — \(datePart)"
        }
        if let t = calendar.date(byAdding: .day, value: 1, to: todaySod),
           calendar.isDate(dayStart, inSameDayAs: t) {
            return "Tomorrow — \(datePart)"
        }
        let y = calendar.component(.year, from: dayStart)
        let ry = calendar.component(.year, from: now)
        if y == ry {
            return dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private func eventsSectionHeaderDatePart(dayStart: Date, calendar: Calendar, referenceNow: Date) -> String {
        let y = calendar.component(.year, from: dayStart)
        let ry = calendar.component(.year, from: referenceNow)
        if y == ry {
            return dayStart.formatted(.dateTime.month(.abbreviated).day())
        }
        return dayStart.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func eventTimelineRow(
        _ ev: GoogleCalendarDisplayEvent,
        role: EventTimelineRole,
        isFirstInDay: Bool,
        isLastInDay: Bool
    ) -> some View {
        let lineColor = Color.primary.opacity(0.22)
        let (titleStyle, timeStyle, metaStyle, dotFill, dotStroke) = eventTimelinePalette(for: role)
        let splash = calendarSplashColor(ev, role: role)

        return HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(splash)
                .frame(width: 4)
                .frame(minHeight: 44)
                .padding(.trailing, 8)

            VStack(spacing: 0) {
                if !isFirstInDay {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2, height: 6)
                }
                Circle()
                    .fill(dotFill)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .strokeBorder(dotStroke, lineWidth: 1)
                    )
                if !isLastInDay {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2, height: 36)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(ev.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeRangeString(ev))
                    .font(.caption)
                    .foregroundStyle(timeStyle)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(ev.calendarTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(metaStyle)
            }
            .padding(.leading, 10)
            .padding(.bottom, isLastInDay ? 10 : 6)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func eventTimelinePalette(for role: EventTimelineRole) -> (Color, Color, Color, Color, Color) {
        let yellow = Color(red: 0.98, green: 0.88, blue: 0.35)
        let dim = Color.primary.opacity(0.48)
        let white = Color.primary
        let metaDim = Color.primary.opacity(0.4)
        let metaBright = Color.primary.opacity(0.65)

        switch role {
        case .past:
            return (dim, dim.opacity(0.9), metaDim, Color.primary.opacity(0.35), Color.primary.opacity(0.2))
        case .current, .next:
            return (yellow, yellow.opacity(0.92), metaBright, yellow, yellow.opacity(0.55))
        case .upcoming:
            return (white, white.opacity(0.75), Color.primary.opacity(0.55), white.opacity(0.95), Color.primary.opacity(0.35))
        }
    }

    /// Google Calendar `backgroundColor` hex, softened for past/upcoming emphasis.
    private func calendarSplashColor(_ ev: GoogleCalendarDisplayEvent, role: EventTimelineRole) -> Color {
        let base: Color
        if let hex = ev.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            base = Color(hex: hex)
        } else {
            base = accentColor
        }
        switch role {
        case .past: return base.opacity(0.35)
        case .current, .next: return base.opacity(0.95)
        case .upcoming: return base.opacity(0.88)
        }
    }

    /// Day / week rows without timeline role — neutral splash strength.
    private func calendarSplashColor(_ ev: GoogleCalendarDisplayEvent) -> Color {
        if let hex = ev.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            return Color(hex: hex).opacity(0.88)
        }
        return accentColor.opacity(0.55)
    }

    private func eventRow(_ ev: GoogleCalendarDisplayEvent, timeUsesAccent: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(calendarSplashColor(ev))
                .frame(width: 4)
                .frame(minHeight: 36)
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(ev.title)
                    .font(.body.weight(.medium))
                Text(timeRangeString(ev))
                    .font(.caption)
                    .foregroundStyle(timeUsesAccent ? accentColor : .secondary)
            }
            Spacer(minLength: 8)
            Text(ev.calendarTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
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
        let allDay = items.filter { $0.isAllDay }
        let timed = items.filter { !$0.isAllDay }
        return Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("No events this day.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarDayTimelineView(
                    day: model.selectedDate,
                    allDayEvents: allDay,
                    timedEvents: timed,
                    focusNowRequestToken: focusNowRequestToken,
                    secondaryTimeZoneIdentifier: $dayViewSecondaryTimeZoneIdentifier,
                    accentColor: accentColor
                )
            }
        }
        #if os(iOS)
        .refreshable {
            await model.refresh()
        }
        #endif
    }

    @ViewBuilder
    private var weekColumnsView: some View {
        let cal = Calendar.current
        let days = GoogleCalendarDerivedMetrics.weekStartDays(containing: model.selectedDate, calendar: cal)
        if days.count == 7 {
            CalendarWeekTimelineView(
                weekDays: days,
                eventsByDay: model.weekDayBuckets,
                focusNowRequestToken: focusNowRequestToken,
                secondaryTimeZoneIdentifier: $dayViewSecondaryTimeZoneIdentifier,
                accentColor: accentColor
            )
        } else {
            Text("Unable to compute week.")
                .foregroundStyle(.secondary)
        }
    }

    private var weekScheduleView: some View {
        weekColumnsView
#if os(iOS)
        .refreshable {
            await model.refresh()
        }
#endif
    }

    private var monthScheduleView: some View {
        CalendarMonthGridView(model: model, accentColor: accentColor)
#if os(iOS)
        .refreshable {
            await model.refresh()
        }
#endif
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
        case .events:
            model.navigateWeek(by: -1)
        case .day:
            model.navigateDate(byDays: -1)
        case .week:
            model.navigateWeek(by: -1)
        case .month:
            model.navigateMonth(by: -1)
        }
    }

    private func navigateForward() {
        switch model.mode {
        case .events:
            model.navigateWeek(by: 1)
        case .day:
            model.navigateDate(byDays: 1)
        case .week:
            model.navigateWeek(by: 1)
        case .month:
            model.navigateMonth(by: 1)
        }
    }

#if os(iOS)
    private func selectionHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
#endif
}
