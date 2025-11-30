//
//  DebugSettings.swift
//  emptyMyInbox
//
//  Manages debug mode settings across the app
//

import Foundation
import SwiftUI

/// Singleton manager for debug settings
/// Persists state using UserDefaults and provides observable properties
class DebugSettings: ObservableObject {
    static let shared = DebugSettings()
    
    private let debugModeKey = "debugModeEnabled"
    
    /// Whether debug mode is enabled
    @Published var isDebugModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDebugModeEnabled, forKey: debugModeKey)
        }
    }
    
    private init() {
        self.isDebugModeEnabled = UserDefaults.standard.bool(forKey: debugModeKey)
    }
    
    /// Toggle debug mode on/off
    func toggle() {
        isDebugModeEnabled.toggle()
    }
}

// MARK: - Debug Copy Button Component

/// A floating copy button that appears when debug mode is enabled
struct DebugCopyButton: View {
    let content: String
    @State private var showCopiedToast = false
    
    var body: some View {
        Button {
            UIPasteboard.general.string = content
            withAnimation(.spring(response: 0.3)) {
                showCopiedToast = true
            }
            
            // Hide toast after 1.5 seconds
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
}

// MARK: - Email Content Formatter for Debug

extension EmailDetail {
    /// Formats the email content for debug copying
    var debugCopyContent: String {
        var content = """
        === DEBUG EMAIL CONTENT ===
        
        ID: \(id)
        Gmail ID: \(gmail_id)
        Thread ID: \(thread_id)
        Account: \(account_email)
        
        --- HEADERS ---
        From: \(sender_name ?? "N/A") <\(sender)>
        To: \(recipients_to ?? "N/A")
        CC: \(recipients_cc ?? "N/A")
        Subject: \(subject)
        Date: \(received_at)
        Is Read: \(is_read)
        Is Starred: \(is_starred)
        Labels: \(labels.joined(separator: ", "))
        
        --- SNIPPET ---
        \(snippet)
        
        --- BODY TEXT ---
        \(body_text.isEmpty ? "(empty)" : body_text)
        
        --- BODY HTML ---
        \(body_html ?? "(empty)")
        
        === END DEBUG CONTENT ===
        """
        return content
    }
}



