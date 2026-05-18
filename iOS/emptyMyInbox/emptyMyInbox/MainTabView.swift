//
//  MainTabView.swift
//  emptyMyInbox
//
//  Root tab bar: Mail (existing dashboard), Calendar, Action Items.
//

import SwiftUI
import EmptyMyInboxShared

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showMenu = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(isMenuPresented: $showMenu)
                .tabItem {
                    Label("Mail", systemImage: "envelope.fill")
                }
                .tag(0)

            CalendarSkeletonView(onMenuTap: { showMenu = true })
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)

            ActionItemsSkeletonView(onMenuTap: { showMenu = true })
                .tabItem {
                    Label("Action Items", systemImage: "checklist")
                }
                .tag(2)
        }
        .tint(AppTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .switchToActionItemsTab)) { _ in
            withAnimation { selectedTab = 2 }
        }
        .sheet(isPresented: $showMenu) {
            MenuView()
                .environmentObject(authManager)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
}
