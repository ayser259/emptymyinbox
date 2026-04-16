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
            Text(payload.introText)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .padding(.horizontal, SharedAppTheme.spacingMedium)
                .padding(.top, SharedAppTheme.spacingSmall)

            if payload.items.isEmpty {
                Text("No important updates right now.")
                    .font(SharedAppTheme.subheadline)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                    .padding(.top, SharedAppTheme.spacingMedium)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: SharedAppTheme.spacingSmall) {
                        ForEach(payload.items) { item in
                            Button {
                                onItemTap(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checklist.checked")
                                        .foregroundStyle(SharedAppTheme.accent)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.subject)
                                            .font(SharedAppTheme.subheadline)
                                            .foregroundStyle(SharedAppTheme.primaryText)
                                            .multilineTextAlignment(.leading)
                                        Text("\(item.senderName ?? item.sender) • \(Self.caption(for: item.type))")
                                            .font(SharedAppTheme.caption)
                                            .foregroundStyle(SharedAppTheme.secondaryText)
                                            .multilineTextAlignment(.leading)
                                        Text(item.snippet)
                                            .font(SharedAppTheme.caption)
                                            .foregroundStyle(SharedAppTheme.secondaryText)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
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
                    }
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                    .padding(.bottom, SharedAppTheme.spacingMedium)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharedAppTheme.primaryBackground)
    }

    private static func caption(for type: BriefingItemType) -> String {
        switch type {
        case .directCommunication:
            return "Direct Communication"
        case .calendarInvite:
            return "Calendar Invite"
        case .urgentNotification:
            return "Urgent Notification"
        }
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
