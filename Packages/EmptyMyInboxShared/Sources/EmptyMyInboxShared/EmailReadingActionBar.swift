//
//  EmailReadingActionBar.swift
//  EmptyMyInboxShared
//
//  Single entry point for email triage controls (Catch Up, mail detail, etc.).
//  Wraps EmailReadingControlCenter and centralizes shared wiring.
//

import SwiftUI

// MARK: - Triage shortcuts

/// Key labels and shortcuts for the triage row (Catch Up uses distinct keys/copy on Mac).
public struct EmailReadingTriageShortcuts: Sendable {
    public let deferUnreadTitle: String
    public let deferUnreadShortcutDisplay: String
    public let markReadTitle: String
    public let markReadShortcutDisplay: String
    /// When true, triage buttons skip `.keyboardShortcut` (Mac Catch Up uses `MacCatchUpKeyboardMonitor` instead).
    public let suppressButtonKeyboardShortcuts: Bool

    public init(
        deferUnreadTitle: String,
        deferUnreadShortcutDisplay: String,
        markReadTitle: String = "Mark as Read",
        markReadShortcutDisplay: String,
        suppressButtonKeyboardShortcuts: Bool = false
    ) {
        self.deferUnreadTitle = deferUnreadTitle
        self.deferUnreadShortcutDisplay = deferUnreadShortcutDisplay
        self.markReadTitle = markReadTitle
        self.markReadShortcutDisplay = markReadShortcutDisplay
        self.suppressButtonKeyboardShortcuts = suppressButtonKeyboardShortcuts
    }

    /// Lowercase key for `.keyboardShortcut` (matches `shortcutDisplay`, e.g. "F" → "f").
    public var deferUnreadShortcutKey: KeyEquivalent {
        KeyEquivalent(deferUnreadShortcutDisplay.lowercased().first ?? "k")
    }

    public var markReadShortcutKey: KeyEquivalent {
        KeyEquivalent(markReadShortcutDisplay.lowercased().first ?? "j")
    }

    /// Inbox / mail detail triage (matches Catch Up: F = review later, J = mark read).
    public static let mailbox = EmailReadingTriageShortcuts(
        deferUnreadTitle: "Review Later",
        deferUnreadShortcutDisplay: "F",
        markReadTitle: "Mark as Read",
        markReadShortcutDisplay: "J"
    )

    /// Catch Up triage (F = review later, J = mark read).
    public static let catchUp: EmailReadingTriageShortcuts = {
        #if os(macOS)
        EmailReadingTriageShortcuts(
            deferUnreadTitle: "Review Later",
            deferUnreadShortcutDisplay: "F",
            markReadTitle: "Mark as Read",
            markReadShortcutDisplay: "J",
            suppressButtonKeyboardShortcuts: true
        )
        #else
        EmailReadingTriageShortcuts(
            deferUnreadTitle: "Review Later",
            deferUnreadShortcutDisplay: "F",
            markReadTitle: "Mark as Read",
            markReadShortcutDisplay: "J"
        )
        #endif
    }()
}

// MARK: - Action handlers

/// Callbacks for the shared reading action bar. Catch Up and mail detail supply their own implementations.
public struct EmailReadingActionHandlers {
    public var onReply: () -> Void
    public var onReplyAll: () -> Void
    public var onStar: () -> Void
    public var onMarkUnread: () -> Void
    public var onMarkAsRead: () -> Void
    public var onUnsubscribe: () -> Void

    public init(
        onReply: @escaping () -> Void,
        onReplyAll: @escaping () -> Void,
        onStar: @escaping () -> Void,
        onMarkUnread: @escaping () -> Void,
        onMarkAsRead: @escaping () -> Void,
        onUnsubscribe: @escaping () -> Void
    ) {
        self.onReply = onReply
        self.onReplyAll = onReplyAll
        self.onStar = onStar
        self.onMarkUnread = onMarkUnread
        self.onMarkAsRead = onMarkAsRead
        self.onUnsubscribe = onUnsubscribe
    }
}

// MARK: - Unsubscribe probe

public enum EmailReadingActionSupport {
    public static func hasUnsubscribeOption(for email: EmailDetail?) async -> Bool {
        guard let email else { return false }
        return await UnsubscribeService.shared.getUnsubscribeInfo(
            for: email,
            accountEmail: email.account_email
        ) != nil
    }
}

// MARK: - Catch Up status strip

public struct EmailReadingCatchUpStatusBar: View {
    public let remainingCount: Int
    public let isAnimating: Bool

    public init(remainingCount: Int, isAnimating: Bool) {
        self.remainingCount = remainingCount
        self.isAnimating = isAnimating
    }

    public var body: some View {
        HStack(spacing: 8) {
            if isAnimating {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
                Text("Processing…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SharedAppTheme.secondaryText)
            } else {
                Circle()
                    .fill(remainingCount > 0 ? SharedAppTheme.accent : Color.green)
                    .frame(width: 7, height: 7)
                Text(remainingCount > 0 ? "\(remainingCount) left to review" : "All caught up!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(remainingCount > 0 ? SharedAppTheme.accent : .green)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(SharedAppTheme.secondaryBackground)
    }
}

// MARK: - Action bar (public API)

/// Shared bottom action bar for reading/triaging an email. Use this instead of `EmailReadingControlCenter` directly.
public struct EmailReadingActionBar<Status: View>: View {
    public let email: EmailDetail?
    public let isDisabled: Bool
    @Binding public var hasUnsubscribe: Bool
    public let handlers: EmailReadingActionHandlers
    public let triageShortcuts: EmailReadingTriageShortcuts
    @ViewBuilder public var statusBar: () -> Status

    private var showReplyAll: Bool {
        guard let email else { return false }
        return ReplyRecipientResolver.isReplyAllMeaningful(email: email)
    }

    public init(
        email: EmailDetail?,
        isDisabled: Bool,
        hasUnsubscribe: Binding<Bool>,
        handlers: EmailReadingActionHandlers,
        triageShortcuts: EmailReadingTriageShortcuts = .mailbox,
        @ViewBuilder statusBar: @escaping () -> Status
    ) {
        self.email = email
        self.isDisabled = isDisabled
        _hasUnsubscribe = hasUnsubscribe
        self.handlers = handlers
        self.triageShortcuts = triageShortcuts
        self.statusBar = statusBar
    }

    public var body: some View {
        EmailReadingControlCenter(
            email: email,
            isDisabled: isDisabled,
            hasUnsubscribe: hasUnsubscribe,
            showReplyAll: showReplyAll,
            triageShortcuts: triageShortcuts,
            onReply: handlers.onReply,
            onReplyAll: handlers.onReplyAll,
            onStar: handlers.onStar,
            onMarkUnread: handlers.onMarkUnread,
            onMarkAsRead: handlers.onMarkAsRead,
            onUnsubscribe: handlers.onUnsubscribe,
            statusBar: statusBar
        )
        .task(id: email?.id) {
            hasUnsubscribe = await EmailReadingActionSupport.hasUnsubscribeOption(for: email)
        }
    }
}

extension EmailReadingActionBar where Status == EmptyView {
    /// Mail detail and other surfaces without a Catch Up status strip.
    public init(
        email: EmailDetail?,
        isDisabled: Bool,
        hasUnsubscribe: Binding<Bool>,
        handlers: EmailReadingActionHandlers
    ) {
        self.init(
            email: email,
            isDisabled: isDisabled,
            hasUnsubscribe: hasUnsubscribe,
            handlers: handlers,
            statusBar: { EmptyView() }
        )
    }
}

/// Catch Up variant: same action bar with the queue status header.
public struct EmailReadingCatchUpActionBar: View {
    public let email: EmailDetail?
    public let remainingCount: Int
    public let isDisabled: Bool
    public let isAnimating: Bool
    @Binding public var hasUnsubscribe: Bool
    public let handlers: EmailReadingActionHandlers

    public init(
        email: EmailDetail?,
        remainingCount: Int,
        isDisabled: Bool,
        isAnimating: Bool,
        hasUnsubscribe: Binding<Bool>,
        handlers: EmailReadingActionHandlers
    ) {
        self.email = email
        self.remainingCount = remainingCount
        self.isDisabled = isDisabled
        self.isAnimating = isAnimating
        _hasUnsubscribe = hasUnsubscribe
        self.handlers = handlers
    }

    public var body: some View {
        EmailReadingActionBar(
            email: email,
            isDisabled: isDisabled,
            hasUnsubscribe: $hasUnsubscribe,
            handlers: handlers,
            triageShortcuts: .catchUp
        ) {
            EmailReadingCatchUpStatusBar(
                remainingCount: remainingCount,
                isAnimating: isAnimating
            )
        }
    }
}
