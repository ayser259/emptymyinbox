//
//  EmailThreadReaderView.swift
//  EmptyMyInboxShared
//
//  Full-thread reading: sticky chrome + single WKWebView for message bodies.
//

import SwiftUI

// MARK: - Shared full-body rendering (single-email contexts)

public enum EmailBodyContent {
    @ViewBuilder
    public static func body(
        for email: EmailDetail,
        minHeight: CGFloat? = nil,
        onLoadComplete: (() -> Void)? = nil,
        scrollSignal: Int = 0,
        scrollStepAmount: CGFloat = 0
    ) -> some View {
        Group {
            if let html = email.body_html, !html.isEmpty {
                EmailHTMLWebView(
                    htmlContent: html,
                    isDarkMode: false,
                    onLoadComplete: onLoadComplete,
                    scrollSignal: scrollSignal,
                    scrollStepAmount: scrollStepAmount
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight ?? 0)
            } else if !email.body_text.isEmpty {
                if looksLikeHTML(email.body_text) {
                    EmailHTMLWebView(
                        htmlContent: email.body_text,
                        isDarkMode: false,
                        onLoadComplete: onLoadComplete,
                        scrollSignal: scrollSignal,
                        scrollStepAmount: scrollStepAmount
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: minHeight ?? 0)
                } else {
                    Text(email.body_text)
                        .font(.system(size: 15))
                        .primaryText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .padding(SharedAppTheme.spacingMedium)
                        .onAppear { onLoadComplete?() }
                }
            } else {
                Text(email.snippet)
                    .font(.system(size: 15))
                    .secondaryText()
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(SharedAppTheme.spacingMedium)
                    .onAppear { onLoadComplete?() }
            }
        }
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") { return true }
        if trimmed.hasPrefix("<") && (
            trimmed.contains("<head") ||
            trimmed.contains("<body") ||
            trimmed.contains("<div") ||
            trimmed.contains("<table") ||
            trimmed.contains("<style") ||
            trimmed.contains("<meta")
        ) {
            return true
        }
        return false
    }
}

// MARK: - Catch Up / compact thread reader

public struct EmailThreadReaderView: View {
    @Binding public var conversation: EmailThreadConversation
    public let viewportHeight: CGFloat
    public var isActive: Bool = true
    public var showsActionTargetPicker: Bool = true
    public var scrollSignal: Int = 0
    public var scrollStepAmount: CGFloat = 0
    public var onLoadComplete: (() -> Void)?

    @State private var isThreadHistoryExpanded = false

    public init(
        conversation: Binding<EmailThreadConversation>,
        viewportHeight: CGFloat,
        isActive: Bool = true,
        showsActionTargetPicker: Bool = true,
        scrollSignal: Int = 0,
        scrollStepAmount: CGFloat = 0,
        onLoadComplete: (() -> Void)? = nil
    ) {
        _conversation = conversation
        self.viewportHeight = viewportHeight
        self.isActive = isActive
        self.showsActionTargetPicker = showsActionTargetPicker
        self.scrollSignal = scrollSignal
        self.scrollStepAmount = scrollStepAmount
        self.onLoadComplete = onLoadComplete
    }

    private var primaryMessage: EmailDetail? {
        newestUnreadMessage ?? newestMessage
    }

    private var newestUnreadMessage: EmailDetail? {
        conversation.messages.filter { !$0.is_read }.max(by: olderThan)
    }

    private var newestMessage: EmailDetail? {
        conversation.messages.max(by: olderThan)
    }

    private var additionalUnreadMessages: [EmailDetail] {
        conversation.messages
            .filter { !$0.is_read && $0.id != primaryMessage?.id }
            .sorted { lhs, rhs in olderThan(rhs, lhs) }
    }

    private var messagesForWebView: [EmailDetail] {
        guard let primary = primaryMessage else { return [] }
        if isThreadHistoryExpanded, !additionalUnreadMessages.isEmpty {
            return [primary] + additionalUnreadMessages
        }
        return [primary]
    }

    public var body: some View {
        Group {
            if primaryMessage != nil {
                threadContent
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#252525"))
        .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(SharedAppTheme.accent.opacity(isActive ? 1 : 0.35), lineWidth: 2)
        )
        .frame(height: viewportHeight)
    }

    @ViewBuilder
    private var threadContent: some View {
        VStack(spacing: 0) {
            if let primary = primaryMessage {
                primaryEmailHeader(primary)
            }

            if showsActionTargetPicker && conversation.unreadCount > 1,
               let target = conversation.selectedMessage {
                ThreadActionTargetBar(
                    target: target,
                    unreadCount: conversation.unreadCount,
                    onSelectLatestUnread: {
                        let id = EmailThreadConversation.defaultActionTargetId(in: conversation.messages)
                        conversation.selectMessage(id: id)
                    }
                )
            }

            if !additionalUnreadMessages.isEmpty {
                threadHistoryToggleBar
            }

            EmailThreadConversationWebView(
                messages: messagesForWebView,
                selectedId: conversation.selectedMessageId,
                scrollSignal: scrollSignal,
                scrollStepAmount: scrollStepAmount,
                onSelectMessage: { id in
                    conversation.selectMessage(id: id)
                },
                onLoadComplete: onLoadComplete
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: viewportHeight)
    }

    private var threadHistoryToggleBar: some View {
        let count = additionalUnreadMessages.count
        let expandedTitle = "Show only newest"
        let collapsedTitle = "\(count) more unread email\(count == 1 ? "" : "s") in this thread"

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isThreadHistoryExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isThreadHistoryExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.accent)
                Text(isThreadHistoryExpanded ? expandedTitle : collapsedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.accent)
                Spacer()
            }
            .padding(.horizontal, SharedAppTheme.spacingMedium)
            .padding(.vertical, 12)
            .background(Color(hex: "#1e1e1e"))
        }
        .buttonStyle(.plain)
    }

    private func primaryEmailHeader(_ email: EmailDetail) -> some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingExtraSmall) {
            HStack {
                Text(email.sender_name ?? email.sender)
                    .font(.system(size: 18, weight: .semibold))
                    .primaryText()

                Spacer()

                if conversation.unreadCount > 1 {
                    Text("\(conversation.unreadCount) unread")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SharedAppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SharedAppTheme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(formatCompactDate(email.received_at))
                    .font(.system(size: 14, weight: .medium))
                    .secondaryText()
            }

            Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                .font(.system(size: 16, weight: .medium))
                .primaryText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(Color(hex: "#252525"))
    }

    private func formatCompactDate(_ dateString: String) -> String {
        EmailListItemDisplay.relativeListDate(from: dateString)
    }

    private func olderThan(_ lhs: EmailDetail, _ rhs: EmailDetail) -> Bool {
        let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
        let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
        return left < right
    }
}

// MARK: - Action target bar

public struct ThreadActionTargetBar: View {
    let target: EmailDetail
    let unreadCount: Int
    let onSelectLatestUnread: () -> Void

    public init(target: EmailDetail, unreadCount: Int, onSelectLatestUnread: @escaping () -> Void) {
        self.target = target
        self.unreadCount = unreadCount
        self.onSelectLatestUnread = onSelectLatestUnread
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SharedAppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Actions apply to")
                    .font(.caption2)
                    .secondaryText()
                Text(target.sender_name ?? target.sender)
                    .font(.caption.weight(.semibold))
                    .primaryText()
                    .lineLimit(1)
            }
            Spacer()
            if unreadCount > 1 {
                Button("Latest unread", action: onSelectLatestUnread)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SharedAppTheme.accent)
            }
        }
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .padding(.vertical, 8)
        .background(SharedAppTheme.secondaryBackground.opacity(0.5))
    }
}

// MARK: - Mailbox thread detail screen

public struct EmailThreadDetailScreen: View {
    let summary: EmailThreadSummary
    @State private var conversation: EmailThreadConversation?
    @State private var loadState: EmailThreadLoadState = .idle
    @State private var replyPresentation: ReplyComposerPresentation?
    @State private var hasUnsubscribeAvailable = false
    @State private var isProcessing = false

    public init(summary: EmailThreadSummary) {
        self.summary = summary
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                SharedAppTheme.primaryBackground
                    .ignoresSafeArea()

                switch loadState {
                case .idle, .loading:
                    ProgressView("Loading conversation…")
                        .tint(SharedAppTheme.accent)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not load thread", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                case .loaded:
                    if let conv = conversation, conv.selectedMessage != nil {
                        detailContent(geometry: geometry, conversation: conv)
                    }
                }
            }
        }
        .navigationTitle(summary.latestMessage.subject.isEmpty ? "Thread" : summary.latestMessage.subject)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadThread() }
        .task(id: conversation?.selectedMessageId) {
            hasUnsubscribeAvailable = await EmailReadingActionSupport.hasUnsubscribeOption(
                for: conversation?.selectedMessage
            )
        }
        .sheet(item: $replyPresentation) { presentation in
            EmailReplyComposerView(
                email: presentation.email,
                mode: presentation.mode,
                isCatchUpContext: false
            )
        }
    }

    @ViewBuilder
    private func detailContent(
        geometry: GeometryProxy,
        conversation: EmailThreadConversation
    ) -> some View {
        if let primary = conversation.selectedMessage {
            let allMessagesNewestFirst = conversation.messages.sorted { lhs, rhs in
                let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
                let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
                return left > right
            }

            VStack(spacing: 0) {
                detailHeader(primary)

                if conversation.unreadCount > 1 {
                    ThreadActionTargetBar(
                        target: primary,
                        unreadCount: conversation.unreadCount,
                        onSelectLatestUnread: {
                            let id = EmailThreadConversation.defaultActionTargetId(in: conversation.messages)
                            conversationBinding.wrappedValue.selectMessage(id: id)
                        }
                    )
                }

                EmailThreadConversationWebView(
                    messages: allMessagesNewestFirst,
                    selectedId: conversation.selectedMessageId,
                    onSelectMessage: { id in
                        conversationBinding.wrappedValue.selectMessage(id: id)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                EmailReadingActionBar(
                    email: primary,
                    isDisabled: isProcessing,
                    hasUnsubscribe: $hasUnsubscribeAvailable,
                    handlers: handlers(for: primary)
                )
            }
        }
    }

    private func detailHeader(_ email: EmailDetail) -> some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingSmall) {
            HStack {
                Text(email.sender_name ?? email.sender)
                    .font(.system(size: 18, weight: .semibold))
                    .primaryText()
                Spacer()
                Text(formatCompactDate(email.received_at))
                    .font(.system(size: 14, weight: .medium))
                    .secondaryText()
            }

            Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                .font(.system(size: 16, weight: .medium))
                .primaryText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            if let recipientsTo = email.recipients_to, !recipientsTo.isEmpty {
                Text("To: \(recipientsTo)")
                    .font(.system(size: 14))
                    .secondaryText()
            }
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(Color(hex: "#252525"))
    }

    private var conversationBinding: Binding<EmailThreadConversation> {
        Binding(
            get: { conversation ?? EmailThreadConversation(key: summary.key, summary: summary) },
            set: { conversation = $0 }
        )
    }

    private func handlers(for detail: EmailDetail) -> EmailReadingActionHandlers {
        EmailReadingActionHandlers(
            onReply: { openReply(mode: .reply, for: detail) },
            onReplyAll: { openReply(mode: .replyAll, for: detail) },
            onStar: { Task { await handleStar(detail) } },
            onMarkUnread: { Task { await handleMarkUnread(detail) } },
            onMarkAsRead: { Task { await handleMarkAsRead(detail) } },
            onUnsubscribe: { Task { await handleUnsubscribe(detail) } }
        )
    }

    private func loadThread() async {
        loadState = .loading
        do {
            let loaded = try await ThreadConversationService.shared.loadConversation(
                key: summary.key,
                summary: summary
            )
            conversation = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func openReply(mode: ReplyMode, for detail: EmailDetail) {
        replyPresentation = ReplyComposerPresentation(email: detail, mode: mode)
    }

    private func handleStar(_ detail: EmailDetail) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let newStar = !detail.is_starred
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: detail.id,
            gmailId: detail.gmail_id,
            accountEmail: detail.account_email,
            shouldStar: newStar
        )
        let updated = detail.updating(isStarred: newStar)
        await EmailCache.shared.saveEmailDetail(updated)
        await DashboardDataManager.shared.updateEmailStarred(emailId: detail.id, isStarred: newStar)
        conversation?.updateMessage(updated)
    }

    private func handleMarkAsRead(_ detail: EmailDetail) async {
        guard !isProcessing, !detail.is_read else { return }
        isProcessing = true
        defer { isProcessing = false }
        await EmailActionSynchronizer.shared.enqueueMarkRead(
            emailId: detail.id,
            gmailId: detail.gmail_id,
            accountEmail: detail.account_email
        )
        let updated = detail.updating(isRead: true)
        await EmailCache.shared.saveEmailDetail(updated)
        await DashboardDataManager.shared.markEmailAsRead(emailId: detail.id)
        conversation?.updateMessage(updated)
    }

    private func handleMarkUnread(_ detail: EmailDetail) async {
        guard !isProcessing, detail.is_read else { return }
        isProcessing = true
        defer { isProcessing = false }
        await EmailActionSynchronizer.shared.enqueueMarkUnread(
            emailId: detail.id,
            gmailId: detail.gmail_id,
            accountEmail: detail.account_email
        )
        let updated = detail.updating(isRead: false)
        await EmailCache.shared.saveEmailDetail(updated)
        await DashboardDataManager.shared.markEmailAsUnread(emailId: detail.id, accountId: nil)
        conversation?.updateMessage(updated)
    }

    private func handleUnsubscribe(_ detail: EmailDetail) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        guard let method = await UnsubscribeService.shared.getUnsubscribeInfo(
            for: detail,
            accountEmail: detail.account_email
        ) else { return }
        _ = await UnsubscribeService.shared.executeUnsubscribe(
            method: method,
            userEmail: detail.account_email
        )
    }

    private func formatCompactDate(_ dateString: String) -> String {
        EmailListItemDisplay.relativeListDate(from: dateString)
    }
}
