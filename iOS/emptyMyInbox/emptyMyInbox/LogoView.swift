//
//  LogoView.swift
//  emptyMyInbox
//
//  Logo view component
//

import SwiftUI
import UIKit
import EmptyMyInboxShared

struct LogoView: View {
    let size: CGFloat
    
    init(size: CGFloat = 40) {
        self.size = size
    }
    
    var body: some View {
        Group {
            // Try to load logo from assets
            if let uiImage = UIImage(named: "Logo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .cornerRadius(AppTheme.cornerRadiusSmall)
            } else {
                // Fallback to system icon
                Image(systemName: "envelope.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: size, height: size)
            }
        }
    }
}

#Preview {
    HStack {
        LogoView(size: 40)
        LogoView(size: 80)
    }
    .padding()
    .primaryBackground()
}

