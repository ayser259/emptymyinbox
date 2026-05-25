//
//  EmailReadingControlCenter.swift
//  EmptyMyInboxShared
//
//  Low-level triage control layout. Prefer `EmailReadingActionBar` for app screens.
//

import SwiftUI

// MARK: - Control center (internal layout)

struct EmailReadingControlCenter<Status: View>: View {
    let email: EmailDetail?
    let isDisabled: Bool
    let hasUnsubscribe: Bool
    let showReplyAll: Bool
    let triageShortcuts: EmailReadingTriageShortcuts
    var onReply: () -> Void
    var onReplyAll: () -> Void
    var onStar: () -> Void
    var onMarkUnread: () -> Void
    var onMarkAsRead: () -> Void
    var onUnsubscribe: () -> Void
    @ViewBuilder var statusBar: () -> Status

    init(
        email: EmailDetail?,
        isDisabled: Bool,
        hasUnsubscribe: Bool,
        showReplyAll: Bool,
        triageShortcuts: EmailReadingTriageShortcuts = .mailbox,
        onReply: @escaping () -> Void,
        onReplyAll: @escaping () -> Void,
        onStar: @escaping () -> Void,
        onMarkUnread: @escaping () -> Void,
        onMarkAsRead: @escaping () -> Void,
        onUnsubscribe: @escaping () -> Void,
        @ViewBuilder statusBar: @escaping () -> Status
    ) {
        self.email = email
        self.isDisabled = isDisabled
        self.hasUnsubscribe = hasUnsubscribe
        self.showReplyAll = showReplyAll
        self.triageShortcuts = triageShortcuts
        self.onReply = onReply
        self.onReplyAll = onReplyAll
        self.onStar = onStar
        self.onMarkUnread = onMarkUnread
        self.onMarkAsRead = onMarkAsRead
        self.onUnsubscribe = onUnsubscribe
        self.statusBar = statusBar
    }

    private var isRead: Bool { email?.is_read == true }

    private var unreadActionTitle: String {
        isRead ? "Mark Unread" : triageShortcuts.deferUnreadTitle
    }

    private var unreadActionIcon: String {
        isRead ? "envelope.badge" : "arrow.uturn.left.circle"
    }

    private var registersButtonKeyboardShortcuts: Bool {
        !triageShortcuts.suppressButtonKeyboardShortcuts
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar()

            Divider().opacity(0.3)

            HStack(spacing: 8) {
                EmailReadingTriageButton(
                    title: unreadActionTitle,
                    systemImage: unreadActionIcon,
                    shortcutDisplay: triageShortcuts.deferUnreadShortcutDisplay,
                    shortcutKey: triageShortcuts.deferUnreadShortcutKey,
                    shortcutModifiers: [],
                    registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                    style: .secondary,
                    isDisabled: isDisabled || (!isRead && email == nil)
                ) {
                    onMarkUnread()
                }
                #if os(macOS)
                .help(
                    isRead
                        ? "Mark as unread  [\(triageShortcuts.deferUnreadShortcutDisplay)]"
                        : "\(triageShortcuts.deferUnreadTitle)  [\(triageShortcuts.deferUnreadShortcutDisplay)]"
                )
                #endif

                EmailReadingTriageButton(
                    title: "Star",
                    systemImage: email?.is_starred == true ? "star.fill" : "star",
                    shortcutDisplay: "S",
                    shortcutKey: "s",
                    shortcutModifiers: [],
                    registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                    style: email?.is_starred == true ? .starred : .secondary,
                    isDisabled: isDisabled
                ) {
                    onStar()
                }
                #if os(macOS)
                .help("Star  [S]")
                #endif

                EmailReadingTriageButton(
                    title: triageShortcuts.markReadTitle,
                    systemImage: "envelope.open.fill",
                    shortcutDisplay: triageShortcuts.markReadShortcutDisplay,
                    shortcutKey: triageShortcuts.markReadShortcutKey,
                    shortcutModifiers: [],
                    registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                    style: .prominent,
                    isDisabled: isDisabled || isRead
                ) {
                    onMarkAsRead()
                }
                #if os(macOS)
                .help("Mark as read  [\(triageShortcuts.markReadShortcutDisplay)]")
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)

                HStack(spacing: 8) {
                    EmailReadingSecondaryButton(
                        label: "Reply",
                        systemImage: "arrowshape.turn.up.left",
                        shortcutDisplay: "R",
                        shortcutKey: "r",
                        shortcutModifiers: [],
                        registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                        isDisabled: isDisabled,
                        action: onReply
                    )
                    #if os(macOS)
                    .help("Compose a reply  [R]")
                    #endif

                    if showReplyAll {
                        EmailReadingSecondaryButton(
                            label: "All",
                            systemImage: "arrowshape.turn.up.left.2",
                            shortcutDisplay: "⇧R",
                            shortcutKey: "r",
                            shortcutModifiers: [.shift],
                            registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                            isDisabled: isDisabled,
                            action: onReplyAll
                        )
                        #if os(macOS)
                        .help("Reply all  [⇧R]")
                        #endif
                    }

                    Spacer()

                    if hasUnsubscribe {
                        EmailReadingSecondaryButton(
                            label: "Unsubscribe",
                            systemImage: "envelope.badge.fill",
                            shortcutDisplay: "⌘⇧U",
                            shortcutKey: "u",
                            shortcutModifiers: [.command, .shift],
                            registersKeyboardShortcut: registersButtonKeyboardShortcuts,
                            tint: .red,
                            isDisabled: isDisabled,
                            action: onUnsubscribe
                        )
                        #if os(macOS)
                        .help("Unsubscribe from this sender  [⌘⇧U]")
                        #endif
                    }
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(SharedAppTheme.secondaryBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}

extension EmailReadingControlCenter where Status == EmptyView {
    init(
        email: EmailDetail?,
        isDisabled: Bool,
        hasUnsubscribe: Bool,
        showReplyAll: Bool,
        triageShortcuts: EmailReadingTriageShortcuts = .mailbox,
        onReply: @escaping () -> Void,
        onReplyAll: @escaping () -> Void,
        onStar: @escaping () -> Void,
        onMarkUnread: @escaping () -> Void,
        onMarkAsRead: @escaping () -> Void,
        onUnsubscribe: @escaping () -> Void
    ) {
        self.init(
            email: email,
            isDisabled: isDisabled,
            hasUnsubscribe: hasUnsubscribe,
            showReplyAll: showReplyAll,
            triageShortcuts: triageShortcuts,
            onReply: onReply,
            onReplyAll: onReplyAll,
            onStar: onStar,
            onMarkUnread: onMarkUnread,
            onMarkAsRead: onMarkAsRead,
            onUnsubscribe: onUnsubscribe,
            statusBar: { EmptyView() }
        )
    }
}

// MARK: - Triage button

enum EmailReadingTriageButtonStyle { case prominent, secondary, starred }

struct EmailReadingTriageButton: View {
    let title: String
    let systemImage: String
    let shortcutDisplay: String
    let shortcutKey: KeyEquivalent
    let shortcutModifiers: EventModifiers
    var registersKeyboardShortcut: Bool = true
    let style: EmailReadingTriageButtonStyle
    let isDisabled: Bool
    let action: () -> Void

    #if os(macOS)
    @State private var isHovered = false
    #endif

    private var bgColor: Color {
        #if os(macOS)
        switch style {
        case .prominent: return isHovered ? SharedAppTheme.accent.opacity(0.88) : SharedAppTheme.accent
        case .starred: return isHovered ? SharedAppTheme.accent.opacity(0.22) : SharedAppTheme.accent.opacity(0.14)
        case .secondary: return isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05)
        }
        #else
        switch style {
        case .prominent: return SharedAppTheme.accent
        case .starred: return SharedAppTheme.accent.opacity(0.14)
        case .secondary: return Color.white.opacity(0.05)
        }
        #endif
    }

    private var borderColor: Color {
        switch style {
        case .prominent: return .clear
        case .starred: return SharedAppTheme.accent.opacity(0.5)
        case .secondary: return Color.white.opacity(0.1)
        }
    }

    private var fgColor: Color {
        switch style {
        case .prominent: return .black
        case .starred: return SharedAppTheme.accent
        case .secondary: return SharedAppTheme.primaryText
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                #if os(macOS)
                Text(shortcutDisplay)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fgColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(fgColor.opacity(0.25), lineWidth: 0.5)
                    )
                #endif
            }
            .foregroundStyle(fgColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .modifier(EmailReadingKeyboardShortcutModifier(
            key: shortcutKey,
            modifiers: shortcutModifiers,
            isEnabled: registersKeyboardShortcut
        ))
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered && !isDisabled ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        #endif
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isDisabled)
    }
}

// MARK: - Secondary button

struct EmailReadingSecondaryButton: View {
    let label: String
    let systemImage: String
    let shortcutDisplay: String
    let shortcutKey: KeyEquivalent
    let shortcutModifiers: EventModifiers
    var registersKeyboardShortcut: Bool = true
    var tint: Color = SharedAppTheme.accent
    let isDisabled: Bool
    let action: () -> Void

    #if os(macOS)
    @State private var isHovered = false
    #endif

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                #if os(macOS)
                Text(shortcutDisplay)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint == .red ? Color.red.opacity(0.8) : SharedAppTheme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                #endif
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint.opacity(borderOpacity), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .modifier(EmailReadingKeyboardShortcutModifier(
            key: shortcutKey,
            modifiers: shortcutModifiers,
            isEnabled: registersKeyboardShortcut
        ))
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered && !isDisabled ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        #endif
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
    }

    #if os(macOS)
    private var backgroundOpacity: Double { isHovered ? 0.15 : 0.08 }
    private var borderOpacity: Double { isHovered ? 0.45 : 0.28 }
    #else
    private var backgroundOpacity: Double { 0.08 }
    private var borderOpacity: Double { 0.28 }
    #endif
}

#if os(macOS)
/// Applies `.keyboardShortcut` only when enabled (Catch Up uses an AppKit key monitor instead).
private struct EmailReadingKeyboardShortcutModifier: ViewModifier {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}
#endif
