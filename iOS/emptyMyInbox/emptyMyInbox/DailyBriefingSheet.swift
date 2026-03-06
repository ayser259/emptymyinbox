import SwiftUI

struct DailyBriefingSheet: View {
    let payload: DailyBriefingPayload
    let onItemTap: (DailyBriefingItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                Text(payload.introText)
                    .font(AppTheme.body)
                    .secondaryText()
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.top, AppTheme.spacingSmall)

                if payload.items.isEmpty {
                    Text("No important updates right now.")
                        .font(AppTheme.subheadline)
                        .secondaryText()
                        .padding(.horizontal, AppTheme.spacingMedium)
                        .padding(.top, AppTheme.spacingMedium)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacingSmall) {
                            ForEach(payload.items) { item in
                                Button {
                                    onItemTap(item)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "checklist.checked")
                                            .foregroundColor(AppTheme.accent)
                                            .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.subject)
                                                .font(AppTheme.subheadline)
                                                .foregroundColor(AppTheme.primaryText)
                                                .multilineTextAlignment(.leading)
                                            Text("\(item.senderName ?? item.sender) • \(caption(for: item.type))")
                                                .font(AppTheme.caption)
                                                .foregroundColor(AppTheme.secondaryText)
                                                .multilineTextAlignment(.leading)
                                            Text(item.snippet)
                                                .font(AppTheme.caption)
                                                .foregroundColor(AppTheme.secondaryText)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(AppTheme.secondaryText)
                                            .padding(.top, 4)
                                    }
                                    .padding(AppTheme.spacingMedium)
                                    .background(AppTheme.secondaryBackground)
                                    .cornerRadius(AppTheme.cornerRadiusMedium)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingMedium)
                        .padding(.bottom, AppTheme.spacingMedium)
                    }
                }
            }
            .primaryBackground()
            .navigationTitle("Daily Executive Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .textButton()
                }
            }
        }
    }

    private func caption(for type: BriefingItemType) -> String {
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
