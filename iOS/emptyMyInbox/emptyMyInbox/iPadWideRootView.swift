//
//  iPadWideRootView.swift
//  emptyMyInbox
//
//  Mac-like root chrome for wide iPad: top tab bar, split mail, calendar, action items.
//

import SwiftUI
import EmptyMyInboxShared

struct iPadWideRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState

    var body: some View {
        VStack(spacing: 0) {
            iPadWideTopBar()

            Group {
                switch rootState.rootTab {
                case .mail:
                    iPadMailTabView()
                        .environmentObject(authManager)
                case .calendar:
                    CalendarSkeletonView(onMenuTap: { rootState.showMenu = true })
                case .actionItems:
                    ActionItemsSkeletonView(onMenuTap: { rootState.showMenu = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(AppTheme.accent.opacity(0.35))

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

    var body: some View {
        HStack(spacing: AppTheme.spacingMedium) {
            LogoView(size: 36)

            Picker("Section", selection: $rootState.selectedTab) {
                ForEach(AdaptiveRootState.RootTab.allCases, id: \.rawValue) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Spacer()

            Button {
                rootState.showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .primaryText()
            }
            .iconButton()
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
}
