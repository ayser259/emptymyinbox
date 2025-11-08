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
    @State private var currentEmail: EmailDetail?
    @State private var nextEmail: EmailDetail?
    @State private var currentIndex: Int = 0
    @State private var isLoading = false
    @State private var isProcessing = false
    @State private var emailOffset: CGSize = .zero
    @State private var emailOpacity: Double = 1.0
    @State private var nextEmailOffset: CGSize = CGSize(width: 8, height: 8)
    @State private var nextEmailOpacity: Double = 0.6
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            if isLoading && unreadEmails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if unreadEmails.isEmpty {
                VStack(spacing: AppTheme.spacingMedium) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                        .padding()
                    
                    Text("All caught up!")
                        .font(AppTheme.title2)
                        .primaryText()
                    
                    Text("No unread emails")
                        .font(AppTheme.body)
                        .secondaryText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top bar with unread counter (centered)
                        HStack {
                            Spacer()
                            Text("\(unreadEmails.count - currentIndex) unread")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.spacingMedium)
                        .padding(.vertical, AppTheme.spacingSmall)
                        .background(AppTheme.secondaryBackground.opacity(0.5))
                        
                        // Email content area with card stacking
                        ZStack {
                            // Next email card (peeking underneath) - always visible when there's a next email
                            if let nextEmail = nextEmail {
                                EmailCardView(email: nextEmail, geometry: geometry)
                                    .offset(nextEmailOffset)
                                    .opacity(nextEmailOpacity)
                                    .scaleEffect(0.98)
                                    .zIndex(0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: nextEmailOffset)
                                    .animation(.easeInOut(duration: 0.2), value: nextEmailOpacity)
                            }
                            
                            // Current email card (on top)
                            if let email = currentEmail {
                                EmailCardView(email: email, geometry: geometry)
                                    .offset(emailOffset)
                                    .opacity(emailOpacity)
                                    .zIndex(1)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: emailOffset)
                                    .animation(.easeInOut(duration: 0.3), value: emailOpacity)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        
                        // Bottom action buttons
                        VStack(spacing: 0) {
                            Divider()
                                .background(AppTheme.secondaryText.opacity(0.2))
                            
                            GeometryReader { buttonGeometry in
                                let availableWidth = buttonGeometry.size.width - (AppTheme.spacingLarge * 2)
                                let buttonSpacing: CGFloat = 12
                                
                                HStack(spacing: buttonSpacing) {
                                    // Star button (20% width)
                                    Button {
                                        Task {
                                            await handleStar()
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: currentEmail?.is_starred == true ? "star.fill" : "star")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(AppTheme.accent)
                                            
                                            Text("Star")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppTheme.accent)
                                        }
                                        .frame(width: availableWidth * 0.20)
                                        .frame(height: 64)
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
                                    .disabled(isProcessing || currentEmail == nil || isAnimating)
                                    
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
                                            .frame(height: 64)
                                            .background(AppTheme.secondaryBackground)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(AppTheme.accent, lineWidth: 2)
                                            )
                                    }
                                    .disabled(isProcessing || currentEmail == nil || isAnimating)
                                    
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
                                            .frame(height: 64)
                                            .background(AppTheme.accent)
                                            .cornerRadius(12)
                                    }
                                    .disabled(isProcessing || currentEmail == nil || isAnimating)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, AppTheme.spacingLarge)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                            }
                            .frame(height: 108)
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
            await loadUnreadEmails()
        }
    }
    
    private func loadUnreadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let emails = try await APIService.shared.getUnreadEmails()
            await MainActor.run {
                self.unreadEmails = emails
                if !emails.isEmpty {
                    loadCurrentEmail()
                }
            }
        } catch {
            print("Error loading unread emails: \(error)")
        }
    }
    
    private func loadCurrentEmail(animateFromBottom: Bool = false) {
        guard currentIndex < unreadEmails.count else { return }
        
        let emailItem = unreadEmails[currentIndex]
        Task {
            do {
                let emailDetail = try await APIService.shared.getEmailDetails(emailId: emailItem.id)
                await MainActor.run {
                    if animateFromBottom {
                        // Move current email to next position, then bring new one forward
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            // Current email becomes next (peeking)
                            if let current = self.currentEmail {
                                self.nextEmail = current
                                self.nextEmailOffset = CGSize(width: 8, height: 8)
                                self.nextEmailOpacity = 0.6
                            }
                            
                            // New email starts from below and comes forward
                            self.emailOffset = CGSize(width: 0, height: 200)
                            self.emailOpacity = 0
                            self.currentEmail = emailDetail
                        }
                        
                        // Animate new email sliding up to center
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                self.emailOffset = .zero
                                self.emailOpacity = 1.0
                            }
                        }
                    } else {
                        // Initial load
                        self.currentEmail = emailDetail
                        self.emailOffset = .zero
                        self.emailOpacity = 1.0
                        
                        // Load next email for stacking
                        loadNextEmail()
                    }
                }
            } catch {
                print("Error loading email details: \(error)")
                await MainActor.run {
                    emailOffset = .zero
                    emailOpacity = 1.0
                }
            }
        }
    }
    
    private func loadNextEmail() {
        guard currentIndex + 1 < unreadEmails.count else {
            nextEmail = nil
            return
        }
        
        let nextEmailItem = unreadEmails[currentIndex + 1]
        Task {
            do {
                let emailDetail = try await APIService.shared.getEmailDetails(emailId: nextEmailItem.id)
                await MainActor.run {
                    self.nextEmail = emailDetail
                    self.nextEmailOffset = CGSize(width: 8, height: 8)
                    self.nextEmailOpacity = 0.6
                }
            } catch {
                print("Error loading next email details: \(error)")
            }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: 0, height: -UIScreen.main.bounds.height)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        do {
            let updatedEmail: EmailDetail
            if email.is_starred {
                updatedEmail = try await APIService.shared.unstarEmail(emailId: email.id)
            } else {
                updatedEmail = try await APIService.shared.starEmail(emailId: email.id)
            }
            
            await MainActor.run {
                // Keep the email visible but update it
                self.currentEmail = updatedEmail
                isProcessing = false
                isAnimating = false
            }
        } catch {
            print("Error toggling star: \(error)")
            await MainActor.run {
                // Reset animation state on error
                emailOffset = .zero
                emailOpacity = 1.0
                isProcessing = false
                isAnimating = false
            }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        // Move to next email
        await MainActor.run {
            currentIndex += 1
            isAnimating = false
            
            if currentIndex < unreadEmails.count {
                // Load next email sliding up from below (card stack animation)
                loadCurrentEmail(animateFromBottom: true)
            } else {
                // No more emails
                currentEmail = nil
                nextEmail = nil
            }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                emailOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                emailOpacity = 0
            }
        }
        
        // Wait for animation
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        do {
            _ = try await APIService.shared.markEmailAsRead(emailId: email.id)
            
            // Remove from unread list and move to next
            await MainActor.run {
                self.unreadEmails.remove(at: currentIndex)
                isAnimating = false
                
                // Don't increment index since we removed the current item
                if currentIndex < unreadEmails.count {
                    // Load next email sliding up from below (card stack animation)
                    loadCurrentEmail(animateFromBottom: true)
                } else {
                    // No more unread emails
                    self.currentEmail = nil
                    self.nextEmail = nil
                }
                isProcessing = false
            }
        } catch {
            print("Error marking as read: \(error)")
            await MainActor.run {
                // Reset animation state on error
                emailOffset = .zero
                emailOpacity = 1.0
                isProcessing = false
                isAnimating = false
            }
        }
    }
    
    private func moveToNextEmail() async {
        await MainActor.run {
            currentIndex += 1
            if currentIndex < unreadEmails.count {
                loadCurrentEmail()
            } else {
                // No more emails
                currentEmail = nil
            }
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

