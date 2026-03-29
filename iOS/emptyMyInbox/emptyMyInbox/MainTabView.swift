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

    var body: some View {
        TabView {
            DashboardView(isMenuPresented: $showMenu)
                .tabItem {
                    Label("Mail", systemImage: "envelope.fill")
                }

            CalendarSkeletonView(onMenuTap: { showMenu = true })
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            ActionItemsSkeletonView(onMenuTap: { showMenu = true })
                .tabItem {
                    Label("Action Items", systemImage: "checklist")
                }
        }
        .tint(AppTheme.accent)
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
