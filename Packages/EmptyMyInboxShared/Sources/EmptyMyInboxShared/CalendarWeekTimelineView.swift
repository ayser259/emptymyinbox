import SwiftUI

/// Seven-day proportional schedule: dual time columns, day headers, all-day row, hour grid, overlap columns, current-time line.
struct CalendarWeekTimelineView: View {
    let weekDays: [Date]
    let eventsByDay: [Date: [GoogleCalendarDisplayEvent]]
    let focusNowRequestToken: Int
    @Binding var secondaryTimeZoneIdentifier: String
    var accentColor: Color

    private let hourHeight: CGFloat = 56
    private let leftColumnWidth: CGFloat = 104
    private let headerRowHeight: CGFloat = 52
    private let minimumEventHeight: CGFloat = 20

    @State private var showAllTimeZones = false

    private var calendar: Calendar { Calendar.current }
    private var primaryTimeZone: TimeZone { TimeZone.current }
    private var secondaryTimeZone: TimeZone {
        TimeZone(identifier: secondaryTimeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    private var totalTimelineHeight: CGFloat { 24 * hourHeight }

    private var referenceDayStart: Date {
        weekDays.first.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: Date())
    }

    /// `weekDayBuckets` keys are start-of-day; normalize so lookups always match the dictionary.
    private func eventsForDay(_ day: Date) -> [GoogleCalendarDisplayEvent] {
        let key = calendar.startOfDay(for: day)
        return eventsByDay[key] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekToolbar
            GeometryReader { geo in
                let avail = max(geo.size.width - leftColumnWidth, 80)
                let minCol: CGFloat = 92
                let natural = avail / 7
                let (columnWidth, weekContentWidth): (CGFloat, CGFloat) = {
                    if natural >= minCol {
                        return (natural, avail)
                    }
                    return (minCol, 7 * minCol)
                }()

                let allDayHeight = allDaySectionHeight()

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            weekPinnedLeftHeader(allDayHeight: allDayHeight)
                            VStack(alignment: .leading, spacing: 0) {
                                weekHeaderRow(columnWidth: columnWidth)
                                    .frame(width: weekContentWidth, height: headerRowHeight)
                                weekAllDayRow(columnWidth: columnWidth, weekWidth: weekContentWidth)
                                    .frame(width: weekContentWidth)
                            }
                        }
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                HStack(alignment: .top, spacing: 0) {
                                    weekTimeRail
                                    weekGrid(
                                        columnWidth: columnWidth,
                                        weekWidth: weekContentWidth
                                    )
                                }
                            }
                            .onAppear { scrollToNowIfNeeded(proxy: proxy) }
                            .onChange(of: weekDays.first?.timeIntervalSince1970 ?? 0) { _, _ in
                                scrollToNowIfNeeded(proxy: proxy)
                            }
                            .onChange(of: focusNowRequestToken) { _, _ in
                                scrollToNowIfNeeded(proxy: proxy)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showAllTimeZones) {
            CalendarTimeZonePickerSheet(selection: $secondaryTimeZoneIdentifier)
        }
    }

    // MARK: - Toolbar

    private var weekToolbar: some View {
        HStack {
            Spacer(minLength: 0)
            Menu {
                ForEach(Self.quickPickTimeZones, id: \.self) { id in
                    Button {
                        secondaryTimeZoneIdentifier = id
                    } label: {
                        if id == secondaryTimeZoneIdentifier {
                            Label(id.replacingOccurrences(of: "_", with: " "), systemImage: "checkmark")
                        } else {
                            Text(id.replacingOccurrences(of: "_", with: " "))
                        }
                    }
                }
                Divider()
                Button("Browse all time zones…") {
                    showAllTimeZones = true
                }
            } label: {
                Label("Second time zone", systemImage: "globe")
                    .font(.caption)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Choose the second time column. The first column follows the device time zone (current local time).")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func weekPinnedLeftHeader(allDayHeight: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Color.clear
                .frame(width: leftColumnWidth, height: headerRowHeight + allDayHeight)
            HStack(spacing: 4) {
                Text(shortTZLabel(primaryTimeZone, at: referenceDayStart))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(shortTZLabel(secondaryTimeZone, at: referenceDayStart))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: leftColumnWidth, height: 20)
            .padding(.bottom, 4)
        }
        .frame(width: leftColumnWidth)
    }

    private var weekTimeRail: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                hourLabelPair(hour: h)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: leftColumnWidth)
    }

    private func weekHeaderRow(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isToday ? accentColor : Color.clear)
                        )
                }
                .frame(width: columnWidth)
            }
        }
    }

    private func allDaySectionHeight() -> CGFloat {
        let counts = weekDays.map { d in eventsForDay(d).filter { $0.isAllDay }.count }
        let maxC = counts.max() ?? 0
        guard maxC > 0 else { return 0 }
        let rows = min(maxC, 4)
        return CGFloat(rows) * 22 + 20
    }

    @ViewBuilder
    private func weekAllDayRow(columnWidth: CGFloat, weekWidth: CGFloat) -> some View {
        let h = allDaySectionHeight()
        if h > 0 {
            HStack(alignment: .top, spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let items = eventsForDay(day).filter { $0.isAllDay }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items.prefix(4)) { ev in
                            HStack(alignment: .top, spacing: 4) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(calendarStripColor(ev))
                                    .frame(width: 3, height: 14)
                                Text(ev.title)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        if items.count > 4 {
                            Text("+\(items.count - 4) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(6)
                    .frame(width: columnWidth, alignment: .leading)
                }
            }
            .frame(width: weekWidth, height: h)
            .background(Color.primary.opacity(0.04))
            .overlay(
                Rectangle()
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func weekGrid(columnWidth: CGFloat, weekWidth: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .topLeading) {
                weekGridCanvas(weekWidth: weekWidth, columnWidth: columnWidth)

                ForEach(Array(weekDays.enumerated()), id: \.element.timeIntervalSince1970) { col, day in
                    let dayStart = calendar.startOfDay(for: day)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
                    let timed = eventsForDay(day).filter { !$0.isAllDay }
                    let segments: [(GoogleCalendarDisplayEvent, Date, Date)] = timed.compactMap { ev in
                        guard let r = CalendarDayTimelineLayout.clippedRange(for: ev, dayStart: dayStart, dayEnd: dayEnd) else {
                            return nil
                        }
                        return (ev, r.0, r.1)
                    }
                    let placed = CalendarDayTimelineLayout.assignLanes(events: segments)
                    ForEach(0..<placed.count, id: \.self) { i in
                        let row = placed[i]
                        let (ev, start, end, lane, laneCount) = row
                        weekEventBlock(
                            event: ev,
                            start: start,
                            end: end,
                            lane: lane,
                            laneCount: laneCount,
                            dayStart: dayStart,
                            columnWidth: columnWidth,
                            columnIndex: col,
                            now: context.date
                        )
                    }
                }

                weekNowIndicator(weekWidth: weekWidth, now: context.date)
                weekNowScrollAnchor(weekWidth: weekWidth, now: context.date)
            }
            .frame(width: weekWidth, height: totalTimelineHeight)
            .clipped()
        }
    }

    private func weekGridCanvas(weekWidth: CGFloat, columnWidth: CGFloat) -> some View {
        Canvas { ctx, size in
            let lineColor = Color.primary.opacity(0.14)
            let vertColor = Color.primary.opacity(0.18)
            for h in 0..<24 {
                let y = CGFloat(h) * hourHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
            for d in 0...7 {
                let x = CGFloat(d) * columnWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(vertColor), lineWidth: d == 0 || d == 7 ? 1 : 0.5)
            }
        }
        .frame(width: weekWidth, height: totalTimelineHeight)
        .allowsHitTesting(false)
    }

    private func weekEventBlock(
        event: GoogleCalendarDisplayEvent,
        start: Date,
        end: Date,
        lane: Int,
        laneCount: Int,
        dayStart: Date,
        columnWidth: CGFloat,
        columnIndex: Int,
        now: Date
    ) -> some View {
        let duration = end.timeIntervalSince(start)
        let rawH = CGFloat(duration / 3600) * hourHeight
        let h = max(rawH, minimumEventHeight)
        let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight
        let strip = calendarStripColor(event)
        let laneW = (columnWidth - 6) / CGFloat(max(laneCount, 1))
        let xBase = CGFloat(columnIndex) * columnWidth + 3
        let x = xBase + CGFloat(lane) * laneW
        let innerW = max(laneW - 2, 24)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(strip)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    Text(weekEventTimeRange(start: start, end: end))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)
                .padding(.vertical, 3)
                Spacer(minLength: 0)
            }
        }
        .frame(width: innerW, height: h, alignment: .topLeading)
        .offset(x: x, y: y)
    }

    private func weekNowIndicator(weekWidth: CGFloat, now: Date) -> some View {
        Group {
            if weekDays.contains(where: { calendar.isDateInToday($0) }) {
                let dayStart = calendar.startOfDay(for: now)
                let y = CGFloat(now.timeIntervalSince(dayStart) / 3600) * hourHeight
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.red.opacity(0.95))
                        .frame(width: weekWidth, height: 1.5)
                        .offset(y: y)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: -3, y: y - 3)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func weekNowScrollAnchor(weekWidth: CGFloat, now: Date) -> some View {
        Group {
            if weekDays.contains(where: { calendar.isDateInToday($0) }) {
                let dayStart = calendar.startOfDay(for: now)
                let y = CGFloat(now.timeIntervalSince(dayStart) / 3600) * hourHeight
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(y, 0))
                    Color.clear
                        .frame(width: weekWidth, height: 1)
                        .id("weekNowScrollAnchor")
                    Spacer(minLength: 0)
                }
                .frame(width: weekWidth, height: totalTimelineHeight, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }

    private func hourLabelPair(hour h: Int) -> some View {
        let instant = calendar.date(byAdding: .hour, value: h, to: referenceDayStart) ?? referenceDayStart
        let p = timeString(instant, timeZone: primaryTimeZone)
        let s = timeString(instant, timeZone: secondaryTimeZone)
        return HStack(spacing: 4) {
            Text(p)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(s)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.trailing, 6)
    }

    private func timeString(_ date: Date, timeZone tz: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private func shortTZLabel(_ tz: TimeZone, at date: Date) -> String {
        if let abbr = tz.abbreviation(for: date) { return abbr }
        let s = tz.secondsFromGMT(for: date)
        let h = s / 3600
        let m = abs(s % 3600) / 60
        if m == 0 { return String(format: "GMT%+d", h) }
        return String(format: "GMT%+d:%02d", h, m)
    }

    private func weekEventTimeRange(start: Date, end: Date) -> String {
        let t0 = timeString(start, timeZone: primaryTimeZone)
        let t1 = timeString(end, timeZone: primaryTimeZone)
        return "\(t0) – \(t1)"
    }

    private func calendarStripColor(_ ev: GoogleCalendarDisplayEvent) -> Color {
        if let hex = ev.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            return Color(hex: hex)
        }
        return accentColor
    }

    private func scrollToNowIfNeeded(proxy: ScrollViewProxy) {
        guard weekDays.contains(where: { calendar.isDateInToday($0) }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("weekNowScrollAnchor", anchor: UnitPoint(x: 0.5, y: 0.5))
            }
        }
    }

    private static let quickPickTimeZones: [String] = [
        "UTC",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "America/Toronto",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Asia/Dubai",
        "Australia/Sydney",
        "Pacific/Auckland",
    ]
}
