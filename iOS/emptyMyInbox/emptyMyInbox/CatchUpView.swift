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
import WebKit
import UIKit

struct CatchUpView: View {
    let accountId: Int?
    let accountEmail: String?
    @EnvironmentObject var authManager: AuthManager
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
    
    // Session tracking
    @State private var sessionStartTime: Date?
    @State private var sessionStats = CatchUpSessionStats()
    
    // Haptic generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
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
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            mainContent
            
            // Toast overlay
            toastOverlay
            unsubscribeToastOverlay
        }
        .navigationTitle(accountEmail.map { "Catch Up (\($0))" } ?? "Catch Up")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton()
        .sheet(isPresented: $showUnsubscribeWebView) {
            if let url = unsubscribeManualURL {
                UnsubscribeWebView(url: url)
            }
        }
        .task {
            await onAppear()
        }
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
                    if let url = unsubscribeManualURL {
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
                    .frame(maxWidth: UIScreen.main.bounds.width - 40)
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
        // Prepare haptic generators
        impactLight.prepare()
        impactMedium.prepare()
        notificationGenerator.prepare()
        
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
            celebrationView
        } else {
            emailDeckView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading emails...")
                .font(AppTheme.body)
                .secondaryText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var celebrationView: some View {
        CelebrationView(
            emailsCleared: sessionStats.reviewed > 0 ? sessionStats.reviewed : nil,
            sessionStartTime: sessionStartTime,
            accountEmail: accountEmail,
            sessionStats: sessionStats.reviewed > 0 ? sessionStats : nil
        )
    }
    
    // MARK: - Email Deck View
    
    private var emailDeckView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    topBarSection
                    cardStackSection(geometry: geometry)
                }
                actionButtonsSection
                
                // Debug copy button overlay
                if debugSettings.isDebugModeEnabled, let email = emailLoader.currentEmail {
                    VStack {
                        HStack {
                            Spacer()
                            DebugCopyButton(content: email.debugCopyContent)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                    .padding(.top, 60) // Below the top bar
                }
            }
        }
    }
    
    private var topBarSection: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Text("\(emailLoader.remainingCount) left to review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                
                if sessionStats.reviewed > 0 {
                    Text("•")
                        .foregroundColor(AppTheme.secondaryText)
                    Text("\(sessionStats.reviewed) reviewed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
    
    // MARK: - Unified Card Stack Renderer
    
    /// Single unified renderer for all cards in the deck
    /// Cards are positioned based on their display index and animation state
    private func cardStackSection(geometry: GeometryProxy) -> some View {
        ZStack {
            // Render cards from back to front
            // Use email ID as identity so SwiftUI correctly tracks cards through index changes
            ForEach(visibleCards.reversed(), id: \.id) { cardInfo in
                cardView(cardInfo: cardInfo, geometry: geometry)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 92)
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
        let endIndex = min(startIndex + maxVisibleCards, emailLoader.emailMetadata.count)
        
        return (startIndex..<endIndex).map { actualIndex in
            let metadata = emailLoader.emailMetadata[actualIndex]
            return CardInfo(
                id: metadata.id,
                actualIndex: actualIndex,
                displayIndex: actualIndex - startIndex
            )
        }
    }
    
    /// Renders a single card with proper transforms based on its position and animation state
    @ViewBuilder
    private func cardView(cardInfo: CardInfo, geometry: GeometryProxy) -> some View {
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
            if let email = emailLoader.emailAt(index: actualIndex) {
                EmailCardView(
                    email: email,
                    geometry: geometry,
                    isActive: displayIndex == 0 && !isDismissing,
                    onLoadComplete: {
                        if actualIndex == 0 && sessionStartTime == nil {
                            sessionStartTime = Date()
                        }
                    }
                )
            } else {
                EmailCardSkeleton(geometry: geometry)
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
    
    private var actionButtonsSection: some View {
        ScrollableEmailActionBar(
            email: emailLoader.currentEmail,
            isProcessing: isButtonDisabled,
            showReply: true,
            onReply: {
                // Reply functionality - placeholder for now
                logDebug("Reply to email", category: "Email")
            },
            onStar: {
                await handleStar()
            },
            onKeepUnread: {
                await handleKeepUnread()
            },
            onMarkAsRead: {
                await handleMarkAsRead()
            },
            onUnsubscribe: {
                await handleUnsubscribe()
            },
            hasUnsubscribe: hasUnsubscribeAvailable
        )
        .onChange(of: emailLoader.currentEmail?.id) { _, newEmailId in
            // Check unsubscribe availability when email changes
            Task {
                await checkUnsubscribeAvailability()
            }
        }
        .task {
            // Check on initial load
            await checkUnsubscribeAvailability()
        }
    }
    
    private func checkUnsubscribeAvailability() async {
        guard let email = emailLoader.currentEmail else {
            await MainActor.run {
                hasUnsubscribeAvailable = false
            }
            return
        }
        
        let unsubscribeService = UnsubscribeService.shared
        if let _ = await unsubscribeService.getUnsubscribeInfo(for: email, accountEmail: email.account_email) {
            await MainActor.run {
                hasUnsubscribeAvailable = true
            }
        } else {
            await MainActor.run {
                hasUnsubscribeAvailable = false
            }
        }
    }
    
    private var isButtonDisabled: Bool {
        isProcessing || !emailLoader.isCurrentLoaded || isAnimating
    }
    
    // MARK: - Action Handlers
    
    private func handleStar() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Haptic feedback
        impactMedium.impactOccurred()
        
        // Perform dismissal animation (card shoots up)
        await performDismissalAnimation(cardId: email.id, direction: .up)
        
        let newStarState = !email.is_starred
        
        // Update stats
        sessionStats.reviewed += 1
        sessionStats.starred += 1
        
        // Remove from deck AFTER animation completes
        emailLoader.removeCurrentEmail()
        
        // Reset animation state
        resetAnimationState()
        
        // Success haptic
        notificationGenerator.notificationOccurred(.success)
        
        isProcessing = false
        isAnimating = false
        
        // Enqueue star action to Gmail
        Task {
            await EmailActionSynchronizer.shared.enqueueStar(
                emailId: email.id,
                gmailId: email.gmail_id,
                accountEmail: email.account_email,
                shouldStar: newStarState
            )
        }
        
        // Update dashboard cache with starred status change
        Task {
            await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        }
    }
    
    private func handleKeepUnread() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        
        isAnimating = true
        
        // Haptic feedback
        impactLight.impactOccurred()
        
        // Perform dismissal animation (card goes left)
        await performDismissalAnimation(cardId: email.id, direction: .left)
        
        // Update stats
        sessionStats.reviewed += 1
        sessionStats.keptUnread += 1
        
        // Move to next email AFTER animation
        emailLoader.moveToNext()
        
        // Reset animation state
        resetAnimationState()
        
        isAnimating = false
    }
    
    private func handleMarkAsRead() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Haptic feedback
        impactMedium.impactOccurred()
        
        // Perform dismissal animation (card goes right)
        await performDismissalAnimation(cardId: email.id, direction: .right)
        
        // Update stats
        sessionStats.reviewed += 1
        sessionStats.markedAsRead += 1
        
        // Remove from deck AFTER animation
        emailLoader.removeCurrentEmail()
        
        // Reset animation state
        resetAnimationState()
        
        // Success haptic
        notificationGenerator.notificationOccurred(.success)
        
        isAnimating = false
        isProcessing = false
        
        // Enqueue mark as read action to Gmail
        Task {
            await EmailActionSynchronizer.shared.enqueueMarkRead(
                emailId: email.id,
                gmailId: email.gmail_id,
                accountEmail: email.account_email
            )
        }
        
        // Update dashboard data manager
        await DashboardDataManager.shared.markEmailAsRead(emailId: email.id)
    }
    
    private func handleUnsubscribe() async {
        guard let email = emailLoader.currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Haptic feedback
        impactMedium.impactOccurred()
        
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
                logInfo("✅ Successfully unsubscribed\n\(logMessage)", category: "Unsubscribe")
                notificationGenerator.notificationOccurred(.success)
                
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
                    
                    // Remove from deck AFTER animation
                    emailLoader.removeCurrentEmail()
                    
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
                logError("❌ Failed to unsubscribe\n\(logMessage)", category: "Unsubscribe")
                notificationGenerator.notificationOccurred(.error)
                
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
            notificationGenerator.notificationOccurred(.warning)
        }
        
        isAnimating = false
        isProcessing = false
    }
    
    // MARK: - Animation Helpers
    
    /// Performs the full dismissal animation: card flies off while others rise
    private func performDismissalAnimation(cardId: Int, direction: DismissDirection) async {
        // Mark which card is being dismissed
        dismissingCardId = cardId
        
        // Reset rise progress
        riseProgress = 0
        
        // Animate card out AND other cards rising simultaneously
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            // Set dismissal transforms based on direction
            switch direction {
            case .left:
                dismissOffset = CGSize(width: -UIScreen.main.bounds.width * 1.3, height: 0)
                dismissRotation = -15
            case .right:
                dismissOffset = CGSize(width: UIScreen.main.bounds.width * 1.3, height: 0)
                dismissRotation = 15
            case .up:
                dismissOffset = CGSize(width: 0, height: -UIScreen.main.bounds.height)
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
