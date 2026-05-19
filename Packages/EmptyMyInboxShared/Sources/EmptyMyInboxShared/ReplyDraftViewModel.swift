//
//  ReplyDraftViewModel.swift
//  EmptyMyInboxShared
//

import Foundation
import Observation

@MainActor
@Observable
public final class ReplyDraftViewModel {

    // MARK: - Intent & recipients

    public let intent: ReplyIntent
    public var mode: ReplyMode {
        didSet {
            guard oldValue != mode else { return }
            applyRecipientsForCurrentMode()
        }
    }

    public var toField: String = ""
    public var ccField: String = ""
    public var bccField: String = ""
    public var showCcBcc = false
    public var subject: String = ""
    public var bodyText: String = ""

    // MARK: - Draft lifecycle

    public private(set) var gmailMessage: GmailMessage?
    public private(set) var draftId: String?
    public private(set) var isBootstrapping = true
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    public private(set) var isSending = false
    public private(set) var sendError: String?
    public private(set) var saveHint: String?
    public var isQuotedOriginalExpanded = false

    // MARK: - Quick Reply

    public var isQuickReplyVisible = false
    public var quickReplyAsk: String = ""
    public var quickReplyDraft: String = ""
    public var quickReplyError: String?
    public var isGeneratingQuickReply = false
    public private(set) var isQuickReplyAvailable = true
    public private(set) var quickReplyAvailabilityMessage: String?
    public private(set) var isReplyAllMeaningful = false

    // MARK: - Catch-up

    /// Shown after a successful send when `intent.isCatchUpContext`.
    public var showCatchUpOutcomePrompt = false
    public var onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)?
    /// Set when the composer should close (send/save success outside catch-up flow).
    public var requestDismiss = false

    private var lastSavedEnvelope: ReplyDraftEnvelope?
    private var autosaveTask: Task<Void, Never>?
    private var shouldDeleteDraftIfDismissed = false
    private let autosaveDelayNs: UInt64 = 1_200_000_000

    public var canSend: Bool {
        !isBootstrapping && errorMessage == nil && !isSaving && !isSending
            && draftId != nil && gmailMessage != nil
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !currentEnvelope().to.isEmpty
    }

    public var canSaveDraft: Bool {
        !isBootstrapping && errorMessage == nil && !isSaving && !isSending
            && draftId != nil && gmailMessage != nil
    }

    public var email: EmailDetail { intent.email }

    public init(intent: ReplyIntent, onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)? = nil) {
        self.intent = intent
        self.mode = intent.mode
        self.onCatchUpOutcome = onCatchUpOutcome
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        await refreshQuickReplyAvailability()

        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else {
            errorMessage = "Could not find Gmail account for \(email.account_email)."
            isBootstrapping = false
            return
        }

        do {
            let full = try await GmailAPIService.shared.getMessage(
                for: account,
                messageId: email.gmail_id,
                format: "full"
            )
            gmailMessage = full
            subject = ReplyRecipientResolver.replySubject(fromOriginalSubject: email.subject)
            applyRecipientsForCurrentMode()

            let envelope = currentEnvelope()
            let id = try await GmailAPIService.shared.createReplyDraft(
                account: account,
                original: full,
                envelope: envelope
            )
            draftId = id
            lastSavedEnvelope = envelope
            isBootstrapping = false
            saveHint = "Draft saved in Gmail"
            shouldDeleteDraftIfDismissed = true
            await refreshQuickReplyAvailability()
        } catch {
            errorMessage = error.localizedDescription
            isBootstrapping = false
        }
    }

    public func applyRecipientsForCurrentMode() {
        let set: ReplyRecipientSet
        if let gmailMessage {
            set = ReplyRecipientResolver.resolve(
                original: gmailMessage,
                accountEmail: email.account_email,
                mode: mode
            )
        } else {
            set = ReplyRecipientResolver.resolve(email: email, mode: mode)
        }
        toField = ReplyRecipientResolver.formattedHeaderList(set.to)
        ccField = ReplyRecipientResolver.formattedHeaderList(set.cc)
        bccField = ReplyRecipientResolver.formattedHeaderList(set.bcc)
        showCcBcc = !set.cc.isEmpty || !set.bcc.isEmpty
        if let gmailMessage {
            isReplyAllMeaningful = ReplyRecipientResolver.isReplyAllMeaningful(
                original: gmailMessage,
                accountEmail: email.account_email
            )
        } else {
            isReplyAllMeaningful = ReplyRecipientResolver.isReplyAllMeaningful(email: email)
        }
        if mode == .replyAll, !isReplyAllMeaningful {
            mode = .reply
        }
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subject = ReplyRecipientResolver.replySubject(fromOriginalSubject: email.subject)
        }
    }

    public func currentEnvelope(includeQuotedOriginal: Bool? = nil) -> ReplyDraftEnvelope {
        ReplyDraftEnvelope(
            to: ReplyRecipientResolver.parseAddresses(from: toField),
            cc: ReplyRecipientResolver.parseAddresses(from: ccField),
            bcc: ReplyRecipientResolver.parseAddresses(from: bccField),
            subject: subject,
            body: bodyText,
            includeQuotedOriginal: includeQuotedOriginal ?? isQuotedOriginalExpanded
        )
    }

    // MARK: - Autosave

    public func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: autosaveDelayNs)
            guard !Task.isCancelled else { return }
            await persistDraft(showSuccessHint: true)
        }
    }

    public func onBodyTextChanged() {
        if sendError != nil { sendError = nil }
        scheduleAutosave()
    }

    public func saveDraftManually() async -> Bool {
        guard draftId != nil, gmailMessage != nil else { return false }
        let envelope = currentEnvelope()
        if envelope == lastSavedEnvelope {
            shouldDeleteDraftIfDismissed = false
            if !intent.isCatchUpContext { requestDismiss = true }
            return true
        }
        await persistDraft(showSuccessHint: true, dismissAfterSuccess: true)
        if !intent.isCatchUpContext { requestDismiss = true }
        return true
    }

    public func persistDraft(showSuccessHint: Bool, dismissAfterSuccess: Bool = false) async {
        guard let draftId, let gmailMessage else { return }
        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else { return }

        let envelope = currentEnvelope()
        if envelope == lastSavedEnvelope { return }

        isSaving = true
        saveHint = nil

        do {
            try await GmailAPIService.shared.updateReplyDraft(
                account: account,
                draftId: draftId,
                original: gmailMessage,
                envelope: envelope
            )
            lastSavedEnvelope = envelope
            isSaving = false
            if dismissAfterSuccess {
                shouldDeleteDraftIfDismissed = false
                if !intent.isCatchUpContext { requestDismiss = true }
            } else if showSuccessHint {
                saveHint = "Draft saved"
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if saveHint == "Draft saved" { saveHint = nil }
                }
            }
        } catch {
            isSaving = false
            saveHint = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Send / cancel

    public func sendReply() async -> Bool {
        guard let draftId, let gmailMessage else { return false }
        guard let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else { return false }
        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !currentEnvelope().to.isEmpty else {
            sendError = "Add at least one recipient."
            return false
        }

        isSending = true
        sendError = nil
        saveHint = nil
        shouldDeleteDraftIfDismissed = false

        do {
            let envelope = currentEnvelope()
            if envelope != lastSavedEnvelope {
                try await GmailAPIService.shared.updateReplyDraft(
                    account: account,
                    draftId: draftId,
                    original: gmailMessage,
                    envelope: envelope
                )
                lastSavedEnvelope = envelope
            }
            _ = try await GmailAPIService.shared.sendDraft(account: account, draftId: draftId)
            isSending = false
            shouldDeleteDraftIfDismissed = false
            if intent.isCatchUpContext {
                showCatchUpOutcomePrompt = true
            }
            return true
        } catch {
            isSending = false
            sendError = error.localizedDescription
            shouldDeleteDraftIfDismissed = true
            return false
        }
    }

    public func cancelReply() async {
        autosaveTask?.cancel()
        guard let draftId,
              let account = GmailAPIService.shared.getAccount(byEmail: email.account_email) else {
            shouldDeleteDraftIfDismissed = false
            return
        }
        try? await GmailAPIService.shared.deleteDraft(account: account, draftId: draftId)
        shouldDeleteDraftIfDismissed = false
    }

    public func cleanupOnDismissIfNeeded() {
        autosaveTask?.cancel()
        if isSending { return }
        guard shouldDeleteDraftIfDismissed, let draftId else { return }
        let accountEmail = email.account_email
        Task {
            guard let account = GmailAPIService.shared.getAccount(byEmail: accountEmail) else { return }
            try? await GmailAPIService.shared.deleteDraft(account: account, draftId: draftId)
        }
    }

    public func handleCatchUpOutcome(_ outcome: CatchUpReplyOutcome) {
        onCatchUpOutcome?(outcome)
        showCatchUpOutcomePrompt = false
        requestDismiss = true
    }

    // MARK: - Quick Reply

    public func toggleQuickReplyVisibility() {
        guard errorMessage == nil, !isSending else { return }
        if !isQuickReplyAvailable {
            quickReplyError = quickReplyAvailabilityMessage
            return
        }
        quickReplyError = nil
        isQuickReplyVisible.toggle()
    }

    public func generateQuickReply(action: QuickReplyAction, customAsk: String = "") async {
        guard isQuickReplyAvailable else {
            quickReplyError = quickReplyAvailabilityMessage ?? "Quick Reply is unavailable for this account."
            return
        }

        let ask = action.promptPhrase(customText: customAsk.isEmpty ? quickReplyAsk : customAsk)
        guard !ask.isEmpty else { return }

        if action.isRewriteAction, bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quickReplyError = "Write something in the body first, then use rewrite actions."
            return
        }

        isGeneratingQuickReply = true
        quickReplyError = nil

        do {
            let generated = try await LLMProviderRouter.shared.quickReply(
                subject: email.subject,
                sender: email.sender,
                snippet: email.snippet,
                body: email.body_text,
                userAsk: ask,
                currentDraft: bodyText,
                recipientsTo: toField,
                recipientsCc: ccField
            )
            let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                quickReplyError = "AI returned an empty reply. Try adding more detail."
            } else {
                quickReplyDraft = trimmed
                saveHint = "Quick Reply generated — tap Insert to add it."
            }
            isGeneratingQuickReply = false
        } catch {
            quickReplyError = error.localizedDescription
            isGeneratingQuickReply = false
        }
    }

    public func insertQuickReply() {
        let text = quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            bodyText = text
        } else {
            bodyText += "\n\n" + text
        }
        scheduleAutosave()
        saveHint = "Quick Reply inserted"
    }

    public func refreshQuickReplyAvailability() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()

        let featureEnabled = FeatureFlagsStore.shared.isQuickReplyEnabled
        let accountIncluded = await AccountInclusionStore.shared.isIncludedInQuickReply(accountEmail: email.account_email)
        let hasProviderKey = await LLMProviderRouter.shared.hasUsableAPIKeyForQuickReply()

        let available = featureEnabled && accountIncluded && hasProviderKey
        let reason: String?
        if !featureEnabled {
            reason = "Turn on Quick Reply under Settings → Core Plugins."
        } else if !accountIncluded {
            reason = "Enable this account under Settings → Core Plugins → Quick Reply → Mail accounts."
        } else if !hasProviderKey {
            let provider = await LLMProviderRouter.shared.selectedProvider()
            let providerName = provider == .openAI ? "OpenAI" : "Claude"
            reason = "Add a \(providerName) API key under Settings → Keys."
        } else {
            reason = nil
        }

        isQuickReplyAvailable = available
        quickReplyAvailabilityMessage = reason
        if !available {
            isQuickReplyVisible = false
        }
    }

    public var quotedOriginalPreview: String {
        let from = email.sender_name ?? email.sender
        let date = email.received_at
        let snippet = email.body_text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = snippet.isEmpty ? email.snippet : String(snippet.prefix(800))
        return """
        On \(date), \(from) wrote:

        \(preview)
        """
    }
}
