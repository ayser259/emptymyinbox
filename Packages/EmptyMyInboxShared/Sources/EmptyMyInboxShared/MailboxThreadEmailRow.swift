//
//  MailboxThreadEmailRow.swift
//  EmptyMyInboxShared
//
//  Gmail-style thread row with unread count badge.
//

import SwiftUI

public struct MailboxThreadEmailRow: View {
    let thread: EmailThreadSummary
    var showsAccountEmail: Bool
    var onStarChanged: ((Bool) -> Void)?

    @State private var isStarred: Bool

    public init(
        thread: EmailThreadSummary,
        showsAccountEmail: Bool = false,
        onStarChanged: ((Bool) -> Void)? = nil
    ) {
        self.thread = thread
        self.showsAccountEmail = showsAccountEmail
        self.onStarChanged = onStarChanged
        _isStarred = State(initialValue: thread.latestMessage.is_starred)
    }

    private var email: EmailListItem { thread.latestMessage }

    public var body: some View {
        #if os(iOS)
        iosRow
        #else
        macRow
        #endif
    }

    #if os(iOS)
    private var iosRow: some View {
        HStack(alignment: .top, spacing: SharedAppTheme.spacingMedium) {
            starButton(iconSize: 16, frameWidth: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: SharedAppTheme.spacingSmall) {
                    Text(EmailListItemDisplay.senderDisplayName(for: email))
                        .font(.body)
                        .fontWeight(thread.isUnread ? .semibold : .regular)
                        .foregroundStyle(thread.isUnread ? SharedAppTheme.primaryText : SharedAppTheme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        if thread.unreadCount > 1 {
                            unreadCountBadge
                        }
                        Text(EmailListItemDisplay.relativeListDate(from: email.received_at))
                            .font(.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                    }
                }

                Text(EmailListItemDisplay.subjectDisplay(for: email))
                    .font(.body)
                    .fontWeight(thread.isUnread ? .semibold : .regular)
                    .foregroundStyle(thread.isUnread ? SharedAppTheme.primaryText : SharedAppTheme.secondaryText)
                    .lineLimit(2)

                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(.subheadline)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.8))
                        .lineLimit(2)
                }

                if showsAccountEmail {
                    Text(email.account_email)
                        .font(.caption2)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.65))
                        .lineLimit(1)
                }
            }

            if thread.isUnread {
                Circle()
                    .fill(SharedAppTheme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, SharedAppTheme.spacingSmall)
        .background(SharedAppTheme.secondaryBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous))
        .contentShape(Rectangle())
    }
    #endif

    #if os(macOS)
    private var macRow: some View {
        HStack(alignment: .top, spacing: 10) {
            starButton(iconSize: 13, frameWidth: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(EmailListItemDisplay.senderDisplayName(for: email))
                        .font(.headline)
                        .fontWeight(thread.isUnread ? .semibold : .regular)
                        .foregroundStyle(SharedAppTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if thread.unreadCount > 1 {
                        unreadCountBadge
                    }
                    Text(EmailListItemDisplay.relativeListDate(from: email.received_at))
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }

                Text(EmailListItemDisplay.subjectDisplay(for: email))
                    .font(.subheadline.weight(thread.isUnread ? .semibold : .regular))
                    .foregroundStyle(thread.isUnread ? SharedAppTheme.primaryText : SharedAppTheme.secondaryText)
                    .lineLimit(2)

                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                        .lineLimit(2)
                }

                if showsAccountEmail {
                    Text(email.account_email)
                        .font(.caption2)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.75))
                        .lineLimit(1)
                }
            }

            if thread.isUnread {
                Circle()
                    .fill(SharedAppTheme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    #endif

    private var unreadCountBadge: some View {
        Text("\(thread.unreadCount)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, thread.unreadCount > 99 ? 5 : 7)
            .padding(.vertical, 3)
            .background(SharedAppTheme.accent)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func starButton(iconSize: CGFloat, frameWidth: CGFloat) -> some View {
        Button {
            Task { await toggleStar() }
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .foregroundStyle(isStarred ? SharedAppTheme.accent : SharedAppTheme.secondaryText.opacity(0.5))
                .font(.system(size: iconSize))
                .frame(width: frameWidth)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private func toggleStar() async {
        let newStarState = !isStarred
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        isStarred = newStarState
        onStarChanged?(newStarState)
    }
}
