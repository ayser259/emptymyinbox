//
//  MailboxEmailRow.swift
//  EmptyMyInboxShared
//
//  Platform-native mailbox list row with star and unread affordances.
//

import SwiftUI

public struct MailboxEmailRow: View {
    let email: EmailListItem
    var showsAccountEmail: Bool
    var onStarChanged: ((Bool) -> Void)?

    @State private var isStarred: Bool
    @State private var isUpdatingStar = false

    public init(
        email: EmailListItem,
        showsAccountEmail: Bool = false,
        onStarChanged: ((Bool) -> Void)? = nil
    ) {
        self.email = email
        self.showsAccountEmail = showsAccountEmail
        self.onStarChanged = onStarChanged
        _isStarred = State(initialValue: email.is_starred)
    }

    public var body: some View {
        #if os(iOS)
        iosRow
        #else
        macRow
        #endif
    }

    // MARK: - iOS

    #if os(iOS)
    private var iosRow: some View {
        HStack(alignment: .top, spacing: SharedAppTheme.spacingMedium) {
            starButton(iconSize: 16, frameWidth: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: SharedAppTheme.spacingSmall) {
                    Text(EmailListItemDisplay.senderDisplayName(for: email))
                        .font(.body)
                        .fontWeight(email.is_read ? .regular : .semibold)
                        .foregroundStyle(email.is_read ? SharedAppTheme.secondaryText : SharedAppTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(EmailListItemDisplay.relativeListDate(from: email.received_at))
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                }

                Text(EmailListItemDisplay.subjectDisplay(for: email))
                    .font(.body)
                    .fontWeight(email.is_read ? .regular : .semibold)
                    .foregroundStyle(email.is_read ? SharedAppTheme.secondaryText : SharedAppTheme.primaryText)
                    .lineLimit(2)

                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(.subheadline)
                        .foregroundStyle(
                            email.is_read
                                ? SharedAppTheme.secondaryText.opacity(0.65)
                                : SharedAppTheme.secondaryText.opacity(0.85)
                        )
                        .lineLimit(2)
                }

                if showsAccountEmail {
                    Text(email.account_email)
                        .font(.caption2)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.65))
                        .lineLimit(1)
                }
            }

            if !email.is_read {
                Circle()
                    .fill(SharedAppTheme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, SharedAppTheme.spacingSmall)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous))
        .contentShape(Rectangle())
    }
    #endif

    // MARK: - macOS

    #if os(macOS)
    private var macRow: some View {
        HStack(alignment: .top, spacing: 10) {
            starButton(iconSize: 13, frameWidth: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(EmailListItemDisplay.senderDisplayName(for: email))
                        .font(.headline)
                        .fontWeight(email.is_read ? .regular : .semibold)
                        .foregroundStyle(
                            email.is_read
                                ? SharedAppTheme.secondaryText
                                : SharedAppTheme.primaryText
                        )
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(EmailListItemDisplay.relativeListDate(from: email.received_at))
                        .font(.caption)
                        .foregroundStyle(
                            email.is_read
                                ? SharedAppTheme.secondaryText.opacity(0.75)
                                : SharedAppTheme.secondaryText
                        )
                }

                Text(EmailListItemDisplay.subjectDisplay(for: email))
                    .font(.subheadline.weight(email.is_read ? .regular : .semibold))
                    .foregroundStyle(email.is_read ? SharedAppTheme.secondaryText : SharedAppTheme.primaryText)
                    .lineLimit(2)

                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(.caption)
                        .foregroundStyle(
                            email.is_read
                                ? SharedAppTheme.secondaryText.opacity(0.7)
                                : SharedAppTheme.secondaryText.opacity(0.9)
                        )
                        .lineLimit(2)
                }

                if showsAccountEmail {
                    Text(email.account_email)
                        .font(.caption2)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.75))
                        .lineLimit(1)
                }
            }

            if !email.is_read {
                Circle()
                    .fill(SharedAppTheme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
    }
    #endif

    private var rowBackground: Color {
        SharedAppTheme.mailboxRowBackground(isRead: email.is_read)
    }

    // MARK: - Star

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
        .disabled(isUpdatingStar)
    }

    private func toggleStar() async {
        isUpdatingStar = true
        defer { isUpdatingStar = false }

        let newStarState = !isStarred
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)

        await MainActor.run {
            isStarred = newStarState
            onStarChanged?(newStarState)
        }
    }
}
