//
//  DashboardView.swift
//  emptyMyInbox
//
//  Main dashboard view after login
//

import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showMenu = false
    @State private var searchText = ""
    @State private var accounts: [EmailAccount] = []
    @State private var emails: [EmailListItem] = []
    @State private var starredEmails: [EmailListItem] = []
    @State private var labels: [Label] = []
    @State private var isLoading = false
    @State private var selectedLabel: Label?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                ScrollView {
                VStack(spacing: 0) {
                    // Top bar with logo, greeting, and menu
                    HStack(alignment: .center) {
                        // Logo
                        LogoView(size: 40)
                        
                        Spacer()
                        
                        // Greeting with user name
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(greeting),")
                                .font(AppTheme.headline)
                                .primaryText()
                            
                            if let user = authManager.currentUser {
                                Text(user.displayName)
                                    .font(AppTheme.subheadline)
                                    .secondaryText()
                            }
                        }
                        
                        Spacer()
                        
                        // Hamburger menu
                        Button {
                            showMenu = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20))
                                .primaryText()
                        }
                        .iconButton()
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingMedium)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.secondaryText)
                        
                        TextField("Jump, search, or chat", text: $searchText)
                            .primaryText()
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.bottom, AppTheme.spacingMedium)
                    
                    // Action buttons carousel
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.spacingMedium) {
                        NavigationLink(value: "catch_up") {
                            ActionButton(
                                title: "Catch up",
                                count: unreadCount,
                                icon: "envelope.badge"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                            
                        NavigationLink(value: "all_emails") {
                            ActionButton(
                                title: "All emails",
                                count: emails.count,
                                icon: "envelope"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(value: "accounts") {
                            ActionButton(
                                title: "Accounts",
                                count: accounts.count,
                                icon: "person.crop.circle"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(value: "starred") {
                            ActionButton(
                                title: "Saved",
                                count: savedCount,
                                icon: "star.fill"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                            
                            ActionButton(
                                title: "Drafts",
                                count: draftsCount,
                                icon: "doc.text"
                            )
                        }
                        .padding(.horizontal, AppTheme.spacingMedium)
                    }
                    .padding(.bottom, AppTheme.spacingMedium)
                    
                    // Labels list (Slack-style)
                    VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                        // Section header
                        HStack {
                            Text("LABELS")
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                                .fontWeight(.semibold)
                                .tracking(0.5)
                            
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.spacingMedium)
                        .padding(.top, AppTheme.spacingMedium)
                        
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if labels.isEmpty {
                            Text("No labels")
                                .font(AppTheme.subheadline)
                                .secondaryText()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                        } else {
                            VStack(spacing: 2) {
                                ForEach(labels, id: \.id) { label in
                                    NavigationLink(value: label) {
                                        SlackStyleLabelRow(label: label)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.bottom, AppTheme.spacingLarge)
                }
                }
                .refreshable {
                    await loadData(shouldSync: true)
                }
            }
            .navigationDestination(for: Label.self) { label in
                LabelEmailsView(label: label)
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "all_emails":
                    AllEmailsView()
                case "accounts":
                    AccountsView()
                        .environmentObject(authManager)
                case "starred":
                    StarredEmailsView()
                case "catch_up":
                    CatchUpView()
                default:
                    EmptyView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showMenu) {
            MenuView()
                .environmentObject(authManager)
        }
        .task {
            await loadData()
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<21:
            return "Good evening"
        default:
            return "Good night"
        }
    }
    
    private var unreadCount: Int {
        emails.filter { !$0.is_read }.count
    }
    
    private var savedCount: Int {
        // Count all starred emails (synced separately to ensure we get all of them)
        starredEmails.count
    }
    
    private var draftsCount: Int {
        // TODO: Implement drafts count when backend supports it
        0
    }
    
    private func loadData(shouldSync: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // If refreshing, sync accounts first
            if shouldSync {
                do {
                    _ = try await APIService.shared.syncAllAccounts()
                    print("Synced all accounts")
                } catch {
                    print("Error syncing accounts: \(error.localizedDescription)")
                    // Continue loading even if sync fails
                }
            }
            
            async let accountsTask = APIService.shared.getAccounts()
            async let emailsTask = APIService.shared.getEmails() // Get recent emails for display
            async let starredEmailsTask = APIService.shared.getStarredEmails() // Get all starred emails for count
            async let labelsTask = APIService.shared.getLabels()
            
            let (fetchedAccounts, fetchedEmails, starredEmails, fetchedLabels) = try await (accountsTask, emailsTask, starredEmailsTask, labelsTask)
            
            await MainActor.run {
                self.accounts = fetchedAccounts
                self.emails = fetchedEmails
                // Store starred emails separately for accurate count
                self.starredEmails = starredEmails
                self.labels = fetchedLabels
                print("Loaded \(fetchedLabels.count) labels, \(fetchedEmails.count) emails")
            }
        } catch {
            print("Error loading data: \(error.localizedDescription)")
            await MainActor.run {
                // Show error state
                if labels.isEmpty {
                    print("Labels array is empty - check API connection and ensure Gmail account is connected")
                }
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: AppTheme.spacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.accent)
            
            Text(title)
                .font(AppTheme.subheadline)
                .primaryText()
            
            Text("\(count)")
                .font(AppTheme.caption)
                .secondaryText()
        }
        .frame(width: 100, height: 100)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LabelRow: View {
    let label: Label
    
    var body: some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundColor(AppTheme.accent)
                .font(.system(size: 16))
            
            Text(label.name)
                .font(AppTheme.body)
                .primaryText()
            
            Spacer()
            
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(AppTheme.subheadline)
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingUnit)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentMuted)
                    .cornerRadius(AppTheme.cornerRadiusSmall)
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SlackStyleLabelRow: View {
    let label: Label
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Hash symbol prefix (Slack-style)
            Text("#")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .frame(width: 16, alignment: .leading)
            
            // Label name
            Text(label.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isPressed ? AppTheme.accent : AppTheme.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            // Unread count badge (Slack-style rounded badge)
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, label.unread_count > 99 ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: 18, minHeight: 18)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
        .background(
            isPressed 
                ? AppTheme.secondaryBackground.opacity(0.6) 
                : Color.clear
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct MenuView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if let user = authManager.currentUser {
                        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                            Text(user.username)
                                .font(AppTheme.headline)
                                .primaryText()
                            
                            if let email = user.email {
                                Text(email)
                                    .font(AppTheme.subheadline)
                                    .secondaryText()
                            }
                        }
                        .padding(.vertical, AppTheme.spacingSmall)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await authManager.logout()
                            dismiss()
                        }
                    } label: {
                        SwiftUI.Label("Logout", systemImage: "arrow.right.square")
                            .foregroundColor(.red)
                    }
                }
            }
            .primaryBackground()
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthManager())
}

