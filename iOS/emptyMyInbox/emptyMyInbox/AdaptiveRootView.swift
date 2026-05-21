//
//  AdaptiveRootView.swift
//  emptyMyInbox
//
//  Chooses compact iPhone-style shell vs wide iPad split shell from size class and width.
//

import SwiftUI
import EmptyMyInboxShared

struct AdaptiveRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var rootState = AdaptiveRootState()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let useWideLayout = AdaptiveLayoutMetrics.shouldUseWideLayout(
                horizontalSizeClass: horizontalSizeClass,
                width: geometry.size.width
            )

            Group {
                if useWideLayout {
                    iPadWideRootView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(rootState)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToActionItemsTab)) { _ in
            withAnimation {
                rootState.selectedTab = AdaptiveRootState.RootTab.actionItems.rawValue
            }
        }
    }
}
