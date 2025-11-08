//
//  ContentView.swift
//  emptyMyInbox
//
//  Created by Ayser Choudhury on 11/7/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            Image(systemName: "envelope.fill")
                .imageScale(.large)
                .foregroundColor(AppTheme.accent)
                .padding(AppTheme.spacingMedium)
            
            Text("Empty My Inbox")
                .font(AppTheme.largeTitle)
                .primaryText()
            
            Text("Manage your inbox and reach inbox zero")
                .font(AppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
            
            Button("Get Started") {
                // Action
            }
            .primaryButton()
        }
        .padding(AppTheme.spacingXLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
    }
}

#Preview {
    ContentView()
}
