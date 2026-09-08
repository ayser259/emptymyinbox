//
//  iPadWideRootView.swift
//  ProjectJade
//
//  Mac-like root chrome for wide iPad: logo/menu bar and split mail.
//

import SwiftUI
import ProjectJadeShared

struct iPadWideRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState

    var body: some View {
        VStack(spacing: 0) {
            iPadWideTopBar()

            iPadMailTabView()
                .environmentObject(authManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
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
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
}
