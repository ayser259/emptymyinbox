//
//  IOSFeatureShellViews.swift
//  emptyMyInbox
//
//  Shared top chrome and skeleton screens for Calendar / Action Items tabs.
//

import SwiftUI

struct MainAppTopBar<Center: View>: View {
    @ViewBuilder var center: () -> Center
    var onMenuTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            LogoView(size: 40)

            Spacer()

            center()

            Spacer()

            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .primaryText()
            }
            .iconButton()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingMedium)
    }
}

struct CalendarSkeletonView: View {
    var onMenuTap: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MainAppTopBar(center: {
                        Text("Calendar")
                            .font(AppTheme.headline)
                            .primaryText()
                    }, onMenuTap: onMenuTap)

                    Spacer()

                    VStack(spacing: AppTheme.spacingMedium) {
                        Image(systemName: "calendar")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.accent.opacity(0.85))
                        Text("Calendar is coming soon")
                            .font(AppTheme.title3)
                            .primaryText()
                        Text("You’ll see events and email-linked dates here.")
                            .font(AppTheme.body)
                            .secondaryText()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.spacingLarge)
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct ActionItemsSkeletonView: View {
    var onMenuTap: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MainAppTopBar(center: {
                        Text("Action Items")
                            .font(AppTheme.headline)
                            .primaryText()
                    }, onMenuTap: onMenuTap)

                    Spacer()

                    VStack(spacing: AppTheme.spacingMedium) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.accent.opacity(0.85))
                        Text("Action items are coming soon")
                            .font(AppTheme.title3)
                            .primaryText()
                        Text("Track todos and follow-ups from your mail.")
                            .font(AppTheme.body)
                            .secondaryText()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.spacingLarge)
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}
