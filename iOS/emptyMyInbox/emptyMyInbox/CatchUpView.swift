//
//  CatchUpView.swift
//  emptyMyInbox
//
//  Slack-style catch up view for processing unread emails
//

import SwiftUI
import WebKit
import UIKit

struct CatchUpView: View {
    let accountId: Int?
    let accountEmail: String?
    @EnvironmentObject var authManager: AuthManager
    @State private var unreadEmails: [EmailListItem] = []
    @State private var emailDeck: [EmailDetail] = [] // Full deck of loaded emails
    @State private var currentIndex: Int = 0
    @State private var isLoading = false
    @State private var isLoadingDeck = false
    @State private var loadedEmailIds: Set<Int> = [] // Track which emails have fully loaded their content
    @State private var isProcessing = false
    @State private var emailOffset: CGSize = .zero
    @State private var emailOpacity: Double = 1.0
    @State private var isAnimating = false
    @State private var reviewedCount: Int = 0 // Track locally reviewed emails
    @State private var lastReviewedEmailId: Int? // Track last reviewed email for visual indicator
    @State private var sessionStartTime: Date? // Track when session started
    @State private var initialEmailCount: Int = 0 // Track initial email count for stats
    private let maxVisibleCards = 2 // Show only the current card and one peeking behind
    
    private var isOffline: Bool {
        // Always assume online since we're using direct Gmail API
        return false
    }
    
    init(accountId: Int? = nil, accountEmail: String? = nil) {
        self.accountId = accountId
        self.accountEmail = accountEmail
    }
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            mainContent
        }
        .navigationTitle(accountEmail.map { "Catch Up (\($0))" } ?? "Catch Up")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton()
        .task {
            // Only resume pending actions if online
            if !isOffline {
                await EmailActionSynchronizer.shared.resumePendingActions()
            }
            // Always use cache-only mode for fast loading
            await loadUnreadEmails(fromCacheOnly: true)
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if isLoading && unreadEmails.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if unreadEmails.isEmpty || currentIndex >= unreadEmails.count {
            CelebrationView(
                emailsCleared: emailsClearedCount,
                sessionStartTime: sessionStartTime,
                accountEmail: accountEmail
            )
        } else {
            emailDeckView
        }
    }
    
    private var emailsClearedCount: Int? {
        if initialEmailCount > 0 {
            return initialEmailCount
        } else if reviewedCount > 0 {
            return reviewedCount
        } else {
            return nil
        }
    }
    
    private var emailDeckView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    topBarSection
                    emailCardsSection(geometry: geometry)
                }
                actionButtonsSection
            }
        }
    }
    
    private var topBarSection: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Text("\(max(0, emailDeck.count - currentIndex)) left to review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                
                if reviewedCount > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.accent)
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
    
    @ViewBuilder
    private func emailCardsSection(geometry: GeometryProxy) -> some View {
        ZStack {
            if isLoadingDeck || emailDeck.isEmpty {
                EmailCardSkeleton(geometry: geometry)
            } else {
                emailCardsStack(geometry: geometry)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 92)
    }
    
    @ViewBuilder
    private func emailCardsStack(geometry: GeometryProxy) -> some View {
        ForEach(Array(emailDeck.enumerated()), id: \.element.id) { index, email in
            let cardIndex = index - currentIndex
            
            if cardIndex >= 0 && cardIndex < maxVisibleCards {
                emailCardView(email: email, cardIndex: cardIndex, geometry: geometry)
            }
        }
    }
    
    private func emailCardView(email: EmailDetail, cardIndex: Int, geometry: GeometryProxy) -> some View {
        EmailCardView(
            email: email,
            geometry: geometry,
            isActive: cardIndex == 0,
            onLoadComplete: {
                loadedEmailIds.insert(email.id)
            }
        )
        .onAppear {
            if cardIndex == 0 && currentIndex == 0 && sessionStartTime == nil {
                sessionStartTime = Date()
            }
        }
        .offset(cardIndex == 0 ? emailOffset : CGSize(width: 0, height: (CGFloat(cardIndex) * 16) - (cardIndex == 1 ? 6 : 0)))
        .opacity(cardIndex == 0 ? emailOpacity : max(0.6, 1.0 - Double(cardIndex) * 0.08))
        .scaleEffect(max(0.96, 1.0 - Double(cardIndex) * 0.01))
        .zIndex(Double(maxVisibleCards - cardIndex))
        .overlay(checkmarkOverlay(cardIndex: cardIndex, email: email))
        .animation(
            cardIndex == 0 ? .spring(response: 0.5, dampingFraction: 0.7) : .spring(response: 0.3, dampingFraction: 0.8),
            value: cardIndex == 0 ? emailOffset : .zero
        )
        .animation(.easeInOut(duration: 0.2), value: emailOpacity)
    }
    
    @ViewBuilder
    private func checkmarkOverlay(cardIndex: Int, email: EmailDetail) -> some View {
        if cardIndex == 0 && lastReviewedEmailId == email.id {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.accent)
                        .padding()
                        .background(AppTheme.secondaryBackground.opacity(0.9))
                        .clipShape(Circle())
                        .padding()
                }
                Spacer()
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.secondaryText.opacity(0.2))
            
            GeometryReader { buttonGeometry in
                let availableWidth = buttonGeometry.size.width - (AppTheme.spacingLarge * 2)
                let buttonSpacing: CGFloat = 12
                let buttonHeight: CGFloat = 51.2
                
                HStack(spacing: buttonSpacing) {
                    starButton(availableWidth: availableWidth, buttonHeight: buttonHeight)
                    keepUnreadButton(availableWidth: availableWidth, buttonHeight: buttonHeight)
                    markAsReadButton(availableWidth: availableWidth, buttonHeight: buttonHeight)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.spacingLarge)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .frame(height: 79)
        }
        .background(AppTheme.primaryBackground)
    }
    
    private func starButton(availableWidth: CGFloat, buttonHeight: CGFloat) -> some View {
        Button {
            Task {
                await handleStar()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: starButtonIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                
                Text("Star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            .frame(width: availableWidth * 0.20)
            .frame(height: buttonHeight)
            .background(Color.black)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(starButtonStrokeColor, lineWidth: starButtonStrokeWidth)
            )
        }
        .disabled(isProcessing || currentIndex >= emailDeck.count || isAnimating || isLoadingDeck)
    }
    
    private var starButtonIcon: String {
        (currentIndex < emailDeck.count && emailDeck[currentIndex].is_starred) ? "star.fill" : "star"
    }
    
    private var starButtonStrokeColor: Color {
        currentEmail?.is_starred == true ? AppTheme.accent : Color.white.opacity(0.2)
    }
    
    private var starButtonStrokeWidth: CGFloat {
        currentEmail?.is_starred == true ? 2 : 1
    }
    
    private func keepUnreadButton(availableWidth: CGFloat, buttonHeight: CGFloat) -> some View {
        Button {
            Task {
                await handleKeepUnread()
            }
        } label: {
            Text("Keep Unread")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .frame(width: availableWidth * 0.40)
                .frame(height: buttonHeight)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent, lineWidth: 2)
                )
        }
        .disabled(isProcessing || currentIndex >= emailDeck.count || isAnimating || isLoadingDeck)
    }
    
    private func markAsReadButton(availableWidth: CGFloat, buttonHeight: CGFloat) -> some View {
        Button {
            Task {
                await handleMarkAsRead()
            }
        } label: {
            Text("Mark as Read")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: availableWidth * 0.40)
                .frame(height: buttonHeight)
                .background(AppTheme.accent)
                .cornerRadius(12)
        }
        .disabled(isProcessing || currentIndex >= emailDeck.count || isAnimating || isLoadingDeck)
    }
    
    private func loadUnreadEmails(fromCacheOnly: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        let cachedEmails = await EmailCache.shared.loadUnreadEmails(accountId: accountId)
        await MainActor.run {
            self.unreadEmails = cachedEmails
            // Track initial count (timer will start when first email is displayed)
            if !cachedEmails.isEmpty {
                self.initialEmailCount = cachedEmails.count
            }
        }
        
        if cachedEmails.isEmpty {
            await MainActor.run {
                self.emailDeck = []
            }
            return
        }
        
        await loadEmailDeck(emails: cachedEmails, useCacheOnly: fromCacheOnly)
    }
    
    private func loadEmailDeck(emails: [EmailListItem], useCacheOnly: Bool) async {
        guard !emails.isEmpty else {
            await MainActor.run {
                self.emailDeck = []
                self.isLoadingDeck = false
                self.loadedEmailIds.removeAll()
            }
            return
        }
        
        // Always show loading state when loading email details
        await MainActor.run {
            isLoadingDeck = true
            loadedEmailIds.removeAll()
        }
        
        // Load all emails from cache only - no Gmail API calls
        var emailDeck: [EmailDetail] = []
        
        for emailItem in emails {
            if let cachedDetail = await EmailCache.shared.loadEmailDetail(emailId: emailItem.id) {
                emailDeck.append(cachedDetail)
            }
            // Skip emails that aren't cached - they'll be available after next refresh
        }
        
        // Update deck with all cached emails
        await MainActor.run {
            self.emailDeck = emailDeck
            self.emailOffset = .zero
            self.emailOpacity = 1.0
            self.loadedEmailIds = Set(emailDeck.map { $0.id })
            isLoadingDeck = false
        }
    }
    
    private var currentEmail: EmailDetail? {
        guard currentIndex < emailDeck.count else { return nil }
        return emailDeck[currentIndex]
    }
    
    private func handleStar() async {
        guard let email = currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Animate email shooting up
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: 0, height: -UIScreen.main.bounds.height)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        let newStarState = !email.is_starred
        let updatedEmail = email.updating(isStarred: newStarState)
        
        // Remove from deck and unread list, but keep as unread
        await MainActor.run {
            // Remove from deck
            if self.currentIndex < self.emailDeck.count {
                self.emailDeck.remove(at: self.currentIndex)
            }
            
            // Remove from unread emails list
            if self.currentIndex < self.unreadEmails.count {
                self.unreadEmails.remove(at: self.currentIndex)
            }
            
            // Track that we reviewed this email
            self.reviewedCount += 1
            self.lastReviewedEmailId = email.id
            
            // Don't increment currentIndex since we removed the item
            // Reset animation state for next card
            if self.currentIndex < self.emailDeck.count {
                self.emailOffset = .zero
                self.emailOpacity = 1.0
            }
            
            self.isProcessing = false
            self.isAnimating = false
        }
        
        // Update cache - keep email but mark as starred
        await EmailCache.shared.saveEmailDetail(updatedEmail)
        // Remove from unread cache since we're removing it from the stack
        await EmailCache.shared.removeUnreadEmail(emailId: email.id, accountId: accountId)
        
        // Enqueue star action only if online
        if !isOffline {
            Task {
                await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email, shouldStar: newStarState)
            }
        }
        
    }
    
    private func handleKeepUnread() async {
        guard !isAnimating else { return }
        
        isAnimating = true
        
        // Animate email going left
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        // Move to next email
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                currentIndex += 1
                // Reset animation state for next card
                if currentIndex < emailDeck.count {
                    emailOffset = .zero
                    emailOpacity = 1.0
                }
            }
            isAnimating = false
        }
    }
    
    private func handleMarkAsRead() async {
        guard let email = currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Animate email going right
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        // Remove from deck and move to next optimistically
        await MainActor.run {
            if self.currentIndex < self.emailDeck.count {
                self.emailDeck.remove(at: self.currentIndex)
            }
            if self.currentIndex < self.unreadEmails.count {
                self.unreadEmails.remove(at: self.currentIndex)
            }
            
            // Track that we reviewed this email
            self.reviewedCount += 1
            self.lastReviewedEmailId = email.id
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if self.currentIndex < self.emailDeck.count {
                    self.emailOffset = .zero
                    self.emailOpacity = 1.0
                }
            }
            isAnimating = false
            isProcessing = false
        }
        
        await EmailCache.shared.removeUnreadEmail(emailId: email.id, accountId: accountId)
        await EmailCache.shared.deleteEmailDetail(emailId: email.id)
        await DashboardDataManager.shared.markEmailAsRead(emailId: email.id)
        
        // Only enqueue sync action if online
        if !isOffline {
            Task {
                await EmailActionSynchronizer.shared.enqueueMarkRead(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email)
            }
        }
        
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            if calendar.isDateInToday(date) {
                dateFormatter.dateStyle = .none
                dateFormatter.timeStyle = .short
            } else {
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
            }
            return dateFormatter.string(from: date)
        }
        return ""
    }
}

#Preview {
    NavigationStack {
        CatchUpView()
            .environmentObject(AuthManager())
    }
}

