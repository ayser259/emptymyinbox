//
//  iPadWideRootView.swift
//  ProjectJade
//
//  Mac-like root chrome for wide iPad: top tab bar and split mail.
//

import SwiftUI
import ProjectJadeShared

struct iPadWideRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        VStack(spacing: 0) {
            iPadWideTopBar()

            iPadMailTabView()
                .environmentObject(authManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(appearanceSettings.resolvedPalette.accent.opacity(0.35))

            VaultRefreshStatusLabel(font: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.spacingMedium)
                .padding(.vertical, 6)
                .background(AppTheme.secondaryBackground.opacity(0.45))
        }
        .background(AppTheme.primaryBackground)
        .sheet(isPresented: $rootState.showMenu) {
            MenuView()
                .environmentObject(authManager)
        }
    }
}

// MARK: - Top bar

private struct iPadWideTopBar: View {
    @EnvironmentObject private var rootState: AdaptiveRootState
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        ZStack {
            HStack(spacing: AppTheme.spacingMedium) {
                BrandedLogoView(size: 36)
                Spacer(minLength: 0)
                Button {
                    rootState.showMenu = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                        .primaryText()
                }
                .iconButton()
                .accessibilityLabel("Menu")
                .accessibilityIdentifier("main_menu_button")
            }

            Label(AdaptiveRootState.RootTab.mail.title, systemImage: AdaptiveRootState.RootTab.mail.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appearanceSettings.resolvedPalette.accent)
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
}
