//
//  EmailReplyComposerCoreView.swift
//  EmptyMyInboxShared
//
//  Shared compose body used by iOS and macOS shells.
//

import SwiftUI
import Combine

struct EmailReplyComposerCoreView: View {
    @Bindable var model: ReplyDraftViewModel
    @ObservedObject private var featureFlags = FeatureFlagsStore.shared
    @FocusState private var isEditorFocused: Bool
    @FocusState private var isQuickReplyAskFocused: Bool

    var body: some View {
        Group {
            if model.isBootstrapping {
                ProgressView("Starting reply…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                composeContent
            }
        }
        .background(SharedAppTheme.primaryBackground)
        .overlay {
            if model.isSending { ReplyComposerSendingOverlay() }
        }
        .task {
            await model.refreshQuickReplyAvailability()
            await model.bootstrap()
        }
        .onDisappear { model.cleanupOnDismissIfNeeded() }
        .onChange(of: featureFlags.isQuickReplyEnabled) { _, _ in
            Task { await model.refreshQuickReplyAvailability() }
        }
        .sheet(isPresented: $model.showCatchUpOutcomePrompt) {
            ReplyCatchUpOutcomeSheet { outcome in
                model.handleCatchUpOutcome(outcome)
            }
            #if os(iOS)
            .presentationDetents([.medium])
            #endif
        }
    }

    private var composeContent: some View {
        VStack(spacing: 0) {
            if let hint = model.saveHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(SharedAppTheme.secondaryBackground.opacity(0.5))
            }

            ReplyComposerHeaderSummary(
                email: model.email,
                accountEmail: model.email.account_email,
                showReplyAllMode: model.isReplyAllMeaningful,
                mode: $model.mode,
                onModeChange: { model.applyRecipientsForCurrentMode() }
            )

            ReplyComposerRecipientFields(
                toField: $model.toField,
                ccField: $model.ccField,
                bccField: $model.bccField,
                subject: $model.subject,
                showCcBcc: $model.showCcBcc,
                isDisabled: model.isSending
            )
            .onChange(of: model.toField) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.ccField) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.bccField) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.subject) { _, _ in model.scheduleAutosave() }

            if model.isQuickReplyVisible {
                ReplyComposerQuickReplyPanel(
                    model: model,
                    focusQuickAsk: $isQuickReplyAskFocused
                )
            }

            ReplyComposerQuotedPreview(
                preview: model.quotedOriginalPreview,
                isExpanded: $model.isQuotedOriginalExpanded
            )
            .onChange(of: model.isQuotedOriginalExpanded) { _, _ in
                model.scheduleAutosave()
            }

            ReplyComposerBodyEditor(
                bodyText: $model.bodyText,
                isDisabled: model.isSending,
                isFocused: $isEditorFocused
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.bodyText) { _, _ in model.onBodyTextChanged() }

            ReplyComposerActionBar(
                model: model,
                onSend: { Task { await handleSend() } },
                onSaveDraft: { Task { await handleSaveDraft() } },
                showQuickReplyShortcut: true
            )
        }
    }

    private func handleSend() async {
        let sent = await model.sendReply()
        if sent && !model.intent.isCatchUpContext {
            // Dismiss handled by parent via binding when not showing outcome prompt
        }
    }

    private func handleSaveDraft() async {
        let saved = await model.saveDraftManually()
        if saved && !model.intent.isCatchUpContext {
            // Parent dismisses
        }
    }
}
