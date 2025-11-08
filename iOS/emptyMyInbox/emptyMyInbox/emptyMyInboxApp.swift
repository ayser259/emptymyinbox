//
//  emptyMyInboxApp.swift
//  emptyMyInbox
//
//  Created by Ayser Choudhury on 11/7/25.
//

import SwiftUI

@main
struct emptyMyInboxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark) // Force dark mode
                .background(AppTheme.primaryBackground)
        }
    }
}
