//
//  DebugCopyButton.swift
//  EmptyMyInboxShared
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct DebugCopyButton: View {
    public let content: String
    @State private var showCopiedToast = false

    public init(content: String) {
        self.content = content
    }

    public var body: some View {
        Button {
            copyToPasteboard(content)
            withAnimation(.spring(response: 0.3)) {
                showCopiedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(response: 0.3)) {
                    showCopiedToast = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                Text(showCopiedToast ? "Copied!" : "Copy Debug")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(showCopiedToast ? Color.green : Color.purple)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
