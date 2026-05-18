//
//  MacInboxMetricsCard.swift
//  emptymyinboxMacApp
//
//  Dashboard card: 14-day inbox metrics chart with weekday comparison toggle.
//

import SwiftUI
import EmptyMyInboxShared

private enum MetricsChartMode: String, CaseIterable, Identifiable {
    case trailing14 = "Last 14 days"
    case weekday = "By weekday"

    var id: String { rawValue }
}

struct MacInboxMetricsCard: View {
    @State private var chartMode: MetricsChartMode = .trailing14
    @State private var selectedMetric: InboxMetricsChartMetric = .received
    @State private var dayPoints: [InboxMetricsDayPoint] = []
    @State private var weekdayBuckets: [InboxMetricsWeekdayBucket] = []
    @State private var isLoading = true

    var body: some View {
        MacDashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                MacCardHeader(icon: "chart.bar.fill", title: "INBOX ACTIVITY")

                Picker("Range", selection: $chartMode) {
                    ForEach(MetricsChartMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(InboxMetricsChartMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider().opacity(0.15)

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if chartMode == .trailing14 {
                        trailingChart
                    } else {
                        weekdayChart
                    }
                }
                .animation(.easeOut(duration: 0.2), value: chartMode)
                .animation(.easeOut(duration: 0.2), value: selectedMetric)
            }
        }
        .task { await reload() }
        .onChange(of: chartMode) { _, _ in Task { await reload() } }
        .onChange(of: selectedMetric) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .inboxMetricsDidUpdate)) { _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var trailingChart: some View {
        let values = dayPoints.map { pointValue($0) }
        let hasData = values.contains { $0 > 0 }

        if hasData {
            VStack(alignment: .leading, spacing: 10) {
                MacSimpleBarChart(
                    values: values,
                    labels: dayPoints.map(\.label),
                    accent: MacAppTheme.accent
                )
                .frame(height: 140)

                trailingTotals
            }
        } else {
            metricsEmptyState
        }
    }

    @ViewBuilder
    private var weekdayChart: some View {
        let hasData = weekdayBuckets.contains { $0.thisWeekValue > 0 || $0.previousWeekValue > 0 }

        if hasData {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    legendDot(color: MacAppTheme.accent, label: "This week")
                    legendDot(color: MacAppTheme.secondaryText.opacity(0.45), label: "Previous week")
                }
                .font(.caption2)
                .foregroundStyle(MacAppTheme.secondaryText)

                MacWeekdayComparisonChart(
                    buckets: weekdayBuckets,
                    thisWeekColor: MacAppTheme.accent,
                    previousWeekColor: MacAppTheme.secondaryText.opacity(0.35)
                )
                .frame(height: 140)

                weekdayDeltaSummary
            }
        } else {
            metricsEmptyState
        }
    }

    private var metricsEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 24))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.35))
            Text("No activity yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.6))
            Text("Refresh your mailbox or complete a catch-up session.")
                .font(.caption)
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var trailingTotals: some View {
        let received = dayPoints.reduce(0) { $0 + $1.emailsReceived }
        let reviewed = dayPoints.reduce(0) { $0 + $1.emailsReviewed }
        let minutes = dayPoints.reduce(0.0) { $0 + $1.reviewMinutes }

        return HStack(spacing: 16) {
            totalPill(label: "Received", value: "\(received)")
            totalPill(label: "Reviewed", value: "\(reviewed)")
            totalPill(label: "Review time", value: formatMinutes(minutes))
        }
        .font(.caption)
    }

    private var weekdayDeltaSummary: some View {
        let totalThis = weekdayBuckets.reduce(0.0) { $0 + $1.thisWeekValue }
        let totalPrev = weekdayBuckets.reduce(0.0) { $0 + $1.previousWeekValue }
        let delta = totalThis - totalPrev
        let sign = delta >= 0 ? "+" : ""
        let formatted = selectedMetric == .reviewTime
            ? formatMinutes(delta)
            : "\(Int(delta.rounded()))"

        return Text("Week over week: \(sign)\(formatted) \(selectedMetric.unitLabel)")
            .font(.caption)
            .foregroundStyle(MacAppTheme.secondaryText)
    }

    private func totalPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.7))
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(MacAppTheme.primaryText)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    private func pointValue(_ point: InboxMetricsDayPoint) -> Double {
        switch selectedMetric {
        case .received: return Double(point.emailsReceived)
        case .reviewed: return Double(point.emailsReviewed)
        case .reviewTime: return point.reviewMinutes
        }
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private func reload() async {
        isLoading = true
        let points = await InboxMetricsStore.shared.last14DayPoints()
        let buckets = await InboxMetricsStore.shared.weekdayBuckets(metric: selectedMetric)
        await MainActor.run {
            dayPoints = points
            weekdayBuckets = buckets
            isLoading = false
        }
    }
}

// MARK: - Simple bar chart

private struct MacSimpleBarChart: View {
    let values: [Double]
    let labels: [String]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(values.max() ?? 1, 1)
            let barWidth = max(4, (geo.size.width - CGFloat(values.count - 1) * 4) / CGFloat(max(values.count, 1)))

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(value > 0 ? 0.85 : 0.15))
                            .frame(
                                width: barWidth,
                                height: max(4, CGFloat(value / maxVal) * (geo.size.height - 22))
                            )

                        if index == 0 || index == values.count - 1 || index == values.count / 2 {
                            Text(labels[index])
                                .font(.system(size: 8))
                                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.55))
                                .lineLimit(1)
                                .frame(width: barWidth + 8)
                        } else {
                            Color.clear.frame(height: 10)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Weekday comparison chart

private struct MacWeekdayComparisonChart: View {
    let buckets: [InboxMetricsWeekdayBucket]
    let thisWeekColor: Color
    let previousWeekColor: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(
                buckets.map(\.thisWeekValue).max() ?? 1,
                buckets.map(\.previousWeekValue).max() ?? 1,
                1
            )
            let groupWidth = (geo.size.width - CGFloat(buckets.count - 1) * 6) / CGFloat(max(buckets.count, 1))
            let barWidth = max(3, (groupWidth - 4) / 2)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(previousWeekColor)
                                .frame(
                                    width: barWidth,
                                    height: max(3, CGFloat(bucket.previousWeekValue / maxVal) * (geo.size.height - 20))
                                )
                            RoundedRectangle(cornerRadius: 2)
                                .fill(thisWeekColor)
                                .frame(
                                    width: barWidth,
                                    height: max(3, CGFloat(bucket.thisWeekValue / maxVal) * (geo.size.height - 20))
                                )
                        }

                        Text(bucket.weekdaySymbol)
                            .font(.system(size: 9))
                            .foregroundStyle(MacAppTheme.secondaryText.opacity(0.6))
                    }
                    .frame(width: groupWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
