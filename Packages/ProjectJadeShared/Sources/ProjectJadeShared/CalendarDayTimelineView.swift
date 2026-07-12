import SwiftUI

/// Proportional day schedule: dual time columns, hour grid, current-time line, lane layout for overlaps.
struct CalendarDayTimelineView: View {
    let day: Date
    let allDayEvents: [GoogleCalendarDisplayEvent]
    let timedEvents: [GoogleCalendarDisplayEvent]
    let focusNowRequestToken: Int
    @Binding var secondaryTimeZoneIdentifier: String
    var accentColor: Color

    private let hourHeight: CGFloat = 56
    private let leftColumnWidth: CGFloat = 104
    private let minimumEventHeight: CGFloat = 22

    @State private var showAllTimeZones = false

    private var calendar: Calendar { Calendar.current }
    private var primaryTimeZone: TimeZone { TimeZone.current }
    private var secondaryTimeZone: TimeZone {
        TimeZone(identifier: secondaryTimeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    private var dayStart: Date { calendar.startOfDay(for: day) }
    private var dayEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    }

    private var totalTimelineHeight: CGFloat { 24 * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayToolbar
            if !allDayEvents.isEmpty {
                allDayStrip
            }
            GeometryReader { outerGeo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            timeLabelsColumn
                            timelineContent(width: max(outerGeo.size.width - leftColumnWidth, 200))
                        }
                        .frame(minHeight: totalTimelineHeight)
                    }
                    .onAppear {
                        scrollToNowIfNeeded(proxy: proxy)
                    }
                    .onChange(of: day) { _, _ in
                        scrollToNowIfNeeded(proxy: proxy)
                    }
                    .onChange(of: focusNowRequestToken) { _, _ in
                        scrollToNowIfNeeded(proxy: proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showAllTimeZones) {
            CalendarTimeZonePickerSheet(selection: $secondaryTimeZoneIdentifier)
        }
    }

    private var dayToolbar: some View {
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

    private var allDayStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(allDayEvents) { ev in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(calendarStripColor(ev))
                        .frame(width: 4, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.title)
                            .font(.subheadline.weight(.medium))
                        Text(ev.calendarTitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var timeLabelsColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text(shortTZLabel(primaryTimeZone, at: dayStart))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(shortTZLabel(secondaryTimeZone, at: dayStart))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: leftColumnWidth, height: 20)
            .padding(.bottom, 4)

            ForEach(0..<24, id: \.self) { h in
                hourLabelPair(hour: h)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: leftColumnWidth)
    }

    private func hourLabelPair(hour h: Int) -> some View {
        let instant = calendar.date(byAdding: .hour, value: h, to: dayStart) ?? dayStart
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

    private func timelineContent(width: CGFloat) -> some View {
        let segments = timedSegments()
        let placed = CalendarDayTimelineLayout.assignLanes(events: segments)

        return TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .topLeading) {
                hourGridLines(width: width)

                ForEach(0..<placed.count, id: \.self) { i in
                    let row = placed[i]
                    let (ev, start, end, lane, laneCount) = row
                    dayEventBlock(
                        event: ev,
                        start: start,
                        end: end,
                        lane: lane,
                        laneCount: laneCount,
                        width: width,
                        now: context.date
                    )
                }

                nowIndicatorIfToday(width: width, now: context.date)
                nowScrollAnchorIfToday(width: width, now: context.date)
            }
            .frame(width: width, height: totalTimelineHeight)
            .clipped()
        }
    }

    private func timedSegments() -> [(GoogleCalendarDisplayEvent, Date, Date)] {
        var out: [(GoogleCalendarDisplayEvent, Date, Date)] = []
        for ev in timedEvents {
            guard let range = CalendarDayTimelineLayout.clippedRange(for: ev, dayStart: dayStart, dayEnd: dayEnd) else {
                continue
            }
            out.append((ev, range.0, range.1))
        }
        return out
    }

    private func hourGridLines(width: CGFloat) -> some View {
        Canvas { ctx, size in
            let lineColor = Color.primary.opacity(0.14)
            for h in 0..<24 {
                let y = CGFloat(h) * hourHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
        }
        .frame(width: width, height: totalTimelineHeight)
        .allowsHitTesting(false)
    }

    private func dayEventBlock(
        event: GoogleCalendarDisplayEvent,
        start: Date,
        end: Date,
        lane: Int,
        laneCount: Int,
        width: CGFloat,
        now: Date
    ) -> some View {
        let duration = end.timeIntervalSince(start)
        let rawH = CGFloat(duration / 3600) * hourHeight
        let h = max(rawH, minimumEventHeight)
        let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight
        let strip = calendarStripColor(event)
        let colW = width / CGFloat(max(laneCount, 1))
        let x = CGFloat(lane) * colW + 2
        let innerW = max(colW - 4, 40)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(strip)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Text(dayEventTimeRange(start: start, end: end))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
        }
        .frame(width: innerW, height: h, alignment: .topLeading)
        .offset(x: x, y: y)
    }

    private func nowIndicatorIfToday(width: CGFloat, now: Date) -> some View {
        Group {
            if calendar.isDate(day, inSameDayAs: now) {
                let y = CGFloat(now.timeIntervalSince(dayStart) / 3600) * hourHeight
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.red.opacity(0.95))
                        .frame(width: width, height: 1.5)
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

    private func nowScrollAnchorIfToday(width: CGFloat, now: Date) -> some View {
        Group {
            if calendar.isDate(day, inSameDayAs: now) {
                let y = CGFloat(now.timeIntervalSince(dayStart) / 3600) * hourHeight
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(y, 0))
                    Color.clear
                        .frame(width: width, height: 1)
                        .id("dayNowScrollAnchor")
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: totalTimelineHeight, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }

    private func scrollToNowIfNeeded(proxy: ScrollViewProxy) {
        guard calendar.isDateInToday(day) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("dayNowScrollAnchor", anchor: UnitPoint(x: 0.5, y: 0.5))
            }
        }
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

    private func dayEventTimeRange(start: Date, end: Date) -> String {
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
