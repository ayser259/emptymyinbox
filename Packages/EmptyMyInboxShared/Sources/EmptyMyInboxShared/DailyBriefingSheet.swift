import SwiftUI

/// Inline body for the daily briefing (used by the sheet and embedded Mac detail).
public struct DailyBriefingContent: View {
    let payload: DailyBriefingPayload
    let onItemTap: (DailyBriefingItem) -> Void

    public init(
        payload: DailyBriefingPayload,
        onItemTap: @escaping (DailyBriefingItem) -> Void
    ) {
        self.payload = payload
        self.onItemTap = onItemTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            Text(Self.generatedLabel(for: payload.generatedAt))
                .font(SharedAppTheme.caption)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .padding(.horizontal, SharedAppTheme.spacingMedium)
                .padding(.top, SharedAppTheme.spacingSmall)

            Text(payload.introText)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .padding(.horizontal, SharedAppTheme.spacingMedium)

            if payload.sections.isEmpty {
                Text("No important updates right now.")
                    .font(SharedAppTheme.subheadline)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                    .padding(.top, SharedAppTheme.spacingMedium)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SharedAppTheme.spacingLarge) {
                        ForEach(payload.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                    .padding(.bottom, SharedAppTheme.spacingMedium)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharedAppTheme.primaryBackground)
    }

    @ViewBuilder
    private func sectionView(_ section: DailyBriefingSection) -> some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingSmall) {
            HStack(spacing: 6) {
                Image(systemName: section.kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharedAppTheme.accent)
                Text(section.title)
                    .font(SharedAppTheme.subheadline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.primaryText)
            }

            if section.kind == .receiptsAndTransactions {
                ForEach(groupedReceiptItems(section.items), id: \.source) { group in
                    receiptGroupView(group)
                }
            } else {
                ForEach(section.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private struct ReceiptGroup: Identifiable {
        let source: String
        let items: [DailyBriefingItem]
        var id: String { source }
    }

    private func groupedReceiptItems(_ items: [DailyBriefingItem]) -> [ReceiptGroup] {
        var groups: [String: [DailyBriefingItem]] = [:]
        for item in items {
            let key = item.sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? item.sourceLabel!
                : (item.senderName ?? item.sender)
            groups[key, default: []].append(item)
        }
        return groups.keys.sorted().map { ReceiptGroup(source: $0, items: groups[$0] ?? []) }
    }

    @ViewBuilder
    private func receiptGroupView(_ group: ReceiptGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.source)
                .font(SharedAppTheme.caption.weight(.semibold))
                .foregroundStyle(SharedAppTheme.accent)
            ForEach(group.items) { item in
                itemRow(item, compact: true)
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: DailyBriefingItem, compact: Bool = false) -> some View {
        Button {
            onItemTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.section.iconName)
                    .foregroundStyle(SharedAppTheme.accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.subject)
                        .font(compact ? SharedAppTheme.caption.weight(.semibold) : SharedAppTheme.subheadline)
                        .foregroundStyle(SharedAppTheme.primaryText)
                        .multilineTextAlignment(.leading)

                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                    } else if !compact {
                        Text(item.snippet)
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if !item.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(item.actionItems, id: \.self) { action in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•")
                                        .font(SharedAppTheme.caption)
                                        .foregroundStyle(SharedAppTheme.accent)
                                    Text(action)
                                        .font(SharedAppTheme.caption)
                                        .foregroundStyle(SharedAppTheme.primaryText)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    Text(item.senderName ?? item.sender)
                        .font(SharedAppTheme.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .padding(.top, 4)
            }
            .padding(SharedAppTheme.spacingMedium)
            .background(SharedAppTheme.secondaryBackground)
            .cornerRadius(SharedAppTheme.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
    }

    private static func generatedLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Generated \(formatter.string(from: date))"
    }
}

public struct DailyBriefingSheet: View {
    let payload: DailyBriefingPayload
    let onItemTap: (DailyBriefingItem) -> Void
    let onDismiss: () -> Void

    public init(
        payload: DailyBriefingPayload,
        onItemTap: @escaping (DailyBriefingItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.payload = payload
        self.onItemTap = onItemTap
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            DailyBriefingContent(payload: payload, onItemTap: onItemTap)
                .navigationTitle("Daily Executive Briefing")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDismiss()
                        }
                        .foregroundStyle(SharedAppTheme.accent)
                    }
                }
        }
    }
}
