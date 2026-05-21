//
//  EmailThreadReaderView.swift
//  EmptyMyInboxShared
//
//  Shared full-thread reading viewport with action-target selection.
//

import SwiftUI

public struct EmailThreadReaderView: View {
    @Binding public var conversation: EmailThreadConversation
    public let viewportHeight: CGFloat
    public var isActive: Bool = true
    public var showsActionTargetPicker: Bool = true
    public var scrollSignal: Int = 0
    public var scrollStepAmount: CGFloat = 0
    public var onLoadComplete: (() -> Void)?

    @State private var showEarlierMessages = false
    @State private var didInitialScroll = false

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

    private var unreadMessages: [EmailDetail] {
        conversation.messages.filter { !$0.is_read }
    }

    private var readMessages: [EmailDetail] {
        conversation.messages.filter(\.is_read)
    }

    private var useCompactUnreadLayout: Bool {
        unreadMessages.count > 1
    }

    private var unreadSectionHeight: CGFloat {
        useCompactUnreadLayout ? viewportHeight * 0.5 : viewportHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            threadHeader

            if showsActionTargetPicker, let target = conversation.selectedMessage {
                ThreadActionTargetBar(
                    target: target,
                    unreadCount: conversation.unreadCount,
                    onSelectLatestUnread: {
                        let id = EmailThreadConversation.defaultActionTargetId(in: conversation.messages)
                        conversation.selectMessage(id: id)
                    }
                )
            }

            threadScrollContent
        }
        .background(Color(hex: "#252525"))
        .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(SharedAppTheme.accent.opacity(isActive ? 1 : 0.35), lineWidth: 2)
        )
    }

    // MARK: - Header

    private var threadHeader: some View {
        let latest = conversation.messages.last
        return VStack(alignment: .leading, spacing: SharedAppTheme.spacingExtraSmall) {
            HStack {
                Text(latest.map { $0.sender_name ?? $0.sender } ?? "Conversation")
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
                if let latest {
                    Text(formatCompactDate(latest.received_at))
                        .font(.system(size: 14, weight: .medium))
                        .secondaryText()
                }
            }
            Text(latest?.subject.isEmpty == false ? (latest?.subject ?? "") : "(No Subject)")
                .font(.system(size: 16, weight: .medium))
                .primaryText()
                .lineLimit(2)
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(Color(hex: "#1e1e1e"))
    }

    // MARK: - Scroll

    @ViewBuilder
    private var threadScrollContent: some View {
        #if os(macOS)
        ScrollViewReader { proxy in
            scrollBody
                .onChange(of: scrollSignal) { _, _ in
                    guard scrollStepAmount != 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(scrollAnchorId, anchor: scrollStepAmount > 0 ? .bottom : .top)
                    }
                }
                .onAppear {
                    scrollToInitialUnread(proxy: proxy)
                }
                .onChange(of: conversation.selectedMessageId) { _, newId in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("msg-\(newId)", anchor: .center)
                    }
                }
        }
        #else
        ScrollViewReader { proxy in
            scrollBody
                .onAppear {
                    scrollToInitialUnread(proxy: proxy)
                }
                .onChange(of: conversation.selectedMessageId) { _, newId in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("msg-\(newId)", anchor: .center)
                    }
                }
        }
        #endif
    }

    private var scrollBody: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if !readMessages.isEmpty && !showEarlierMessages && conversation.messages.count > 3 {
                    Button {
                        withAnimation { showEarlierMessages = true }
                    } label: {
                        Label("Show \(readMessages.count) earlier message\(readMessages.count == 1 ? "" : "s")", systemImage: "chevron.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SharedAppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                let visibleRead = showEarlierMessages ? readMessages : []
                ForEach(visibleRead, id: \.id) { message in
                    messageCard(message, isUnread: false)
                }

                ForEach(unreadMessages, id: \.id) { message in
                    messageCard(message, isUnread: true)
                }
            }
            .padding(SharedAppTheme.spacingSmall)
        }
        .frame(maxHeight: max(200, viewportHeight - 120))
    }

    private var scrollAnchorId: String {
        "msg-\(conversation.selectedMessageId)"
    }

    private func scrollToInitialUnread(proxy: ScrollViewProxy) {
        guard !didInitialScroll else { return }
        didInitialScroll = true
        let targetId = EmailThreadConversation.defaultActionTargetId(in: conversation.messages)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("msg-\(targetId)", anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func messageCard(_ message: EmailDetail, isUnread: Bool) -> some View {
        let isTarget = conversation.selectedMessageId == message.id
        let maxH = isUnread && useCompactUnreadLayout ? unreadSectionHeight : nil

        EmailThreadMessageCard(
            message: message,
            isUnread: isUnread,
            isActionTarget: isTarget,
            maxHeight: maxH,
            onLoadComplete: message.id == conversation.selectedMessageId ? onLoadComplete : nil
        )
        .id("msg-\(message.id)")
        .onTapGesture {
            conversation.selectMessage(id: message.id)
        }
    }

    private func formatCompactDate(_ dateString: String) -> String {
        EmailListItemDisplay.relativeListDate(from: dateString)
    }
}

// MARK: - Action target bar

public struct ThreadActionTargetBar: View {
    let target: EmailDetail
    let unreadCount: Int
    let onSelectLatestUnread: () -> Void

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

// MARK: - Message card

public struct EmailThreadMessageCard: View {
    let message: EmailDetail
    let isUnread: Bool
    let isActionTarget: Bool
    var maxHeight: CGFloat?
    var onLoadComplete: (() -> Void)?

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.sender_name ?? message.sender)
                        .font(.subheadline.weight(isUnread ? .semibold : .regular))
                        .primaryText()
                    Text(formatCompactDate(message.received_at))
                        .font(.caption)
                        .secondaryText()
                }
                Spacer()
                if isActionTarget {
                    Text("Target")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(SharedAppTheme.accent)
                        .clipShape(Capsule())
                } else if isUnread {
                    Circle()
                        .fill(SharedAppTheme.accent)
                        .frame(width: 8, height: 8)
                }
            }

            messageBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous)
                .fill(isUnread ? SharedAppTheme.accent.opacity(0.08) : SharedAppTheme.secondaryBackground.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(
                    isActionTarget ? SharedAppTheme.accent : (isUnread ? SharedAppTheme.accent.opacity(0.35) : Color.clear),
                    lineWidth: isActionTarget ? 2 : 1
                )
        )
    }

    @ViewBuilder
    private var messageBody: some View {
        Group {
            if let html = message.body_html, !html.isEmpty {
                EmailHTMLWebView(htmlContent: html, isDarkMode: false, onLoadComplete: onLoadComplete)
            } else if !message.body_text.isEmpty {
                if EmailThreadMessageCard.looksLikeHTML(message.body_text) {
                    EmailHTMLWebView(htmlContent: message.body_text, isDarkMode: false, onLoadComplete: onLoadComplete)
                } else {
                    Text(message.body_text)
                        .font(.system(size: 14))
                        .primaryText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear { onLoadComplete?() }
                }
            } else {
                Text(message.snippet)
                    .font(.system(size: 14))
                    .secondaryText()
                    .italic()
                    .onAppear { onLoadComplete?() }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func formatCompactDate(_ dateString: String) -> String {
        EmailListItemDisplay.relativeListDate(from: dateString)
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html")
            || (trimmed.hasPrefix("<") && (trimmed.contains("<div") || trimmed.contains("<table") || trimmed.contains("<body")))
    }
}

// MARK: - Standalone thread detail (mailbox navigation)

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
                    if conversation != nil {
                        VStack(spacing: 0) {
                            EmailThreadReaderView(
                                conversation: conversationBinding,
                                viewportHeight: geometry.size.height * 0.75,
                                showsActionTargetPicker: true
                            )
                            .padding(.horizontal, SharedAppTheme.spacingMedium)
                            .padding(.top, SharedAppTheme.spacingSmall)

                            if let target = conversation?.selectedMessage {
                                EmailReadingActionBar(
                                    email: target,
                                    isDisabled: isProcessing,
                                    hasUnsubscribe: $hasUnsubscribeAvailable,
                                    handlers: handlers(for: target)
                                )
                            }
                        }
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
}
