//
//  CustomBackButton.swift
//  emptyMyInbox
//
//  Custom back button component
//

import SwiftUI
import EmptyMyInboxShared

struct CustomBackButton: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(Color(hex: "#252525"))
                .clipShape(Circle())
        }
    }
}

struct CustomBackButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CustomBackButton()
                }
            }
    }
}

extension View {
    func customBackButton() -> some View {
        self.modifier(CustomBackButtonModifier())
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

