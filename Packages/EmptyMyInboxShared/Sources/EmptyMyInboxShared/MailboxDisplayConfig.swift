//
//  MailboxDisplayConfig.swift
//  EmptyMyInboxShared
//
//  Titles, icons, and empty-state copy for unified mailbox list surfaces.
//

import Foundation

public struct MailboxDisplayConfig: Sendable {
    public let navigationTitle: String
    public let emptyIconSystemName: String
    public let emptyTitle: String
    public let emptySubtitle: String
    public let showsReadFilterChips: Bool
    public let showsUnreadCountHeader: Bool

    public init(
        navigationTitle: String,
        emptyIconSystemName: String,
        emptyTitle: String,
        emptySubtitle: String,
        showsReadFilterChips: Bool = true,
        showsUnreadCountHeader: Bool = false
    ) {
        self.navigationTitle = navigationTitle
        self.emptyIconSystemName = emptyIconSystemName
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.showsReadFilterChips = showsReadFilterChips
        self.showsUnreadCountHeader = showsUnreadCountHeader
    }

    public static func forScope(_ scope: MailboxScope, readFilter: MailboxReadFilter = .all) -> MailboxDisplayConfig {
        switch scope {
        case .all:
            return MailboxDisplayConfig(
                navigationTitle: "All Emails",
                emptyIconSystemName: "envelope",
                emptyTitle: emptyTitle(for: readFilter, defaultTitle: "No emails"),
                emptySubtitle: emptySubtitle(for: readFilter, defaultSubtitle: "Your inbox is empty"),
                showsReadFilterChips: true,
                showsUnreadCountHeader: true
            )
        case .allUnread:
            return MailboxDisplayConfig(
                navigationTitle: "All Unread",
                emptyIconSystemName: "envelope.badge",
                emptyTitle: "No unread emails",
                emptySubtitle: "You're all caught up!",
                showsReadFilterChips: false,
                showsUnreadCountHeader: false
            )
        case .saved:
            return MailboxDisplayConfig(
                navigationTitle: "Saved",
                emptyIconSystemName: "star",
                emptyTitle: "No saved messages",
                emptySubtitle: "Star messages in Gmail to save them for later",
                showsReadFilterChips: true,
                showsUnreadCountHeader: false
            )
        case .account(let email):
            return MailboxDisplayConfig(
                navigationTitle: email,
                emptyIconSystemName: "envelope",
                emptyTitle: emptyTitle(for: readFilter, defaultTitle: "No messages"),
                emptySubtitle: emptySubtitle(for: readFilter, defaultSubtitle: "Messages will appear here when synced"),
                showsReadFilterChips: true,
                showsUnreadCountHeader: true
            )
        case .accountSaved:
            return MailboxDisplayConfig(
                navigationTitle: "Saved",
                emptyIconSystemName: "star",
                emptyTitle: "No saved messages",
                emptySubtitle: "Star messages to save them for later",
                showsReadFilterChips: false,
                showsUnreadCountHeader: false
            )
        }
    }

    private static func emptyTitle(for readFilter: MailboxReadFilter, defaultTitle: String) -> String {
        switch readFilter {
        case .all: return defaultTitle
        case .unread: return "No unread messages"
        case .read: return "No read messages"
        }
    }

    private static func emptySubtitle(for readFilter: MailboxReadFilter, defaultSubtitle: String) -> String {
        switch readFilter {
        case .all: return defaultSubtitle
        case .unread: return "You're all caught up!"
        case .read: return "Unread messages will appear in the Unread filter."
        }
    }
}
