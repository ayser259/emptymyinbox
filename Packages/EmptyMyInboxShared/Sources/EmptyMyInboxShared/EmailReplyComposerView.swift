//
//  EmailReplyComposerView.swift
//  EmptyMyInboxShared
//
//  Gmail reply as a draft: create on open, autosave, cancel (delete draft), send.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct EmailReplyComposerView: View {

    let email: EmailDetail

    @Environment(\.dismiss) private var dismiss

    @State private var gmailMessage: GmailMessage?
    @State private var draftId: String?
    @State private var bodyText: String = ""
    @State private var isBootstrapping = true
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var lastSavedBody: String?
    @State private var saveHint: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isQuickReplyVisible = false
    @State private var quickReplyAsk: String = ""
    @State private var quickReplyDraft: String = ""
    @State private var quickReplyError: String?
    @State private var isGeneratingQuickReply = false
    @State private var quickReplyReadyToSend = false
    @State private var isQuickReplyAvailable = true
    @State private var quickReplyAvailabilityMessage: String?
    @FocusState private var isEditorFocused: Bool
    @FocusState private var isQuickReplyAskFocused: Bool
    #if os(macOS)
    @State private var quickReplyShortcutMonitor: Any?
    #endif
    /// When true, a dismiss (e.g. swipe-down) should delete the server draft so it is not left orphaned.
    @State private var shouldDeleteDraftIfDismissed = false

    private let autosaveDelayNs: UInt64 = 1_200_000_000

    public init(email: EmailDetail) {
        self.email = email
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isBootstrapping {
                    ProgressView("Starting reply…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .font(.body)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(SharedAppTheme.accent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if let hint = saveHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(SharedAppTheme.secondaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SharedAppTheme.secondaryBackground.opacity(0.6))
                        }

                        if isQuickReplyVisible {
                            quickReplyPanel
                        }

                        TextEditor(text: $bodyText)
                            .font(.body)
                            .foregroundStyle(SharedAppTheme.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(SharedAppTheme.secondaryBackground.opacity(0.35))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .focused($isEditorFocused)
                            .disabled(isSending)
                            .onChange(of: bodyText) { _, _ in
                    quickReplyReadyToSend = false
                                if sendError != nil {
                                    sendError = nil
                                }
                                scheduleAutosave()
                            }

                        actionBar
                    }
                }
            }
            .background(SharedAppTheme.primaryBackground)
            .navigationTitle("Reply")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await cancelReply() }
                    }
                    .disabled(isSending)
                }
            }
        }
        .overlay {
            if isSending {
                sendingOverlay
            }
        }
        .task {
            await bootstrap()
        }
        #if os(macOS)
        .onAppear {
            installQuickReplyShortcutMonitor()
        }
        #endif
        .onDisappear {
            autosaveTask?.cancel()
            #if os(macOS)
            removeQuickReplyShortcutMonitor()
            #endif
            // While sending, do not delete — avoids racing dismiss/onDisappear with a successful send.
            if isSending { return }
            if shouldDeleteDraftIfDismissed {
                let id = draftId
                let accountEmail = email.account_email
                Task {
                    guard let draftId = id,
                          let account = GmailAPIService.shared.getAccount(byEmail: accountEmail) else { return }
                    try? await GmailAPIService.shared.deleteDraft(account: account, draftId: draftId)
                }
            }
        }
    }

    private var sendingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(SharedAppTheme.accent)
                Text("Sending…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.primaryText)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SharedAppTheme.secondaryBackground)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
            )
        }
        .allowsHitTesting(true)
    }

    private var actionBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                toggleQuickReplyVisibility()
            } label: {
                HStack(spacing: 6) {
                    Text(isQuickReplyVisible ? "Hide Quick Reply" : "Quick Reply")
                    shortcutBadge("⌥Q")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isBootstrapping || errorMessage != nil || isSending || !isQuickReplyAvailable)
            .keyboardShortcut("q", modifiers: [.option])

            Button {
                Task { await saveDraftManually() }
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Text("Save draft")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isBootstrapping || errorMessage != nil || isSending || draftId == nil || gmailMessage == nil)

            Spacer(minLength: 8)

            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.95))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task { await sendReply() }
            } label: {
                Text("Send")
                    .fontWeight(.semibold)
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(SharedAppTheme.accent)
            .disabled(
                isBootstrapping || errorMessage != nil || isSaving || isSending
                    || draftId == nil || gmailMessage == nil
                    || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SharedAppTheme.primaryBackground)
    }

    private var quickReplyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Reply")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharedAppTheme.primaryText)

            TextField("What do you want to say?", text: $quickReplyAsk, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 5)
                .disabled(isGeneratingQuickReply)
                .focused($isQuickReplyAskFocused)
                .submitLabel(.send)
                .onSubmit {
                    if quickReplyReadyToSend {
                        Task { await sendReply() }
                    } else {
                        Task { await generateQuickReply() }
                    }
                }
                .onChange(of: quickReplyAsk) { _, _ in
                    quickReplyReadyToSend = false
                    if quickReplyError != nil {
                        quickReplyError = nil
                    }
                    if !quickReplyDraft.isEmpty {
                        quickReplyDraft = ""
                    }
                }

            HStack(spacing: 8) {
                Button {
                    Task { await generateQuickReply() }
                } label: {
                    if isGeneratingQuickReply {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        HStack(spacing: 6) {
                            Text("Generate")
                            shortcutBadge("↩")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)
                .disabled(isGeneratingQuickReply || quickReplyAsk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    insertQuickReply()
                } label: {
                    HStack(spacing: 6) {
                        Text("Insert")
                        shortcutBadge("⌘↩")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingQuickReply)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            if let quickReplyError {
                Text(quickReplyError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quickReplyAvailabilityMessage {
                Text(quickReplyAvailabilityMessage)
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Generated reply")
                        .font(SharedAppTheme.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)

                    ScrollView {
                        Text(quickReplyDraft)
                            .font(.callout)
                            .foregroundStyle(SharedAppTheme.primaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 84, maxHeight: 150)
                    .background(SharedAppTheme.secondaryBackground.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SharedAppTheme.secondaryBackground.opacity(0.35))
    }

    private func bootstrap() async {
        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else {
            await MainActor.run {
                errorMessage = "Could not find Gmail account for \(email.account_email)."
                isBootstrapping = false
            }
            return
        }

        do {
            let full = try await GmailAPIService.shared.getMessage(
                for: account,
                messageId: email.gmail_id,
                format: "full"
            )
            let id = try await GmailAPIService.shared.createReplyDraft(
                account: account,
                original: full,
                body: ""
            )
            await MainActor.run {
                gmailMessage = full
                draftId = id
                lastSavedBody = ""
                isBootstrapping = false
                saveHint = "Draft saved in Gmail"
                shouldDeleteDraftIfDismissed = true
            }
            await refreshQuickReplyAvailability()
            // Focus after layout; short delay helps sheet / TextEditor become first responder (iOS + Mac).
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                isEditorFocused = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isBootstrapping = false
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: autosaveDelayNs)
            guard !Task.isCancelled else { return }
            await persistDraft(showSuccessHint: true)
        }
    }

    private func saveDraftManually() async {
        guard draftId != nil, gmailMessage != nil else { return }
        // Nothing to sync — still close and keep the existing Gmail draft.
        if bodyText == lastSavedBody {
            await MainActor.run {
                shouldDeleteDraftIfDismissed = false
                dismiss()
            }
            return
        }
        await persistDraft(showSuccessHint: true, dismissAfterSuccess: true)
    }

    private func persistDraft(showSuccessHint: Bool, dismissAfterSuccess: Bool = false) async {
        guard let draftId, let gmailMessage else { return }
        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else { return }
        if bodyText == lastSavedBody { return }

        await MainActor.run {
            isSaving = true
            saveHint = nil
        }

        do {
            try await GmailAPIService.shared.updateReplyDraft(
                account: account,
                draftId: draftId,
                original: gmailMessage,
                body: bodyText
            )
            await MainActor.run {
                lastSavedBody = bodyText
                isSaving = false
                if dismissAfterSuccess {
                    shouldDeleteDraftIfDismissed = false
                    dismiss()
                } else if showSuccessHint {
                    saveHint = "Draft saved"
                }
            }
            if showSuccessHint && !dismissAfterSuccess {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if saveHint == "Draft saved" {
                        saveHint = nil
                    }
                }
            }
        } catch {
            await MainActor.run {
                isSaving = false
                saveHint = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    private func sendReply() async {
        guard let draftId, let gmailMessage else { return }
        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else { return }
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSending = true
            sendError = nil
            saveHint = nil
            // Draft still exists until send returns 2xx; suppress swipe-dismiss delete while sending.
            shouldDeleteDraftIfDismissed = false
        }

        do {
            if bodyText != lastSavedBody {
                try await GmailAPIService.shared.updateReplyDraft(
                    account: account,
                    draftId: draftId,
                    original: gmailMessage,
                    body: bodyText
                )
                await MainActor.run { lastSavedBody = bodyText }
            }
            _ = try await GmailAPIService.shared.sendDraft(account: account, draftId: draftId)
            await MainActor.run {
                isSending = false
                shouldDeleteDraftIfDismissed = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSending = false
                sendError = error.localizedDescription
                // Send failed — draft may still exist; allow user to dismiss and delete or retry.
                shouldDeleteDraftIfDismissed = true
            }
        }
    }

    private func generateQuickReply() async {
        guard isQuickReplyAvailable else {
            await MainActor.run {
                quickReplyError = quickReplyAvailabilityMessage ?? "Quick Reply is unavailable for this account."
            }
            return
        }
        let ask = quickReplyAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }

        await MainActor.run {
            isGeneratingQuickReply = true
            quickReplyError = nil
        }

        do {
            let generated = try await LLMProviderRouter.shared.quickReply(
                subject: email.subject,
                sender: email.sender,
                snippet: email.snippet,
                body: email.body_text,
                userAsk: ask
            )
            await MainActor.run {
                let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
                logInfo(
                    "Quick Reply generated chars=\(trimmed.count) preview=\(String(trimmed.prefix(180)))",
                    category: "LLM"
                )
                if trimmed.isEmpty {
                    quickReplyError = "AI returned an empty reply. Try adding more detail."
                } else {
                    quickReplyDraft = trimmed
                    saveHint = "Quick Reply generated. Press Insert (⌘↩) to add it."
                }
                isGeneratingQuickReply = false
            }
        } catch {
            await MainActor.run {
                quickReplyError = error.localizedDescription
                isGeneratingQuickReply = false
            }
        }
    }

    private func refreshQuickReplyAvailability() async {
        let featureEnabled = await MainActor.run { FeatureFlagsStore.shared.isQuickReplyEnabled }
        let accountIncluded = await AccountInclusionStore.shared.isIncludedInQuickReply(accountEmail: email.account_email)
        let hasProviderKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()

        let available = featureEnabled && accountIncluded && hasProviderKey
        let reason: String?
        if !featureEnabled {
            reason = "Quick Reply is turned off in Settings."
        } else if !accountIncluded {
            reason = "Quick Reply is disabled for this account in Settings."
        } else if !hasProviderKey {
            reason = "Add a provider API key under Settings → Keys to use Quick Reply."
        } else {
            reason = nil
        }

        await MainActor.run {
            isQuickReplyAvailable = available
            quickReplyAvailabilityMessage = reason
            if !available {
                isQuickReplyVisible = false
            }
        }
    }

    private func insertQuickReply() {
        let text = quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            bodyText = text
        } else {
            bodyText += "\n\n" + text
        }
        quickReplyReadyToSend = true
        saveHint = "Quick Reply inserted. Press Enter in the Quick Reply box to send."
        isQuickReplyAskFocused = true
    }

    private func toggleQuickReplyVisibility() {
        guard !(isBootstrapping || errorMessage != nil || isSending || !isQuickReplyAvailable) else { return }
        isQuickReplyVisible.toggle()
        if isQuickReplyVisible {
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    isQuickReplyAskFocused = true
                }
            }
        }
    }

    #if os(macOS)
    @MainActor
    private func installQuickReplyShortcutMonitor() {
        guard quickReplyShortcutMonitor == nil else { return }
        quickReplyShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .option,
                  event.charactersIgnoringModifiers?.lowercased() == "q" else {
                return event
            }
            toggleQuickReplyVisibility()
            return nil
        }
    }

    @MainActor
    private func removeQuickReplyShortcutMonitor() {
        guard let monitor = quickReplyShortcutMonitor else { return }
        NSEvent.removeMonitor(monitor)
        quickReplyShortcutMonitor = nil
    }
    #endif

    @ViewBuilder
    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(SharedAppTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
    }

    private func cancelReply() async {
        autosaveTask?.cancel()
        guard let draftId,
              let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else {
            await MainActor.run {
                shouldDeleteDraftIfDismissed = false
                dismiss()
            }
            return
        }
        do {
            try await GmailAPIService.shared.deleteDraft(account: account, draftId: draftId)
        } catch {
            // Draft may already be gone; still dismiss.
        }
        await MainActor.run {
            shouldDeleteDraftIfDismissed = false
            dismiss()
        }
    }
}
