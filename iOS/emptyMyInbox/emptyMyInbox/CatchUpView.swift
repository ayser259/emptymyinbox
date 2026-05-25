//
//  CatchUpView.swift
//  emptyMyInbox
//
//  Slack-style catch up view for processing unread emails
//  Uses progressive loading - emails are fetched on-demand as user swipes
//
//  Card Animation Design:
//  - All cards rendered through a single unified system
//  - Cards identified by ID, not index (prevents animation jumps)
//  - Dismissed card flies off, remaining cards rise up from deck
//  - New cards always appear from below (stack position) never from sides
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import EmptyMyInboxShared

struct CatchUpView: View {
    let accountId: Int?
    let accountEmail: String?
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var debugSettings = DebugSettings.shared
    
    // Use the new lazy loader
    @StateObject private var emailLoader: LazyEmailLoader
    
    // MARK: - Animation State (Unified System)
    
    /// ID of the card currently being dismissed (nil when idle)
    @State private var dismissingCardId: Int? = nil
    
    /// Offset for the dismissing card
    @State private var dismissOffset: CGSize = .zero
    
    /// Rotation for the dismissing card
    @State private var dismissRotation: Double = 0
    
    /// Opacity for the dismissing card
    @State private var dismissOpacity: Double = 1
    
    /// Progress of remaining cards rising up (0 = stacked, 1 = promoted)
    @State private var riseProgress: CGFloat = 0
    
    /// Prevents multiple simultaneous actions
    @State private var isAnimating = false
    @State private var isProcessing = false
    
    // Unsubscribe availability
    @State private var hasUnsubscribeAvailable = false
    
    // Toast state
    @State private var showLoadedToast = false
    @State private var loadedEmailCount = 0
    @State private var showUnsubscribeToast = false
    @State private var unsubscribeToastMessage = ""
    @State private var unsubscribeToastIsSuccess = false
    @State private var unsubscribeManualURL: URL? = nil
    @State private var showUnsubscribeWebView = false
    @State private var currentLoadRetryCount = 0
    @State private var replyPresentation: ReplyComposerPresentation?
    
    // Session tracking
    @State private var sessionStartTime: Date?
    @State private var sessionStats = CatchUpSessionStats()
    @State private var didPersistSessionMetrics = false
    @State private var todaySendersReceived = 0
    @State private var todayUnsubscribesTotal = 0
    
    // Haptic generators (iOS only)
    #if os(iOS)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    #endif
    
    /// Maximum cards to render in the deck (for performance)
    private let maxVisibleCards = 4

    /// Visual offset between stacked cards (in points)
    private let stackOffsetY: CGFloat = 10
    
    /// Scale reduction per card in stack
    private let stackScaleStep: CGFloat = 0.025
    
    /// Opacity reduction per card in stack
    private let stackOpacityStep: Double = 0.12
    
    init(accountId: Int? = nil, accountEmail: String? = nil) {
        self.accountId = accountId
        self.accountEmail = accountEmail
        _emailLoader = StateObject(wrappedValue: LazyEmailLoader(accountId: accountId, accountEmail: accountEmail))
    }
    
    var body: some View {
        ZStack {
            SharedAppTheme.primaryBackground
                .ignoresSafeArea()
            
            mainContent
            
            // Toast overlay
            toastOverlay
            unsubscribeToastOverlay
        }
        .navigationTitle(accountEmail.map { "Catch Up (\($0))" } ?? "Catch Up")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .customBackButton()
        #endif
        .sheet(isPresented: $showUnsubscribeWebView) {
            if let url = unsubscribeManualURL {
                UnsubscribeWebView(url: url)
            }
        }
        .sheet(item: $replyPresentation) { presentation in
            EmailReplyComposerView(
                email: presentation.email,
                mode: presentation.mode,
                isCatchUpContext: true,
                onCatchUpOutcome: { outcome in
                    Task { await handleCatchUpReplyOutcome(outcome, email: presentation.email) }
                }
            )
        }
        .task {
            await onAppear()
        }
        .onChange(of: emailLoader.currentIndex) { _, newIndex in
            currentLoadRetryCount = 0
            Task {
                await emailLoader.loadThread(at: newIndex)
                if newIndex + 1 < emailLoader.catchUpThreads.count {
                    await emailLoader.loadThread(at: newIndex + 1)
                }
            }
        }
    }
    
    @ViewBuilder
    private func threadLoadFailedView(cardHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            Text("Could not load this conversation")
                .font(AppTheme.subheadline)
                .secondaryText()
            HStack(spacing: 10) {
                Button("Retry") {
                    Task { await emailLoader.retryCurrentEmail() }
                }
                .buttonStyle(.borderedProminent)
                Button("Skip") {
                    emailLoader.skipCurrentFailedEmail()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight * 0.5)
    }
    
    // MARK: - Toast Overlay
    
    @ViewBuilder
    private var toastOverlay: some View {
        if showLoadedToast {
            VStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(loadedEmailCount) email\(loadedEmailCount == 1 ? "" : "s") loaded")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.85))
                .cornerRadius(20)
                .padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    }
    
    @ViewBuilder
    private var unsubscribeToastOverlay: some View {
        if showUnsubscribeToast {
            VStack {
                Spacer()
                
                Button {
                    if unsubscribeManualURL != nil {
                        showUnsubscribeWebView = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: unsubscribeToastIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(unsubscribeToastIsSuccess ? .green : .orange)
                            Text(unsubscribeToastIsSuccess ? "Unsubscribed" : "Unsubscribe Failed")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            
                            if unsubscribeManualURL != nil {
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.system(size: 12))
                            }
                        }
                        
                        Text(unsubscribeToastMessage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3)
                        
                        if unsubscribeManualURL != nil {
                            Text("Tap to complete unsubscribe")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(12)
                    .frame(maxWidth: 560)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(101)
        }
    }
    
    // MARK: - Lifecycle
    
    private func onAppear() async {
        #if os(iOS)
        impactLight.prepare()
        impactMedium.prepare()
        notificationGenerator.prepare()
        #endif
        
        // Resume pending actions
        await EmailActionSynchronizer.shared.resumePendingActions()
        
        // Load metadata and start progressive loading
        await emailLoader.loadMetadata()
        
        // Show toast if emails loaded
        if emailLoader.totalEmailCount > 0 {
            loadedEmailCount = emailLoader.totalEmailCount
            withAnimation(.spring(response: 0.3)) {
                showLoadedToast = true
            }
            
            // Hide toast after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.3)) {
                showLoadedToast = false
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        if emailLoader.isLoadingMetadata {
            loadingView
        } else if !emailLoader.hasMoreEmails {
            if sessionStats.reviewed > 0 {
                CatchUpCompletionView(
                    sessionStats: sessionStats,
                    sessionStartTime: sessionStartTime,
                    todaySendersReceived: todaySendersReceived,
                    todayUnsubscribesTotal: todayUnsubscribesTotal,
                    onDone: { dismiss() }
                )
                .task { await loadCompletionContext() }
                .onAppear { Task { await persistSessionMetricsIfNeeded() } }
            } else {
                catchUpEmptyState
            }
        } else {
            emailDeckView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading emails...")
                .font(SharedAppTheme.body)
                .secondaryText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var catchUpEmptyState: some View {
        VStack(spacing: 20) {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("No unread emails in this view.")
            }
            Button("Return to Dashboard") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(SharedAppTheme.accent)
            .keyboardShortcut(.defaultAction)
            .keyboardShortcut(.return, modifiers: [])
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
    
    // MARK: - Email Deck View
    
    private var emailDeckView: some View {
        VStack(spacing: 0) {
            GeometryReader { deckGeometry in
                let cardHeight = cardViewportHeight(in: deckGeometry)

                ZStack {
                    cardStackSection(cardHeight: cardHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    if emailLoader.currentLoadState == .failed {
                        failedCurrentCardBanner
                            .padding(.horizontal, SharedAppTheme.spacingMedium)
                            .zIndex(50)
                    }

                    if debugSettings.isDebugModeEnabled, let email = emailLoader.currentEmail {
                        VStack {
                            HStack {
                                Spacer()
                                DebugCopyButton(content: email.debugCopyContent)
                                    .padding(.trailing, 16)
                            }
                            Spacer()
                        }
                        .zIndex(60)
                    }
                }
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .opacity(0.35)

            actionButtonsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Height for the front email card inside the reserved deck area (accounts for stacked cards behind).
    private func cardViewportHeight(in deckGeometry: GeometryProxy) -> CGFloat {
        let stackDepth = stackOffsetY * CGFloat(min(maxVisibleCards - 1, max(0, visibleCards.count - 1)))
        let available = deckGeometry.size.height - stackDepth
        return max(200, available)
    }
    
    // MARK: - Unified Card Stack Renderer
    
    /// Single unified renderer for all cards in the deck
    /// Cards are positioned based on their display index and animation state
    private func cardStackSection(cardHeight: CGFloat) -> some View {
        ZStack {
            // Render cards from back to front
            // Use email ID as identity so SwiftUI correctly tracks cards through index changes
            ForEach(visibleCards.reversed(), id: \.id) { cardInfo in
                cardView(cardInfo: cardInfo, cardHeight: cardHeight)
            }
        }
    }
    
    /// Card info for rendering (captures both ID and current display position)
    private struct CardInfo: Identifiable {
        let id: Int           // Email ID - stable identity
        let actualIndex: Int  // Current index in emailMetadata
        let displayIndex: Int // Position in visible stack (0 = front)
    }
    
    /// Cards to render with their display positions
    private var visibleCards: [CardInfo] {
        let startIndex = emailLoader.currentIndex
        let endIndex = min(startIndex + maxVisibleCards, emailLoader.catchUpThreads.count)
        
        return (startIndex..<endIndex).map { actualIndex in
            let thread = emailLoader.catchUpThreads[actualIndex]
            return CardInfo(
                id: thread.id,
                actualIndex: actualIndex,
                displayIndex: actualIndex - startIndex
            )
        }
    }
    
    /// Renders a single card with proper transforms based on its position and animation state
    @ViewBuilder
    private func cardView(cardInfo: CardInfo, cardHeight: CGFloat) -> some View {
        let cardId = cardInfo.id
        let displayIndex = cardInfo.displayIndex
        let actualIndex = cardInfo.actualIndex
        let isDismissing = dismissingCardId == cardId
        
        // Calculate effective position (accounts for rising animation)
        let effectiveDisplayIndex = calculateEffectiveDisplayIndex(
            displayIndex: displayIndex,
            isDismissing: isDismissing
        )
        
        // Calculate transforms
        let (yOffset, scale, opacity) = calculateCardTransforms(effectiveDisplayIndex: effectiveDisplayIndex)
        
        Group {
            if actualIndex < emailLoader.catchUpThreads.count,
               let binding = emailLoader.bindingForConversation(
                   threadStableId: emailLoader.catchUpThreads[actualIndex].id
               ) {
                EmailThreadReaderView(
                    conversation: binding,
                    viewportHeight: cardHeight,
                    isActive: displayIndex == 0 && !isDismissing,
                    onLoadComplete: {
                        if actualIndex == emailLoader.currentIndex && sessionStartTime == nil {
                            sessionStartTime = Date()
                        }
                    }
                )
                .padding(.horizontal, AppTheme.spacingMedium)
                .onChange(of: binding.wrappedValue.selectedMessageId) { _, _ in
                    emailLoader.updateCurrentConversation(binding.wrappedValue)
                }
            } else if emailLoader.threadLoadStates[cardInfo.id] == .failed {
                threadLoadFailedView(cardHeight: cardHeight)
            } else {
                EmailCardSkeleton(cardHeight: cardHeight)
            }
        }
        // Apply transforms based on whether this card is dismissing or staying
        .offset(isDismissing ? dismissOffset : CGSize(width: 0, height: yOffset))
        .scaleEffect(isDismissing ? 1.0 : scale)
        .rotationEffect(.degrees(isDismissing ? dismissRotation : 0))
        .opacity(isDismissing ? dismissOpacity : opacity)
        .zIndex(cardZIndex(displayIndex: displayIndex, isDismissing: isDismissing))
        // Only front card is interactive
        .allowsHitTesting(displayIndex == 0 && !isDismissing)
        // Smooth spring animation for rising cards
        .animation(
            isDismissing ? nil : .spring(response: 0.35, dampingFraction: 0.75),
            value: effectiveDisplayIndex
        )
    }
    
    /// Calculates the effective display index accounting for the rise animation
    private func calculateEffectiveDisplayIndex(displayIndex: Int, isDismissing: Bool) -> CGFloat {
        if isDismissing {
            // Dismissing card stays at its original position (handled separately)
            return CGFloat(displayIndex)
        }
        
        if dismissingCardId != nil {
            // During dismissal, non-dismissing cards rise up
            // Their effective index decreases by riseProgress
            // displayIndex 1 -> 1 - riseProgress (at riseProgress=1, becomes 0)
            // displayIndex 2 -> 2 - riseProgress (at riseProgress=1, becomes 1)
            return max(0, CGFloat(displayIndex) - riseProgress)
        }
        
        return CGFloat(displayIndex)
    }
    
    /// Calculates y-offset, scale, and opacity for a given effective display index
    private func calculateCardTransforms(effectiveDisplayIndex: CGFloat) -> (CGFloat, CGFloat, Double) {
        let yOffset = effectiveDisplayIndex * stackOffsetY
        let scale = 1.0 - effectiveDisplayIndex * stackScaleStep
        let opacity = 1.0 - Double(effectiveDisplayIndex) * stackOpacityStep
        return (yOffset, scale, max(0, opacity))
    }
    
    /// Determines z-index for proper layering (front card on top)
    private func cardZIndex(displayIndex: Int, isDismissing: Bool) -> Double {
        if isDismissing {
            // Dismissing card should be above all others during animation
            return Double(maxVisibleCards + 10)
        }
        // Higher display index = further back = lower z-index
        return Double(maxVisibleCards - displayIndex)
    }
    
    // MARK: - Action Buttons
    
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

    private var actionButtonsSection: some View {
        EmailReadingCatchUpActionBar(
            email: emailLoader.currentEmail,
            remainingCount: emailLoader.remainingCount,
            isDisabled: isButtonDisabled,
            isAnimating: isAnimating,
            hasUnsubscribe: $hasUnsubscribeAvailable,
            handlers: catchUpReadingHandlers
        )
    }

    private func handleReply(mode: ReplyMode) async {
        guard let current = emailLoader.currentEmail else { return }
        await MainActor.run {
            replyPresentation = ReplyComposerPresentation(email: current, mode: mode, isCatchUpContext: true)
        }
    }

    private func handleCatchUpReplyOutcome(_ outcome: CatchUpReplyOutcome, email: EmailDetail) async {
        sessionStats.repliesSent += 1
        switch outcome {
        case .markReadAndAdvance:
            guard !isAnimating else { return }
            isProcessing = true
            isAnimating = true
            await markUnreadMessagesReadInCurrentThread(animateDismiss: true)
            sessionStats.reviewed += 1
            sessionStats.markedAsRead += 1
            recordSenderForReviewedEmail(email)
            resetAnimationState()
            isProcessing = false
            isAnimating = false
        case .keepUnreadAndAdvance:
            guard !isAnimating else { return }
            isAnimating = true
            let threadCardId = emailLoader.currentThread?.id ?? email.id
            await performDismissalAnimation(cardId: threadCardId, direction: .left)
            emailLoader.moveToNext()
            sessionStats.reviewed += 1
            sessionStats.keptUnread += 1
            recordSenderForReviewedEmail(email)
            resetAnimationState()
            isAnimating = false
        case .stay:
            break
        }
    }
    
    private var isButtonDisabled: Bool {
        isProcessing || !emailLoader.isCurrentLoaded || isAnimating
    }
    
    private func markUnreadMessagesReadInCurrentThread(animateDismiss: Bool) async {
        guard let fallback = emailLoader.currentEmail else { return }
        let unreadMessages = emailLoader.currentConversation?.messages.filter { !$0.is_read } ?? [fallback]
        let threadCardId = emailLoader.currentThread?.id ?? fallback.id

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

        emailLoader.markMessagesReadInCurrentThread(emailIds: unreadMessages.map(\.id))
    }

    private var failedCurrentCardBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Could not load this email")
                .font(SharedAppTheme.subheadline)
                .primaryText()
            Text("You can retry loading or skip to the next email.")
                .font(SharedAppTheme.caption)
                .secondaryText()
            HStack(spacing: 10) {
                Button("Retry") {
                    Task { await retryCurrentFailedCard() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)

                Button("Skip") {
                    skipCurrentFailedCard()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharedAppTheme.secondaryBackground)
        .cornerRadius(SharedAppTheme.cornerRadiusMedium)
    }
    
    // MARK: - Action Handlers
    
    private func handleStar() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        let actionStart = Date()
        
        isProcessing = true
        isAnimating = true
        
        #if os(iOS)
        impactMedium.impactOccurred()
        #endif
        
        // Perform dismissal animation (card shoots up)
        let threadCardId = emailLoader.currentThread?.id ?? email.id
        await performDismissalAnimation(cardId: threadCardId, direction: .up)
        
        let newStarState = !email.is_starred
        
        // Update stats
        sessionStats.reviewed += 1
        sessionStats.starred += 1
        recordSenderForReviewedEmail(email)
        
        // Remove from deck AFTER animation completes
        emailLoader.removeCurrentThread()
        
        // Persist user intent before UI flow completes.
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        
        // Reset animation state
        resetAnimationState()
        
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        #endif
        
        isProcessing = false
        isAnimating = false
        Telemetry.event("catchup.action.star", metadata: [
            "remaining_count": "\(emailLoader.remainingCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(actionStart) * 1000))"
        ])
        
    }

    private func retryCurrentFailedCard() async {
        guard emailLoader.currentLoadState == .failed else { return }
        let startedAt = Date()
        await emailLoader.retryCurrentEmail()
        if emailLoader.currentLoadState == .failed {
            currentLoadRetryCount += 1
            Telemetry.event("catchup.card.retry_failed", metadata: [
                "retry_count": "\(currentLoadRetryCount)",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
            if currentLoadRetryCount >= 2 {
                skipCurrentFailedCard()
            }
        } else {
            currentLoadRetryCount = 0
            Telemetry.event("catchup.card.retry_succeeded", metadata: [
                "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
            ])
        }
    }

    private func skipCurrentFailedCard() {
        guard emailLoader.currentLoadState == .failed else { return }
        if let email = emailLoader.currentEmail {
            sessionStats.reviewed += 1
            sessionStats.keptUnread += 1
            recordSenderForReviewedEmail(email)
        } else {
            sessionStats.reviewed += 1
            sessionStats.keptUnread += 1
        }
        emailLoader.skipCurrentFailedEmail()
        currentLoadRetryCount = 0
        Telemetry.event("catchup.card.skipped_failed", metadata: [
            "remaining_count": "\(emailLoader.remainingCount)"
        ])
    }
    
    private func handleKeepUnread() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        let actionStart = Date()
        
        isAnimating = true
        
        #if os(iOS)
        impactLight.impactOccurred()
        #endif
        
        // Perform dismissal animation (card goes left)
        let threadCardId = emailLoader.currentThread?.id ?? email.id
        await performDismissalAnimation(cardId: threadCardId, direction: .left)

        // Update stats
        sessionStats.reviewed += 1
        sessionStats.keptUnread += 1
        if let email = emailLoader.currentEmail {
            recordSenderForReviewedEmail(email)
        }
        
        // Move to next thread AFTER animation
        emailLoader.moveToNext()
        
        // Reset animation state
        resetAnimationState()
        
        isAnimating = false
        Telemetry.event("catchup.action.keep_unread", metadata: [
            "remaining_count": "\(emailLoader.remainingCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(actionStart) * 1000))"
        ])
    }
    
    private func handleMarkAsRead() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        let actionStart = Date()
        
        isProcessing = true
        isAnimating = true
        
        #if os(iOS)
        impactMedium.impactOccurred()
        #endif
        
        // Perform dismissal animation (card goes right)
        // Update stats
        sessionStats.reviewed += 1
        sessionStats.markedAsRead += 1
        recordSenderForReviewedEmail(email)
        
        await markUnreadMessagesReadInCurrentThread(animateDismiss: true)
        
        // Reset animation state
        resetAnimationState()
        
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        #endif
        
        isAnimating = false
        isProcessing = false
        Telemetry.event("catchup.action.mark_read", metadata: [
            "remaining_count": "\(emailLoader.remainingCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(actionStart) * 1000))"
        ])
        
    }
    
    private func handleUnsubscribe() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        let actionStart = Date()
        
        isProcessing = true
        isAnimating = true
        
        #if os(iOS)
        impactMedium.impactOccurred()
        #endif
        
        // Get unsubscribe info
        let unsubscribeService = UnsubscribeService.shared
        if let method = await unsubscribeService.getUnsubscribeInfo(for: email, accountEmail: email.account_email) {
            let result = await unsubscribeService.executeUnsubscribe(
                method: method,
                userEmail: email.account_email
            )
            
            // Log detailed information
            let logMessage = """
            Unsubscribe Result:
            - Success: \(result.success)
            - Method: \(result.verificationInfo)
            - Details: \(result.details ?? "N/A")
            """
            
            if result.success {
                Telemetry.event("catchup.action.unsubscribe_succeeded", metadata: [
                    "manual_required": "\(result.requiresManualAction)"
                ])
                logInfo("✅ Successfully unsubscribed\n\(logMessage)", category: "Unsubscribe")
                #if os(iOS)
                notificationGenerator.notificationOccurred(.success)
                #endif
                
                sessionStats.potentialUnsubscribeSenders.insert(email.sender.lowercased())
                
                // Extract domain from sender email or unsubscribe URL for tracking
                var unsubscribeDomain: String? = nil
                if let method = result.method {
                    switch method {
                    case .http(let url):
                        unsubscribeDomain = url.host
                    case .mailto(let email):
                        // Extract domain from email address
                        if let atIndex = email.firstIndex(of: "@") {
                            unsubscribeDomain = String(email[email.index(after: atIndex)...])
                        }
                    }
                }
                // Fallback to sender email domain if unsubscribe domain not available
                if unsubscribeDomain == nil {
                    if let atIndex = email.sender.firstIndex(of: "@") {
                        unsubscribeDomain = String(email.sender[email.sender.index(after: atIndex)...])
                    }
                }
                
                // Track unique unsubscribe domain
                if let domain = unsubscribeDomain {
                    sessionStats.uniqueUnsubscribeDomains.insert(domain)
                }
                
                // If manual action is required, open web view immediately
                if result.requiresManualAction, let url = result.manualActionURL {
                    await MainActor.run {
                        unsubscribeManualURL = url
                        showUnsubscribeWebView = true
                    }
                    
                    // Still count as reviewed even if manual action is needed
                    // The user has initiated the unsubscribe process
                    sessionStats.reviewed += 1
                    
                    // Don't dismiss the email yet - let user complete unsubscribe first
                    // They can dismiss manually after completing
                } else {
                    // Show success toast with verification info
                    await MainActor.run {
                        unsubscribeToastMessage = result.verificationInfo
                        unsubscribeToastIsSuccess = true
                        unsubscribeManualURL = result.manualActionURL
                        showUnsubscribeToast = true
                    }
                    
                    // Perform dismissal animation (card goes right, similar to mark as read)
                    await performDismissalAnimation(cardId: email.id, direction: .right)
                    
                    // Update stats
                    sessionStats.reviewed += 1
                    sessionStats.successfulUnsubscribes += 1
                    recordSenderForReviewedEmail(email)
                    
                    // Remove from deck AFTER animation
                    emailLoader.removeCurrentThread()
                    
                    // Reset animation state
                    resetAnimationState()
                    
                    // Hide toast after 4 seconds
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showUnsubscribeToast = false
                        }
                    }
                }
            } else {
                Telemetry.event("catchup.action.unsubscribe_failed")
                logError("❌ Failed to unsubscribe\n\(logMessage)", category: "Unsubscribe")
                #if os(iOS)
                notificationGenerator.notificationOccurred(.error)
                #endif
                
                // If manual action URL is available, open it immediately
                if let url = result.manualActionURL {
                    await MainActor.run {
                        unsubscribeManualURL = url
                        showUnsubscribeWebView = true
                    }
                } else {
                    // Show error toast
                    await MainActor.run {
                        unsubscribeToastMessage = result.verificationInfo
                        unsubscribeToastIsSuccess = false
                        showUnsubscribeToast = true
                    }
                    
                    // Hide toast after 3 seconds
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showUnsubscribeToast = false
                        }
                    }
                }
            }
        } else {
            logWarning("⚠️ No unsubscribe method found for this email", category: "Unsubscribe")
            #if os(iOS)
            notificationGenerator.notificationOccurred(.warning)
            #endif
        }
        
        isAnimating = false
        isProcessing = false
        Telemetry.event("catchup.action.unsubscribe_completed", metadata: [
            "remaining_count": "\(emailLoader.remainingCount)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(actionStart) * 1000))"
        ])
    }
    
    // MARK: - Animation Helpers
    
    /// Performs the full dismissal animation: card flies off while others rise
    private func performDismissalAnimation(cardId: Int, direction: DismissDirection) async {
        // Mark which card is being dismissed
        dismissingCardId = cardId
        
        // Reset rise progress
        riseProgress = 0
        
        // Animate card out AND other cards rising simultaneously
        #if os(iOS)
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        #else
        let screenW: CGFloat = 900
        let screenH: CGFloat = 800
        #endif
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            // Set dismissal transforms based on direction
            switch direction {
            case .left:
                dismissOffset = CGSize(width: -screenW * 1.3, height: 0)
                dismissRotation = -15
            case .right:
                dismissOffset = CGSize(width: screenW * 1.3, height: 0)
                dismissRotation = 15
            case .up:
                dismissOffset = CGSize(width: 0, height: -screenH)
                dismissRotation = 5
            }
            dismissOpacity = 0
            
            // Simultaneously animate other cards rising
            riseProgress = 1.0
        }
        
        // Wait for animation to complete
        try? await Task.sleep(nanoseconds: 350_000_000)
    }
    
    /// Resets all animation state after dismissal (without animation to prevent jumps)
    private func resetAnimationState() {
        // Use withAnimation(nil) to instantly reset without interpolation
        withAnimation(nil) {
            dismissingCardId = nil
            dismissOffset = .zero
            dismissRotation = 0
            dismissOpacity = 1
            riseProgress = 0
        }
    }
}

// MARK: - Supporting Types

private enum DismissDirection {
    case left
    case right
    case up
}

#Preview {
    NavigationStack {
        CatchUpView()
            .environmentObject(AuthManager())
    }
}
