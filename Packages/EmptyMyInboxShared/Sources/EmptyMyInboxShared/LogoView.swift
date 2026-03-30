//
//  LogoView.swift
//  EmptyMyInboxShared
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct LogoView: View {
    public let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        Group {
            #if os(iOS)
            if let uiImage = UIImage(named: "Logo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .cornerRadius(SharedAppTheme.cornerRadiusSmall)
            } else {
                fallbackIcon
            }
            #elseif os(macOS)
            if let img = NSImage(named: "Logo") {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .cornerRadius(SharedAppTheme.cornerRadiusSmall)
            } else {
                fallbackIcon
            }
            #else
            fallbackIcon
            #endif
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "envelope.fill")
            .font(.system(size: size * 0.6))
            .foregroundColor(SharedAppTheme.accent)
            .frame(width: size, height: size)
    }
}
