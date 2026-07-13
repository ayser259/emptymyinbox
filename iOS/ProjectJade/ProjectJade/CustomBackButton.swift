//
//  CustomBackButton.swift
//  ProjectJade
//
//  Custom back button component
//

import SwiftUI
import ProjectJadeShared

struct CustomBackButton: View {
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Button {
            if let onBack {
                onBack()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(SharedAppTheme.cardBackground)
                .clipShape(Circle())
        }
        .accessibilityIdentifier("navigation_back_button")
    }
}

struct CustomBackButtonModifier: ViewModifier {
    var onBack: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CustomBackButton(onBack: onBack)
                }
            }
    }
}

extension View {
    func customBackButton(onBack: (() -> Void)? = nil) -> some View {
        self.modifier(CustomBackButtonModifier(onBack: onBack))
    }
}

// Global navigation bar appearance setup
struct NavigationBarAppearanceModifier: ViewModifier {
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.shadowColor = .clear
        
        // Customize back button
        appearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        appearance.backButtonAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: -1000, vertical: 0)
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func setupNavigationBarAppearance() -> some View {
        self.modifier(NavigationBarAppearanceModifier())
    }
}

