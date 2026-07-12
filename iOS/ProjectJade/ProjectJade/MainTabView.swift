//
//  MainTabView.swift
//  ProjectJade
//
//  Root tab bar: Mail (dashboard).
//

import SwiftUI
import ProjectJadeShared

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        TabView(selection: $rootState.selectedTab) {
            DashboardView(isMenuPresented: $rootState.showMenu)
                .tabItem {
                    Label("Mail", systemImage: "envelope.fill")
                }
                .tag(AdaptiveRootState.RootTab.mail.rawValue)
        }
        .id(appearanceSettings.paletteRevision)
        .tint(appearanceSettings.resolvedPalette.accent)
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
        .environmentObject(AppearanceSettingsStore.shared)
}
