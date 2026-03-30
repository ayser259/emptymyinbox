//
//  ScrollableEmailActionBar.swift
//  EmptyMyInboxShared
//

import SwiftUI

public struct ScrollableEmailActionBar: View {
    public let email: EmailDetail?
    public let isProcessing: Bool
    public let onReply: () async -> Void
    public let onStar: () async -> Void
    public let onKeepUnread: () async -> Void
    public let onMarkAsRead: () async -> Void
    public let onUnsubscribe: () async -> Void

    public let showReply: Bool
    public let hasUnsubscribe: Bool

    public init(
        email: EmailDetail?,
        isProcessing: Bool = false,
        showReply: Bool = true,
        onReply: @escaping () async -> Void,
        onStar: @escaping () async -> Void,
        onKeepUnread: @escaping () async -> Void,
        onMarkAsRead: @escaping () async -> Void,
        onUnsubscribe: @escaping () async -> Void,
        hasUnsubscribe: Bool = false
    ) {
        self.email = email
        self.isProcessing = isProcessing
        self.showReply = showReply
        self.hasUnsubscribe = hasUnsubscribe
        self.onReply = onReply
        self.onStar = onStar
        self.onKeepUnread = onKeepUnread
        self.onMarkAsRead = onMarkAsRead
        self.onUnsubscribe = onUnsubscribe
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(SharedAppTheme.secondaryText.opacity(0.2))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if showReply {
                            Button {
                                Task { await onReply() }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrowshape.turn.up.left")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(SharedAppTheme.accent)

                                    Text("Reply")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(SharedAppTheme.accent)
                                }
                                .frame(width: 80, height: 51.2)
                                .background(Color.black)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .id("reply")
                            .disabled(isProcessing)
                        }

                        Button {
                            Task { await onStar() }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: email?.is_starred == true ? "star.fill" : "star")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(SharedAppTheme.accent)

                                Text("Star")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(SharedAppTheme.accent)
                            }
                            .frame(width: 80, height: 51.2)
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        email?.is_starred == true ? SharedAppTheme.accent : Color.white.opacity(0.2),
                                        lineWidth: email?.is_starred == true ? 2 : 1
                                    )
                            )
                        }
                        .id("star")
                        .disabled(isProcessing)

                        Button {
                            Task { await onKeepUnread() }
                        } label: {
                            Text("Keep Unread")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(SharedAppTheme.primaryText)
                                .frame(width: 150, height: 51.2)
                                .background(SharedAppTheme.secondaryBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(SharedAppTheme.accent, lineWidth: 2)
                                )
                        }
                        .id("keepUnread")
                        .disabled(isProcessing)

                        Button {
                            Task { await onMarkAsRead() }
                        } label: {
                            Text("Mark as Read")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 150, height: 51.2)
                                .background(SharedAppTheme.accent)
                                .cornerRadius(12)
                        }
                        .id("markAsRead")
                        .disabled(isProcessing)

                        if hasUnsubscribe {
                            Button {
                                Task { await onUnsubscribe() }
                            } label: {
                                VStack(spacing: 6) {
                                    unsubscribeIcon
                                        .frame(width: 20, height: 20)

                                    Text("Unsubscribe")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .frame(width: 100, height: 51.2)
                                .background(Color.black)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .id("unsubscribe")
                            .disabled(isProcessing)
                        }
                    }
                    .padding(.leading, showReply ? (SharedAppTheme.spacingLarge - 60) : SharedAppTheme.spacingLarge)
                    .padding(.trailing, SharedAppTheme.spacingLarge)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("star", anchor: .leading)
                        }
                    }
                }
            }
        }
        .background(SharedAppTheme.primaryBackground)
    }

    @ViewBuilder
    private var unsubscribeIcon: some View {
        #if os(iOS)
        Image("Unsubscribe")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(.red)
        #else
        Image(systemName: "envelope.badge.fill")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.red)
        #endif
    }
}
