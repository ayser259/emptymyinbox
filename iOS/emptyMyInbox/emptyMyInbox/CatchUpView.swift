//
//  CatchUpView.swift
//  emptyMyInbox
//
//  Slack-style catch up view for processing unread emails
//

import SwiftUI
import WebKit
import UIKit
import AudioToolbox

struct CatchUpView: View {
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
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    private let maxVisibleCards = 2 // Show only the current card and one peeking behind
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            if isLoading && unreadEmails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if unreadEmails.isEmpty || currentIndex >= unreadEmails.count {
                CelebrationView()
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            // Top bar with unread counter (centered)
                            HStack {
                                Spacer()
                                Text("\(unreadEmails.count - currentIndex) left to review")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                Spacer()
                            }
                            .padding(.horizontal, AppTheme.spacingMedium)
                            .padding(.vertical, AppTheme.spacingSmall)
                            .background(AppTheme.secondaryBackground.opacity(0.5))
                            
                            // Email content area with card stacking
                            ZStack {
                                if isLoadingDeck || emailDeck.isEmpty {
                                    // Show skeleton loader while loading initial deck
                                    EmailCardSkeleton(geometry: geometry)
                                } else {
                                    // Render deck of cards (peeking from behind)
                                    ForEach(Array(emailDeck.enumerated()), id: \.element.id) { index, email in
                                        let cardIndex = index - currentIndex
                                        
                                        // Only show cards that are visible (current and next few)
                                        if cardIndex >= 0 && cardIndex < maxVisibleCards {
                                            EmailCardView(
                                                email: email,
                                                geometry: geometry,
                                                isActive: cardIndex == 0,
                                                onLoadComplete: {
                                                    // Mark this email as loaded (for future use if needed)
                                                    loadedEmailIds.insert(email.id)
                                                }
                                            )
                                                .offset(
                                                    cardIndex == 0 
                                                        ? CGSize(width: emailOffset.width + dragOffset.width, height: emailOffset.height + dragOffset.height)
                                                        : CGSize(width: 0, height: (CGFloat(cardIndex) * 16) - (cardIndex == 1 ? 6 : 0))
                                                )
                                                .opacity(
                                                    cardIndex == 0 
                                                        ? emailOpacity 
                                                        : max(0.6, 1.0 - Double(cardIndex) * 0.08)
                                                )
                                                .scaleEffect(max(0.96, 1.0 - Double(cardIndex) * 0.01))
                                                .zIndex(Double(maxVisibleCards - cardIndex))
                                                .gesture(
                                                    cardIndex == 0 && !isAnimating && !isProcessing
                                                        ? DragGesture(minimumDistance: 10)
                                                            .onChanged { value in
                                                                isDragging = true
                                                                dragOffset = value.translation
                                                            }
                                                            .onEnded { value in
                                                                isDragging = false
                                                                handleSwipeGesture(translation: value.translation, velocity: value.velocity)
                                                            }
                                                        : nil
                                                )
                                                .animation(
                                                    cardIndex == 0 && !isDragging
                                                        ? .spring(response: 0.5, dampingFraction: 0.7) 
                                                        : .spring(response: 0.3, dampingFraction: 0.8),
                                                    value: cardIndex == 0 ? emailOffset : .zero
                                                )
                                                .animation(.easeInOut(duration: 0.2), value: emailOpacity)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: .infinity)
                            .padding(.bottom, 92) // Space for buttons + gap (reduced)
                        }
                        
                        // Bottom action buttons (pinned to bottom)
                        VStack(spacing: 0) {
                            Divider()
                                .background(AppTheme.secondaryText.opacity(0.2))
                            
                            GeometryReader { buttonGeometry in
                                let availableWidth = buttonGeometry.size.width - (AppTheme.spacingLarge * 2)
                                let buttonSpacing: CGFloat = 12
                                let buttonHeight: CGFloat = 51.2 // Reduced by 20% from 64
                                
                                HStack(spacing: buttonSpacing) {
                                    // Star button (20% width)
                                    Button {
                                        Task {
                                            await handleStar()
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: (currentIndex < emailDeck.count && emailDeck[currentIndex].is_starred) ? "star.fill" : "star")
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
                                                .stroke(
                                                    currentEmail?.is_starred == true 
                                                        ? AppTheme.accent 
                                                        : Color.white.opacity(0.2), 
                                                    lineWidth: currentEmail?.is_starred == true ? 2 : 1
                                                )
                                        )
                                    }
                                    .disabled(isProcessing || currentIndex >= emailDeck.count || isAnimating || isLoadingDeck)
                                    
                                    // Keep Unread button (40% width)
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
                                    
                                    // Mark as Read button (40% width)
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
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, AppTheme.spacingLarge)
                                .padding(.top, 12)
                                .padding(.bottom, 16)
                            }
                            .frame(height: 79) // Reduced height for more compact button area
                        }
                        .background(AppTheme.primaryBackground)
                    }
                }
            }
        }
        .navigationTitle("Catch Up")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton()
        .task {
            await EmailActionSynchronizer.shared.resumePendingActions()
            await loadUnreadEmails()
        }
    }
    
    private func loadUnreadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        let cachedEmails = await EmailCache.shared.loadUnreadEmails()
        if !cachedEmails.isEmpty {
            await MainActor.run {
                self.unreadEmails = cachedEmails
            }
            await loadEmailDeck(emails: cachedEmails, useCacheOnly: true)
        }
        
        do {
            let emails = try await APIService.shared.getUnreadEmails()
            await EmailCache.shared.saveUnreadEmails(emails)
            await MainActor.run {
                self.unreadEmails = emails
            }
            
            // Preload all email details to create the deck
            if !emails.isEmpty {
                await loadEmailDeck(emails: emails, useCacheOnly: false)
            } else {
                await MainActor.run {
                    self.emailDeck = []
                }
            }
        } catch {
            print("Error loading unread emails: \(error)")
        }
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
        
        if useCacheOnly {
            await MainActor.run {
                loadedEmailIds.removeAll()
            }
        } else {
            await MainActor.run {
                isLoadingDeck = true
                loadedEmailIds.removeAll()
            }
        }
        
        let priorityCount = min(3, emails.count)
        
        // Phase 1: Load first 3 emails immediately (priority)
        var priorityDeck: [EmailDetail?] = Array(repeating: nil, count: priorityCount)
        var priorityFetchIndexes: [Int] = []
        
        for index in 0..<priorityCount {
            let emailItem = emails[index]
            if let cachedDetail = await EmailCache.shared.loadEmailDetail(emailId: emailItem.id) {
                priorityDeck[index] = cachedDetail
            } else if !useCacheOnly {
                priorityFetchIndexes.append(index)
            }
        }
        
        if !priorityFetchIndexes.isEmpty && !useCacheOnly {
            await withTaskGroup(of: (Int, EmailDetail?).self) { group in
                for index in priorityFetchIndexes {
                    let emailItem = emails[index]
                    group.addTask {
                        do {
                            let detail = try await APIService.shared.getEmailDetails(emailId: emailItem.id)
                            await EmailCache.shared.saveEmailDetail(detail)
                            return (index, detail)
                        } catch {
                            print("Error loading email details for \(emailItem.id): \(error)")
                            return (index, nil)
                        }
                    }
                }
                
                for await (index, emailDetail) in group {
                    if let detail = emailDetail {
                        priorityDeck[index] = detail
                    }
                }
            }
        }
        
        // Build priority deck maintaining order
        let initialDeck = priorityDeck.compactMap { $0 }
        
        // Show first batch immediately
        await MainActor.run {
            self.emailDeck = initialDeck
            self.emailOffset = .zero
            self.emailOpacity = 1.0
            self.loadedEmailIds.removeAll()
            if !useCacheOnly {
                isLoadingDeck = false // Allow UI to show first batch
            }
        }
        
        // Phase 2: Load remaining emails in background
        if emails.count > priorityCount {
            var remainingDict: [Int: EmailDetail] = [:]
            var remainingFetchIndexes: [Int] = []
            
            for index in priorityCount..<emails.count {
                let emailItem = emails[index]
                if let cachedDetail = await EmailCache.shared.loadEmailDetail(emailId: emailItem.id) {
                    remainingDict[index] = cachedDetail
                } else if !useCacheOnly {
                    remainingFetchIndexes.append(index)
                }
            }
            
            if !remainingFetchIndexes.isEmpty && !useCacheOnly {
                await withTaskGroup(of: (Int, EmailDetail?).self) { group in
                    for index in remainingFetchIndexes {
                        let emailItem = emails[index]
                        group.addTask {
                            do {
                                let detail = try await APIService.shared.getEmailDetails(emailId: emailItem.id)
                                await EmailCache.shared.saveEmailDetail(detail)
                                return (index, detail)
                            } catch {
                                print("Error loading email details for \(emailItem.id): \(error)")
                                return (index, nil)
                            }
                        }
                    }
                    
                    for await (index, emailDetail) in group {
                        if let detail = emailDetail {
                            remainingDict[index] = detail
                        }
                    }
                }
            }
            
            // Merge with priority deck maintaining original order
            var fullDeck = initialDeck
            for index in priorityCount..<emails.count {
                if let detail = remainingDict[index] {
                    fullDeck.append(detail)
                }
            }
            
            // Update with full deck
            await MainActor.run {
                self.emailDeck = fullDeck
            }
        }
    }
    
    private var currentEmail: EmailDetail? {
        guard currentIndex < emailDeck.count else { return nil }
        return emailDeck[currentIndex]
    }
    
    private func handleSwipeGesture(translation: CGSize, velocity: CGSize) {
        let swipeThreshold: CGFloat = 100
        let velocityThreshold: CGFloat = 500
        
        // Reset drag offset
        dragOffset = .zero
        
        // Determine swipe direction based on translation and velocity
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        let absVelocityX = abs(velocity.width)
        let absVelocityY = abs(velocity.height)
        
        // Swipe up (star)
        if translation.height < -swipeThreshold || (absVelocityY > velocityThreshold && velocity.height < 0 && absY > absX) {
            Task {
                await handleStar()
            }
            return
        }
        
        // Swipe left (keep unread)
        if translation.width < -swipeThreshold || (absVelocityX > velocityThreshold && velocity.width < 0 && absX > absY) {
            Task {
                await handleKeepUnread()
            }
            return
        }
        
        // Swipe right (mark as read)
        if translation.width > swipeThreshold || (absVelocityX > velocityThreshold && velocity.width > 0 && absX > absY) {
            Task {
                await handleMarkAsRead()
            }
            return
        }
        
        // If no clear swipe, reset position
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            emailOffset = .zero
        }
    }
    
    private func handleStar() async {
        guard let email = currentEmail, !isAnimating else { return }
        
        isProcessing = true
        isAnimating = true
        
        // Hard haptic feedback for star
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Play sound effect
        playSoundEffect(.star)
        
        // Animate email shooting up
        await MainActor.run {
            dragOffset = .zero // Reset drag offset
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: 0, height: -UIScreen.main.bounds.height)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        let newStarState = !email.is_starred
        let updatedEmail = email.updating(isStarred: newStarState)
        
        let updatedListItem: EmailListItem? = await MainActor.run {
            guard self.currentIndex < self.emailDeck.count else {
                dragOffset = .zero
                emailOffset = .zero
                emailOpacity = 1.0
                isProcessing = false
                isAnimating = false
                return nil
            }
            
            self.emailDeck[self.currentIndex] = updatedEmail
            
            guard self.currentIndex < self.unreadEmails.count else {
                dragOffset = .zero
                emailOffset = .zero
                emailOpacity = 1.0
                isProcessing = false
                isAnimating = false
                return nil
            }
            
            let updatedItem = self.unreadEmails[self.currentIndex].updating(isStarred: newStarState)
            self.unreadEmails[self.currentIndex] = updatedItem
            
            dragOffset = .zero
            emailOffset = .zero
            emailOpacity = 1.0
            isProcessing = false
            isAnimating = false
            
            return updatedItem
        }
        
        await EmailCache.shared.saveEmailDetail(updatedEmail)
        if let updatedListItem {
            await EmailCache.shared.upsertUnreadEmail(updatedListItem)
        }
        
        Task {
            await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, shouldStar: newStarState)
        }
    }
    
    private func handleKeepUnread() async {
        guard !isAnimating else { return }
        
        isAnimating = true
        
        // Light haptic feedback for keep unread
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Animate email going left
        await MainActor.run {
            dragOffset = .zero // Reset drag offset
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
                dragOffset = .zero
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
        
        // Hard haptic feedback for mark as read
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Animate email going right
        await MainActor.run {
            dragOffset = .zero // Reset drag offset
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
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if self.currentIndex < self.emailDeck.count {
                    self.dragOffset = .zero
                    self.emailOffset = .zero
                    self.emailOpacity = 1.0
                }
            }
            isAnimating = false
            isProcessing = false
        }
        
        await EmailCache.shared.removeUnreadEmail(emailId: email.id)
        await EmailCache.shared.deleteEmailDetail(emailId: email.id)
        
        Task {
            await EmailActionSynchronizer.shared.enqueueMarkRead(emailId: email.id)
        }
    }
    
    
    private enum SoundEffect {
        case star
        case swipe
        case success
    }
    
    private func playSoundEffect(_ effect: SoundEffect) {
        let systemSoundId: SystemSoundID
        switch effect {
        case .star:
            systemSoundId = 1054 // Star/Bookmark sound
        case .swipe:
            systemSoundId = 1104 // Swipe sound
        case .success:
            systemSoundId = 1057 // Success sound
        }
        AudioServicesPlaySystemSound(systemSoundId)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
        return ""
    }
}

#Preview {
    NavigationStack {
        CatchUpView()
    }
}

