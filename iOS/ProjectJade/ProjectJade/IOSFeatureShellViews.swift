//
//  IOSFeatureShellViews.swift
//  ProjectJade
//
//  Shared top chrome for the compact dashboard shell.
//

import SwiftUI
import UIKit
import ProjectJadeShared

struct MainAppTopBar<Center: View>: View {
    @ViewBuilder var center: () -> Center
    var onMenuTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            BrandedLogoView(size: 40)

            Spacer()

            center()

            Spacer()

            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .primaryText()
            }
            .iconButton()
            .accessibilityLabel("Menu")
            .accessibilityIdentifier("main_menu_button")
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingMedium)
    }
}
