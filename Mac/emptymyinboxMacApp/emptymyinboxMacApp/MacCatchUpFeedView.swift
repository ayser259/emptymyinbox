//
//  MacCatchUpFeedView.swift
//  emptymyinboxMacApp
//
//  Catch Up: stacked deck with iOS-parity dismiss animation system.
//
//  Animation design (matches CatchUpView.swift on iOS):
//  - All cards rendered through a single unified ZStack
//  - Cards identified by email ID (stable), not index — prevents SwiftUI identity jumps
//  - Dismissed card flies off; remaining cards rise using riseProgress
//  - withAnimation(nil) reset after model updates to prevent snap-back interpolation
//  - isAnimating guard prevents double-triggering
//

import SwiftUI
import EmptyMyInboxShared

struct MacCatchUpFeedView: View {

    @EnvironmentObject private var sidebarShortcutsStore: MacSidebarShortcutsStore
    var onDone: () -> Void = {}

    @StateObject private var loader = LazyEmailLoader()
    @StateObject private var accountOrderStore = CatchUpAccountOrderStore()
    @State private var isProcessing = false
    @State private var hasUnsubscribeAvailable = false
    @State private var showUnsubscribeWebView = false
    @State private var unsubscribeManualURL: URL?
    @State private var showReorderSheet = false
    @State private var replyPresentation: ReplyComposerPresentation?

    // MARK: - Session stats (for completion view)
    @State private var sessionStats = CatchUpSessionStats()
    @State private var sessionStartTime: Date? = nil
    @State private var didPersistSessionMetrics = false
    @State private var todaySendersReceived = 0
    @State private var todayUnsubscribesTotal = 0

    // MARK: - Unified dismiss animation state (iOS-parity)
    @State private var dismissingCardId: Int? = nil
    @State private var dismissOffset: CGSize = .zero
    @State private var dismissRotation: Double = 0
    @State private var dismissOpacity: Double = 1.0
    @State private var riseProgress: CGFloat = 0
    @State private var isAnimating = false

    // MARK: - Live drag tracking (front card only)
    @State private var cardDragOffset: CGSize = .zero

    // MARK: - Arrow-key scroll (front card only)
    @State private var scrollSignal: Int = 0
    @State private var scrollStepAmount: CGFloat = 0
    @StateObject private var keyboardMonitor = MacCatchUpKeyboardMonitor()

    // MARK: - Stack constants
    private let maxVisibleCards = 4
    private let stackOffsetY: CGFloat = 14
    private let stackScaleStep: CGFloat = 0.028
    private let stackOpacityStep: Double = 0.12
    private let swipeTranslationThreshold: CGFloat = 80
    private let swipeVelocityThreshold: CGFloat = 500

    // MARK: - Card info for unified renderer
    private struct CardInfo: Identifiable {
        let id: Int
        let actualIndex: Int
        let displayIndex: Int
    }

    private var visibleCards: [CardInfo] {
        let start = loader.currentIndex
        let end = min(start + maxVisibleCards, loader.catchUpThreads.count)
        var displayIndex = 0
        var cards: [CardInfo] = []
        for i in start..<end {
            let thread = loader.catchUpThreads[i]
            guard !loader.sessionSeenThreadIds.contains(thread.id) else { continue }
            cards.append(CardInfo(id: thread.id, actualIndex: i, displayIndex: displayIndex))
            displayIndex += 1
        }
        return cards
    }

    // MARK: - Root body

    var body: some View {
        Group {
            if loader.isLoadingMetadata {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !loader.hasMoreEmails {
                if sessionStats.reviewed > 0 {
                    MacCatchUpCompletionView(
                        sessionStats: sessionStats,
                        sessionStartTime: sessionStartTime,
                        todaySendersReceived: todaySendersReceived,
                        todayUnsubscribesTotal: todayUnsubscribesTotal,
                        onDone: onDone
                    )
                    .task { await loadCompletionContext() }
                    .onAppear { Task { await persistSessionMetricsIfNeeded() } }
                } else {
                    catchUpEmptyState
                }
            } else {
                MacReplyComposerSlideInContainer(
                    replyPresentation: $replyPresentation,
                    onCatchUpOutcome: { outcome in
                        guard let email = replyPresentation?.email else { return }
                        Task { await handleCatchUpReplyOutcome(outcome, email: email) }
                    }
                ) {
                    GeometryReader { geo in
                        let bottomBarHeight: CGFloat = 168
                        let deckHeight = max(320, geo.size.height - bottomBarHeight - accountGroupBarHeight)
                        VStack(spacing: 0) {
                            accountGroupBar
                            deckStack(deckHeight: deckHeight)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .task(id: loader.currentIndex) {
                                    await loader.loadThread(at: loader.currentIndex)
                                    if loader.currentIndex + 1 < loader.catchUpThreads.count {
                                        await loader.loadThread(at: loader.currentIndex + 1)
                                    }
                                }

                            Divider().opacity(0.35)

                            bottomControls
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(MacAppTheme.secondaryBackground.opacity(0.98))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .navigationTitle("Catch Up")
        .task {
            // Sync account order with live accounts, then load
            let allAccounts = GmailAPIService.shared.getAllAccounts().map { $0.email }
            accountOrderStore.sync(allAccounts: allAccounts)
            loader.accountOrder = accountOrderStore.orderedAccounts
            await loader.loadMetadata()
        }
        .onChange(of: accountOrderStore.orderedAccounts) { _, newOrder in
            loader.accountOrder = newOrder
        }
        .onAppear {
            syncSidebarContextualShortcuts()
            syncKeyboardMonitor()
            keyboardMonitor.installIfNeeded()
        }
        .sheet(isPresented: $showReorderSheet) {
            AccountReorderSheet(store: accountOrderStore)
        }
        .onDisappear {
            keyboardMonitor.remove()
            sidebarShortcutsStore.removeLayers(withPrefix: "catchup.")
        }
        .onChange(of: loader.isLoadingMetadata) { _, _ in syncSidebarContextualShortcuts() }
        .onChange(of: loader.hasMoreEmails) { _, _ in syncSidebarContextualShortcuts() }
        .onChange(of: hasUnsubscribeAvailable) { _, _ in syncSidebarContextualShortcuts() }
        .onChange(of: loader.currentEmail?.id) { _, _ in
            scrollSignal = 0
            scrollStepAmount = 0
            syncSidebarContextualShortcuts()
            syncKeyboardMonitor()
        }
        .onChange(of: replyPresentation?.id) { _, _ in
            syncSidebarContextualShortcuts()
            syncKeyboardMonitor()
        }
        .onChange(of: isAnimating) { _, _ in syncKeyboardMonitor() }
        .onChange(of: loader.hasMoreEmails) { _, _ in syncKeyboardMonitor() }
        .onChange(of: hasUnsubscribeAvailable) { _, _ in syncKeyboardMonitor() }
        .onChange(of: isProcessing) { _, _ in syncKeyboardMonitor() }
        .onChange(of: loader.isCurrentLoaded) { _, _ in syncKeyboardMonitor() }
        .sheet(isPresented: $showUnsubscribeWebView) {
            if let url = unsubscribeManualURL { UnsubscribeWebView(url: url) }
        }
    }

    // MARK: - Account group bar

    private let accountGroupBarHeight: CGFloat = 44

    /// Groups emails by account, preserving accountOrderStore order.
    private var groupedCounts: [(account: String, total: Int, remaining: Int)] {
        let order = accountOrderStore.orderedAccounts
        var totalMap: [String: Int] = [:]
        var remainingMap: [String: Int] = [:]
        for (idx, thread) in loader.catchUpThreads.enumerated() {
            guard !loader.sessionSeenThreadIds.contains(thread.id) else { continue }
            totalMap[thread.key.accountEmail, default: 0] += thread.unreadCount
            if idx >= loader.currentIndex {
                remainingMap[thread.key.accountEmail, default: 0] += 1
            }
        }
        let accounts = order.isEmpty ? Array(totalMap.keys.sorted()) : order
        return accounts.compactMap { account in
            guard let total = totalMap[account] else { return nil }
            return (account, total, remainingMap[account] ?? 0)
        }
    }

    private var accountGroupBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groupedCounts, id: \.account) { group in
                        AccountGroupPill(
                            account: group.account,
                            remaining: group.remaining,
                            total: group.total
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()
                .frame(height: 20)
                .opacity(0.4)
                .padding(.horizontal, 4)

            Button {
                showReorderSheet = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reorder accounts")
            .padding(.trailing, 12)
        }
        .frame(height: accountGroupBarHeight)
        .background(MacAppTheme.primaryBackground.opacity(0.85))
    }

    // MARK: - Deck

    private func deckStack(deckHeight: CGFloat) -> some View {
        let cardHeight = deckHeight - stackOffsetY * CGFloat(min(maxVisibleCards - 1, visibleCards.count - 1))
        return ZStack {
            ForEach(visibleCards.reversed()) { cardInfo in
                cardViewFor(cardInfo, cardHeight: cardHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .clipped()
    }

    @ViewBuilder
    private func cardViewFor(_ cardInfo: CardInfo, cardHeight: CGFloat) -> some View {
        let thread = loader.catchUpThreads[cardInfo.actualIndex]
        let isDismissing = dismissingCardId == cardInfo.id
        let displayIndex = cardInfo.displayIndex
        let effectiveDisplayIndex = calcEffectiveDisplayIndex(displayIndex: displayIndex, isDismissing: isDismissing)
        let (yOffset, scale, opacity) = calcCardTransforms(eff: effectiveDisplayIndex)

        let cardOffset: CGSize = {
            if isDismissing { return dismissOffset }
            if displayIndex == 0 { return cardDragOffset }
            return CGSize(width: 0, height: yOffset)
        }()
        let cardRotation: Double = {
            if isDismissing { return dismissRotation }
            if displayIndex == 0 { return Double(cardDragOffset.width / 26) }
            return 0
        }()

        MacCatchUpThreadDeckCard(
            thread: thread,
            conversation: loader.loadedConversations[thread.id],
            conversationBinding: loader.bindingForConversation(threadStableId: thread.id),
            loadState: loader.threadLoadStates[thread.id] ?? .pending,
            cardHeight: cardHeight,
            dragOffset: displayIndex == 0 && !isDismissing ? cardDragOffset : .zero,
            onRetry: {
                Task { await loader.retryCurrentEmail() }
            },
            onSkipFailed: {
                loader.skipCurrentFailedEmail()
            },
            onDragChanged: { translation in
                guard !isAnimating, displayIndex == 0 else { return }
                cardDragOffset = translation
            },
            onDragEnded: { translation, velocity in
                guard !isAnimating, displayIndex == 0 else { return }
                handleDragEnd(translation: translation, velocity: velocity)
            },
            scrollSignal: displayIndex == 0 ? scrollSignal : 0,
            scrollStepAmount: displayIndex == 0 ? scrollStepAmount : 0,
            onConversationChange: { loader.updateCurrentConversation($0) }
        )
        .offset(cardOffset)
        .scaleEffect(isDismissing ? 1.0 : scale)
        .rotationEffect(.degrees(cardRotation))
        .opacity(isDismissing ? dismissOpacity : opacity)
        .zIndex(cardZIndex(displayIndex: displayIndex, isDismissing: isDismissing))
        .allowsHitTesting(displayIndex == 0 && !isDismissing && !isAnimating)
        // Non-dismissing cards animate their rise with a spring; dismissing card: no interpolation
        .animation(
            isDismissing ? nil : .spring(response: 0.35, dampingFraction: 0.75),
            value: effectiveDisplayIndex
        )
    }

    private func calcEffectiveDisplayIndex(displayIndex: Int, isDismissing: Bool) -> CGFloat {
        if isDismissing { return CGFloat(displayIndex) }
        if dismissingCardId != nil {
            return max(0, CGFloat(displayIndex) - riseProgress)
        }
        return CGFloat(displayIndex)
    }

    private func calcCardTransforms(eff: CGFloat) -> (CGFloat, CGFloat, Double) {
        let y = eff * stackOffsetY
        let scale = 1.0 - eff * stackScaleStep
        let opacity = max(0, 1.0 - Double(eff) * stackOpacityStep)
        return (y, scale, opacity)
    }

    private func cardZIndex(displayIndex: Int, isDismissing: Bool) -> Double {
        if isDismissing { return Double(maxVisibleCards + 10) }
        return Double(maxVisibleCards - displayIndex)
    }

    // MARK: - Drag → action bridge

    private func handleDragEnd(translation: CGSize, velocity: CGSize) {
        let tx = translation.width, ty = translation.height
        let vx = velocity.width, vy = velocity.height

        let hStrong = abs(tx) > swipeTranslationThreshold && abs(tx) > abs(ty)
        let hFast   = abs(vx) > swipeVelocityThreshold  && abs(tx) > 30 && abs(tx) > abs(ty)
        let uStrong = ty < -swipeTranslationThreshold    && abs(ty) > abs(tx)
        let uFast   = vy < -swipeVelocityThreshold       && ty < -30    && abs(ty) > abs(tx)

        if hStrong || hFast {
            if tx > 0 {
                Task { await handleMarkAsRead() }
            } else {
                Task { await handleKeepUnread() }
            }
        } else if uStrong || uFast {
            Task { await handleStar() }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                cardDragOffset = .zero
            }
        }
    }

    // MARK: - Core dismiss animation (iOS-parity)

    private enum DismissDirection { case left, right, up }

    private func performDismissalAnimation(cardId: Int, direction: DismissDirection) async {
        dismissingCardId = cardId
        riseProgress = 0
        // Reset drag offset instantly so the spring starts from neutral
        withAnimation(nil) { cardDragOffset = .zero }

        let exitW: CGFloat = 1600
        let exitH: CGFloat = 1000

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            switch direction {
            case .left:
                dismissOffset = CGSize(width: -exitW * 1.3, height: 0)
                dismissRotation = -15
            case .right:
                dismissOffset = CGSize(width: exitW * 1.3, height: 0)
                dismissRotation = 15
            case .up:
                dismissOffset = CGSize(width: 0, height: -exitH)
                dismissRotation = 5
            }
            dismissOpacity = 0
            riseProgress = 1.0
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    private func resetAnimationState() {
        withAnimation(nil) {
            dismissingCardId = nil
            dismissOffset = .zero
            dismissRotation = 0
            dismissOpacity = 1.0
            riseProgress = 0
        }
    }

    // MARK: - Bottom controls

    private var isButtonsDisabled: Bool { isProcessing || !loader.isCurrentLoaded || isAnimating }

    private var isReplyAllMeaningful: Bool {
        guard let email = loader.currentEmail else { return false }
        return ReplyRecipientResolver.isReplyAllMeaningful(email: email)
    }

    private var catchUpReadingHandlers: EmailReadingActionHandlers {
        EmailReadingActionHandlers(
            onReply: { Task { await handleReply(mode: .reply) } },
            onReplyAll: { Task { await handleReply(mode: .replyAll) } },
            onStar: { Task { await handleStar() } },
            onMarkUnread: { Task { await handleKeepUnread() } },
            onMarkAsRead: { Task { await handleMarkAsRead() } },
            onUnsubscribe: { Task { await handleUnsubscribe() } }
        )
    }

    private var bottomControls: some View {
        EmailReadingCatchUpActionBar(
            email: loader.currentEmail,
            remainingCount: loader.remainingCount,
            isDisabled: isButtonsDisabled,
            isAnimating: isAnimating,
            hasUnsubscribe: $hasUnsubscribeAvailable,
            handlers: catchUpReadingHandlers
        )
    }

    // MARK: - Sidebar shortcuts

    private func syncSidebarContextualShortcuts() {
        guard !loader.isLoadingMetadata, loader.hasMoreEmails else {
            sidebarShortcutsStore.removeLayers(withPrefix: "catchup.")
            return
        }
        if replyPresentation != nil {
            sidebarShortcutsStore.removeLayer(id: "catchup.triage")
            sidebarShortcutsStore.setLayer(
                id: "catchup.replyComposer",
                title: "Reply composer",
                shortcuts: MacSidebarShortcutLibrary.mailReplyComposer,
                priority: 30
            )
            return
        }
        sidebarShortcutsStore.removeLayer(id: "catchup.replyComposer")

        var items: [MacSidebarContextualShortcut] = [
            MacSidebarContextualShortcut(title: "Review Later", shortcutDisplay: "F"),
            MacSidebarContextualShortcut(title: "Star", shortcutDisplay: "S"),
            MacSidebarContextualShortcut(title: "Mark as read", shortcutDisplay: "J"),
            MacSidebarContextualShortcut(title: "Reply", shortcutDisplay: "R"),
        ]
        if isReplyAllMeaningful {
            items.append(MacSidebarContextualShortcut(title: "Reply All", shortcutDisplay: "⇧R"))
        }
        if hasUnsubscribeAvailable {
            items.append(MacSidebarContextualShortcut(title: "Unsubscribe", shortcutDisplay: "⌘⇧U"))
        }
        sidebarShortcutsStore.setLayer(
            id: "catchup.triage",
            title: "Catch Up",
            shortcuts: items,
            priority: 20
        )
    }

    // MARK: - Unsubscribe probe

    // MARK: - Action handlers

    private func syncKeyboardMonitor() {
        keyboardMonitor.isReplyComposerOpen = replyPresentation != nil
        keyboardMonitor.isButtonsDisabled = isButtonsDisabled
        keyboardMonitor.hasMoreEmails = loader.hasMoreEmails
        keyboardMonitor.isAnimating = isAnimating
        keyboardMonitor.hasUnsubscribe = hasUnsubscribeAvailable
        keyboardMonitor.isReplyAllMeaningful = isReplyAllMeaningful
        keyboardMonitor.onReply = { Task { await handleReply(mode: .reply) } }
        keyboardMonitor.onReplyAll = { Task { await handleReply(mode: .replyAll) } }
        keyboardMonitor.onKeepUnread = { Task { await handleKeepUnread() } }
        keyboardMonitor.onStar = { Task { await handleStar() } }
        keyboardMonitor.onMarkAsRead = { Task { await handleMarkAsRead() } }
        keyboardMonitor.onUnsubscribe = { Task { await handleUnsubscribe() } }
        keyboardMonitor.onScrollDown = {
            scrollStepAmount = 160
            scrollSignal += 1
        }
        keyboardMonitor.onScrollUp = {
            scrollStepAmount = -160
            scrollSignal += 1
        }
    }

    private func recordFirstAction() {
        if sessionStartTime == nil { sessionStartTime = Date() }
    }

    private var catchUpEmptyState: some View {
        VStack(spacing: 20) {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("No unread emails in this view.")
            }
            Button("Back to Dashboard", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(MacAppTheme.accent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCompletionContext() async {
        let todayMetric = await InboxMetricsStore.shared.metric(forDayContaining: Date())
        await MainActor.run {
            todaySendersReceived = todayMetric?.uniqueSendersReceived ?? sessionStats.reviewedSenders.count
            todayUnsubscribesTotal = todayMetric?.successfulUnsubscribes ?? sessionStats.successfulUnsubscribes
        }
    }

    private func persistSessionMetricsIfNeeded() async {
        guard !didPersistSessionMetrics, sessionStats.reviewed > 0 else { return }
        didPersistSessionMetrics = true
        await InboxMetricsStore.shared.recordCatchUpSession(
            stats: sessionStats,
            sessionStart: sessionStartTime
        )
        await loadCompletionContext()
    }

    private func recordSenderForReviewedEmail(_ email: EmailDetail) {
        sessionStats.reviewedSenders.insert(email.sender.lowercased())
        if hasUnsubscribeAvailable {
            sessionStats.potentialUnsubscribeSenders.insert(email.sender.lowercased())
        }
    }

    private func handleReply(mode: ReplyMode = .reply) async {
        guard let email = loader.currentEmail else { return }
        await MainActor.run {
            replyPresentation = ReplyComposerPresentation(email: email, mode: mode, isCatchUpContext: true)
            syncSidebarContextualShortcuts()
        }
    }

    private func handleCatchUpReplyOutcome(_ outcome: CatchUpReplyOutcome, email: EmailDetail) async {
        sessionStats.repliesSent += 1
        switch outcome {
        case .markReadAndAdvance:
            guard !isAnimating else { return }
            isProcessing = true
            isAnimating = true
            await markUnreadMessagesReadInCurrentThread(fallback: email, animateDismiss: true)
            sessionStats.reviewed += 1
            sessionStats.markedAsRead += 1
            recordSenderForReviewedEmail(email)
            resetAnimationState()
            isProcessing = false
            isAnimating = false
        case .keepUnreadAndAdvance:
            guard !isAnimating else { return }
            isAnimating = true
            let threadCardId = loader.currentThread?.id ?? email.id
            await performDismissalAnimation(cardId: threadCardId, direction: .left)
            loader.moveToNext()
            sessionStats.reviewed += 1
            sessionStats.keptUnread += 1
            recordSenderForReviewedEmail(email)
            resetAnimationState()
            isAnimating = false
        case .stay:
            break
        }
    }

    private func handleStar() async {
        guard let email = loader.currentEmail, !isAnimating else { return }
        recordFirstAction()
        isProcessing = true
        isAnimating = true

        let threadCardId = loader.currentThread?.id ?? email.id
        await performDismissalAnimation(cardId: threadCardId, direction: .up)

        let newStar = !email.is_starred
        loader.removeCurrentThread()
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStar
        )
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStar)

        sessionStats.reviewed += 1
        sessionStats.starred += 1
        recordSenderForReviewedEmail(email)

        resetAnimationState()
        isProcessing = false
        isAnimating = false
    }

    private func handleKeepUnread() async {
        guard loader.currentEmail != nil, !isAnimating else { return }
        guard let email = loader.currentEmail else { return }
        recordFirstAction()
        isAnimating = true

        let threadCardId = loader.currentThread?.id ?? email.id
        await performDismissalAnimation(cardId: threadCardId, direction: .left)

        loader.moveToNext()

        sessionStats.reviewed += 1
        sessionStats.keptUnread += 1
        recordSenderForReviewedEmail(email)

        resetAnimationState()
        isAnimating = false
    }

    private func handleMarkAsRead() async {
        guard let email = loader.currentEmail, !isAnimating else { return }
        recordFirstAction()
        isProcessing = true
        isAnimating = true

        await markUnreadMessagesReadInCurrentThread(fallback: email, animateDismiss: true)

        sessionStats.reviewed += 1
        sessionStats.markedAsRead += 1
        recordSenderForReviewedEmail(email)

        resetAnimationState()
        isProcessing = false
        isAnimating = false
    }
    
    private func markUnreadMessagesReadInCurrentThread(fallback: EmailDetail, animateDismiss: Bool) async {
        let unreadMessages = loader.currentConversation?.messages.filter { !$0.is_read } ?? [fallback]
        let threadCardId = loader.currentThread?.id ?? fallback.id

        if animateDismiss {
            await performDismissalAnimation(cardId: threadCardId, direction: .right)
        }

        for message in unreadMessages {
            await EmailActionSynchronizer.shared.enqueueMarkRead(
                emailId: message.id,
                gmailId: message.gmail_id,
                accountEmail: message.account_email
            )
            await DashboardDataManager.shared.markEmailAsRead(emailId: message.id)
            let updated = message.updating(isRead: true)
            await EmailCache.shared.saveEmailDetail(updated)
        }

        loader.markMessagesReadInCurrentThread(emailIds: unreadMessages.map(\.id))
    }

    private func handleUnsubscribe() async {
        guard let email = loader.currentEmail, !isAnimating else { return }
        recordFirstAction()
        isProcessing = true
        isAnimating = true

        if let method = await UnsubscribeService.shared.getUnsubscribeInfo(for: email, accountEmail: email.account_email) {
            let result = await UnsubscribeService.shared.executeUnsubscribe(method: method, userEmail: email.account_email)
            if result.success {
                sessionStats.potentialUnsubscribeSenders.insert(email.sender.lowercased())
                if result.requiresManualAction, let url = result.manualActionURL {
                    await MainActor.run { unsubscribeManualURL = url; showUnsubscribeWebView = true }
                } else {
                    let threadCardId = loader.currentThread?.id ?? email.id
                    await performDismissalAnimation(cardId: threadCardId, direction: .right)
                    loader.removeCurrentThread()
                    sessionStats.reviewed += 1
                    sessionStats.successfulUnsubscribes += 1
                    recordSenderForReviewedEmail(email)
                    resetAnimationState()
                }
            } else if let url = result.manualActionURL {
                await MainActor.run { unsubscribeManualURL = url; showUnsubscribeWebView = true }
            }
        }

        isProcessing = false
        isAnimating = false
    }
}

// MARK: - Thread deck card

private struct MacCatchUpThreadDeckCard: View {
    let thread: CatchUpThreadItem
    let conversation: EmailThreadConversation?
    let conversationBinding: Binding<EmailThreadConversation>?
    let loadState: EmailLoadState
    let cardHeight: CGFloat
    let dragOffset: CGSize
    let onRetry: () -> Void
    let onSkipFailed: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize, CGSize) -> Void
    var scrollSignal: Int = 0
    var scrollStepAmount: CGFloat = 0
    let onConversationChange: (EmailThreadConversation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swipeHintBar

            Group {
                switch loadState {
                case .loaded:
                    if let binding = conversationBinding {
                        EmailThreadReaderView(
                            conversation: binding,
                            viewportHeight: cardHeight - 48,
                            scrollSignal: scrollSignal,
                            scrollStepAmount: scrollStepAmount
                        )
                        .onChange(of: binding.wrappedValue.selectedMessageId) { _, _ in
                            onConversationChange(binding.wrappedValue)
                        }
                    } else if let conversation {
                        EmailThreadReaderView(
                            conversation: .constant(conversation),
                            viewportHeight: cardHeight - 48,
                            scrollSignal: scrollSignal,
                            scrollStepAmount: scrollStepAmount
                        )
                    }
                case .loading, .pending:
                    ProgressView("Loading conversation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    VStack(spacing: 12) {
                        Text("Could not load this conversation")
                            .font(.subheadline)
                            .foregroundStyle(MacAppTheme.secondaryText)
                        HStack(spacing: 10) {
                            Button("Retry", action: onRetry)
                                .buttonStyle(.borderedProminent)
                            Button("Skip", action: onSkipFailed)
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in onDragChanged(v.translation) }
                    .onEnded { v in onDragEnded(v.translation, v.velocity) }
            )
        }
        .frame(height: cardHeight, alignment: .top)
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var swipeHintBar: some View {
        let tint: Color = {
            if dragOffset.width > 18 { return .green }
            if dragOffset.width < -18 { return .orange }
            if dragOffset.height < -18 { return MacAppTheme.accent }
            return .clear
        }()
        return tint
            .frame(height: 4)
            .animation(.easeInOut(duration: 0.1), value: dragOffset.width)
    }
}

// MARK: - Legacy single-message deck card

private struct MacCatchUpDeckCard: View {
    let metadata: EmailMetadata
    let detail: EmailDetail?
    let loadState: EmailLoadState
    let cardHeight: CGFloat
    let dragOffset: CGSize
    let onRetry: () -> Void
    let onSkipFailed: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize, CGSize) -> Void
    /// Arrow-key scroll signal forwarded to the embedded WKWebView (front card only).
    var scrollSignal: Int = 0
    var scrollStepAmount: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swipeHintBar

            metadataHeader
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in onDragChanged(v.translation) }
                        .onEnded { v in onDragEnded(v.translation, v.velocity) }
                )

            Divider().opacity(0.35)
            bodySection
        }
        .frame(height: cardHeight, alignment: .top)
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall)
                .stroke(MacAppTheme.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    // Thin coloured bar at the top that hints swipe direction
    private var swipeHintBar: some View {
        let tint: Color = {
            if dragOffset.width > 18 { return .green }
            if dragOffset.width < -18 { return .orange }
            if dragOffset.height < -18 { return MacAppTheme.accent }
            return .clear
        }()
        return tint
            .frame(height: 4)
            .animation(.easeInOut(duration: 0.1), value: dragOffset.width)
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerSubject)
                .font(.headline)
                .foregroundStyle(MacAppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            metadataRow(label: "From", value: headerFrom)

            if let to = detail?.recipients_to, !to.isEmpty {
                metadataRow(label: "To", value: to)
            }
            if let cc = detail?.recipients_cc, !cc.isEmpty {
                metadataRow(label: "Cc", value: cc)
            }

            HStack {
                Text(headerDate)
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
                Spacer()
                Text(metadata.account_email)
                    .font(.caption2)
                    .foregroundStyle(MacAppTheme.secondaryText.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppTheme.primaryBackground.opacity(0.35))
        .contentShape(Rectangle())
    }

    private var headerSubject: String {
        let s = detail?.subject ?? metadata.subject
        return s.isEmpty ? "(No subject)" : s
    }

    private var headerFrom: String {
        if let d = detail {
            if let name = d.sender_name, !name.isEmpty { return "\(name) <\(d.sender)>" }
            return d.sender
        }
        return metadata.sender
    }

    private var headerDate: String { formattedSent(detail?.received_at ?? metadata.received_at) }

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacAppTheme.secondaryText)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(MacAppTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        switch loadState {
        case .pending, .loading:
            ProgressView("Loading message…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        case .failed:
            VStack(spacing: 10) {
                Text("Could not load this message.")
                    .foregroundStyle(MacAppTheme.secondaryText)
                HStack {
                    Button("Retry", action: onRetry).buttonStyle(.borderedProminent).tint(MacAppTheme.accent)
                    Button("Skip", action: onSkipFailed).buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .loaded:
            if let d = detail { emailBody(d) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    private func emailBody(_ detail: EmailDetail) -> some View {
        Group {
            if let html = detail.body_html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmailHTMLWebView(htmlContent: html, isDarkMode: false,
                                 scrollSignal: scrollSignal, scrollStepAmount: scrollStepAmount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !detail.body_text.isEmpty {
                if looksLikeHTML(detail.body_text) {
                    EmailHTMLWebView(htmlContent: detail.body_text, isDarkMode: false,
                                     scrollSignal: scrollSignal, scrollStepAmount: scrollStepAmount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(detail.body_text)
                            .font(.body).foregroundStyle(MacAppTheme.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    Text(detail.snippet)
                        .font(.body).italic().foregroundStyle(MacAppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func looksLikeHTML(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("<!doctype") || t.hasPrefix("<html") { return true }
        return t.hasPrefix("<") && (t.contains("<div") || t.contains("<table") || t.contains("<body"))
    }

    private func formattedSent(_ iso: String) -> String {
        let d = ISO8601DateFormatter().date(from: iso) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"; return f.date(from: iso)
        }()
        guard let d else { return iso }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Account group pill (progress indicator)

private struct AccountGroupPill: View {
    let account: String
    let remaining: Int
    let total: Int

    private var isDone: Bool { remaining == 0 }
    private var isCurrent: Bool { remaining > 0 && remaining == total }

    private var shortName: String {
        // Use the portion before '@' for brevity
        account.components(separatedBy: "@").first ?? account
    }

    var body: some View {
        HStack(spacing: 5) {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(MacAppTheme.accent)
            } else {
                Circle()
                    .fill(isCurrent ? MacAppTheme.accent : MacAppTheme.secondaryText.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
            Text(shortName)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isDone
                                 ? MacAppTheme.secondaryText.opacity(0.5)
                                 : (isCurrent ? MacAppTheme.primaryText : MacAppTheme.secondaryText))
                .lineLimit(1)
            if !isDone {
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? MacAppTheme.accent : MacAppTheme.secondaryText.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isCurrent
                      ? MacAppTheme.accent.opacity(0.12)
                      : MacAppTheme.secondaryBackground.opacity(0.6))
        )
        .overlay(
            Capsule()
                .strokeBorder(isCurrent ? MacAppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Reorder sheet

private struct AccountReorderSheet: View {
    @ObservedObject var store: CatchUpAccountOrderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Account Order")
                    .font(.headline)
                    .foregroundStyle(MacAppTheme.primaryText)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacAppTheme.accent)
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            Text("Drag to set the order emails are reviewed in Catch Up.")
                .font(.caption)
                .foregroundStyle(MacAppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List {
                ForEach(store.orderedAccounts, id: \.self) { account in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(MacAppTheme.secondaryText)
                            .font(.system(size: 14))
                        Image(systemName: "envelope.circle")
                            .foregroundStyle(MacAppTheme.accent)
                        Text(account)
                            .font(.body)
                            .foregroundStyle(MacAppTheme.primaryText)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { from, to in
                    store.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(MacAppTheme.primaryBackground)
    }
}

