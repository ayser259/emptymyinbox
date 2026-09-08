//
//  MainTabView.swift
//  ProjectJade
//
//  Compact iPhone / iPad-narrow shell: dashboard with menu sheet (no bottom tab bar).
//

import SwiftUI
import ProjectJadeShared

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        DashboardView(isMenuPresented: $rootState.showMenu)
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
