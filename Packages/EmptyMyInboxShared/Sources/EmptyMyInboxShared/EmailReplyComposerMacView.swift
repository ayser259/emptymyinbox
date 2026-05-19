//
//  EmailReplyComposerMacView.swift
//  EmptyMyInboxShared
//

#if os(macOS)
import AppKit
import SwiftUI

struct EmailReplyComposerMacView: View {
    @Bindable var model: ReplyDraftViewModel
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var environmentDismiss
    @StateObject private var keyboardMonitor = MacReplyComposerKeyboardMonitor()

    var body: some View {
        VStack(spacing: 0) {
            macToolbar
            Divider().opacity(0.35)
            EmailReplyComposerCoreView(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharedAppTheme.primaryBackground)
        .onAppear {
            Task { await model.refreshQuickReplyAvailability() }
            syncKeyboardMonitor()
            keyboardMonitor.installIfNeeded()
        }
        .onDisappear { keyboardMonitor.remove() }
        .onChange(of: model.isQuickReplyAvailable) { _, _ in syncKeyboardMonitor() }
        .onChange(of: model.isBootstrapping) { _, _ in syncKeyboardMonitor() }
        .onChange(of: model.isSending) { _, _ in syncKeyboardMonitor() }
        .onChange(of: model.canSend) { _, _ in syncKeyboardMonitor() }
        .onChange(of: model.canSaveDraft) { _, _ in syncKeyboardMonitor() }
        .onChange(of: model.requestDismiss) { _, shouldDismiss in
            if shouldDismiss { closeComposer() }
        }
    }

    private func closeComposer() {
        if let onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }

    private var macToolbar: some View {
        HStack(spacing: 12) {
            Text(model.mode.title)
                .font(.headline)
                .foregroundStyle(SharedAppTheme.primaryText)
            Spacer()
            Button {
                Task {
                    await model.cancelReply()
                    closeComposer()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Close")
                        .font(.subheadline.weight(.semibold))
                    Text("Esc")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SharedAppTheme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(SharedAppTheme.secondaryBackground.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(SharedAppTheme.secondaryText.opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .disabled(model.isSending)
            .help("Close reply composer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SharedAppTheme.secondaryBackground.opacity(0.6))
    }

    private func syncKeyboardMonitor() {
        keyboardMonitor.canSend = model.canSend
        keyboardMonitor.canSaveDraft = model.canSaveDraft
        keyboardMonitor.onToggleQuickReply = { model.toggleQuickReplyVisibility() }
        keyboardMonitor.onSend = {
            Task { _ = await model.sendReply() }
        }
        keyboardMonitor.onSaveDraft = {
            Task { _ = await model.saveDraftManually() }
        }
    }
}
#endif
