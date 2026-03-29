//
//  LogoView.swift
//  emptymyinboxMacApp
//
//  Same asset name as iOS (`Logo` in Assets.xcassets).
//

import AppKit
import SwiftUI

struct LogoView: View {
    let size: CGFloat

    init(size: CGFloat = 40) {
        self.size = size
    }

    var body: some View {
        Group {
            if NSImage(named: "Logo") != nil {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
            } else {
                Image(systemName: "envelope.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(MacAppTheme.accent)
                    .frame(width: size, height: size)
            }
        }
    }
}

#Preview {
    LogoView(size: 80)
        .padding()
        .background(MacAppTheme.primaryBackground)
}
