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
    @EnvironmentObject private var rootState: AdaptiveRootState

    var body: some View {
        TabView(selection: $rootState.selectedTab) {
            DashboardView(isMenuPresented: $rootState.showMenu)
                .tabItem {
                    Label("Mail", systemImage: "envelope.fill")
                }
                .tag(AdaptiveRootState.RootTab.mail.rawValue)

            CalendarSkeletonView(onMenuTap: { rootState.showMenu = true })
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AdaptiveRootState.RootTab.calendar.rawValue)

            ActionItemsSkeletonView(onMenuTap: { rootState.showMenu = true })
                .tabItem {
                    Label("Action Items", systemImage: "checklist")
                }
                .tag(AdaptiveRootState.RootTab.actionItems.rawValue)
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: $rootState.showMenu) {
            MenuView()
                .environmentObject(authManager)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
        .environmentObject(AdaptiveRootState())
}
