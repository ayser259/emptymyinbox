//
//  ScrollableEmailActionBar.swift
//  emptyMyInbox
//
//  Reusable scrollable action bar for email actions
//  Supports: Reply, Star, Keep Unread, Mark as Read, Unsubscribe
//

import SwiftUI

struct ScrollableEmailActionBar: View {
    let email: EmailDetail?
    let isProcessing: Bool
    let onReply: () async -> Void
    let onStar: () async -> Void
    let onKeepUnread: () async -> Void
    let onMarkAsRead: () async -> Void
    let onUnsubscribe: () async -> Void
    
    // Optional: can hide certain buttons
    let showReply: Bool
    let hasUnsubscribe: Bool  // Changed from showUnsubscribe to hasUnsubscribe to indicate availability
    
    init(
        email: EmailDetail?,
        isProcessing: Bool = false,
        showReply: Bool = true,
        onReply: @escaping () async -> Void,
        onStar: @escaping () async -> Void,
        onKeepUnread: @escaping () async -> Void,
        onMarkAsRead: @escaping () async -> Void,
        onUnsubscribe: @escaping () async -> Void,
        hasUnsubscribe: Bool = false  // Default to false - only show when available
    ) {
        self.email = email
        self.isProcessing = isProcessing
        self.showReply = showReply
        self.hasUnsubscribe = hasUnsubscribe
        self.onReply = onReply
        self.onStar = onStar
        self.onKeepUnread = onKeepUnread
        self.onMarkAsRead = onMarkAsRead
        self.onUnsubscribe = onUnsubscribe
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.secondaryText.opacity(0.2))
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Reply button (peeking from left, scrollable)
                        if showReply {
                            Button {
                                Task {
                                    await onReply()
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrowshape.turn.up.left")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                    
                                    Text("Reply")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                }
                                .frame(width: 80, height: 51.2)
                                .background(Color.black)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .id("reply")
                            .disabled(isProcessing)
                        }
                        
                        // Star button
                        Button {
                            Task {
                                await onStar()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: email?.is_starred == true ? "star.fill" : "star")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(AppTheme.accent)
                                
                                Text("Star")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.accent)
                            }
                            .frame(width: 80, height: 51.2)
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        email?.is_starred == true ? AppTheme.accent : Color.white.opacity(0.2),
                                        lineWidth: email?.is_starred == true ? 2 : 1
                                    )
                            )
                        }
                        .id("star")
                        .disabled(isProcessing)
                        
                        // Keep Unread button
                        Button {
                            Task {
                                await onKeepUnread()
                            }
                        } label: {
                            Text("Keep Unread")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.primaryText)
                                .frame(width: 150, height: 51.2)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppTheme.accent, lineWidth: 2)
                                )
                        }
                        .id("keepUnread")
                        .disabled(isProcessing)
                        
                        // Mark as Read button
                        Button {
                            Task {
                                await onMarkAsRead()
                            }
                        } label: {
                            Text("Mark as Read")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 150, height: 51.2)
                                .background(AppTheme.accent)
                                .cornerRadius(12)
                        }
                        .id("markAsRead")
                        .disabled(isProcessing)
                        
                        // Unsubscribe button (peeking from right, scrollable)
                        if hasUnsubscribe {
                            Button {
                                Task {
                                    await onUnsubscribe()
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image("Unsubscribe")
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundColor(.red)
                                        .frame(width: 20, height: 20)
                                    
                                    Text("Unsubscribe")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .frame(width: 100, height: 51.2)
                                .background(Color.black)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .id("unsubscribe")
                            .disabled(isProcessing)
                        }
                    }
                    .padding(.leading, showReply ? (AppTheme.spacingLarge - 60) : AppTheme.spacingLarge) // Start with Reply partially visible if shown
                    .padding(.trailing, AppTheme.spacingLarge)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    // Scroll to show Star button initially, with Reply peeking from left
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("star", anchor: .leading)
                        }
                    }
                }
            }
        }
        .background(AppTheme.primaryBackground)
    }
}

#Preview {
    ScrollableEmailActionBar(
        email: nil,
        onReply: { print("Reply") },
        onStar: { print("Star") },
        onKeepUnread: { print("Keep Unread") },
        onMarkAsRead: { print("Mark as Read") },
        onUnsubscribe: { print("Unsubscribe") },
        hasUnsubscribe: false
    )
}

