//
//  ReplyComposerComponents.swift
//  EmptyMyInboxShared
//

import SwiftUI

// MARK: - Header summary

public struct ReplyComposerHeaderSummary: View {
    let email: EmailDetail
    let accountEmail: String
    let showReplyAllMode: Bool
    @Binding var mode: ReplyMode
    var onModeChange: () -> Void

    public init(
        email: EmailDetail,
        accountEmail: String,
        showReplyAllMode: Bool = true,
        mode: Binding<ReplyMode>,
        onModeChange: @escaping () -> Void = {}
    ) {
        self.email = email
        self.accountEmail = accountEmail
        self.showReplyAllMode = showReplyAllMode
        self._mode = mode
        self.onModeChange = onModeChange
    }

    private var pickerModes: [ReplyMode] {
        showReplyAllMode ? ReplyMode.allCases : [.reply]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(email.sender_name ?? email.sender)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(accountEmail)
                    .font(.caption2)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .lineLimit(1)
            }

            Text(email.subject.isEmpty ? "(No subject)" : email.subject)
                .font(.caption)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .lineLimit(2)

            if pickerModes.count > 1 {
                Picker("Mode", selection: $mode) {
                    ForEach(pickerModes) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in onModeChange() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SharedAppTheme.secondaryBackground.opacity(0.55))
    }
}

// MARK: - Recipient fields

public struct ReplyComposerRecipientFields: View {
    @Binding var toField: String
    @Binding var ccField: String
    @Binding var bccField: String
    @Binding var subject: String
    @Binding var showCcBcc: Bool
    var isDisabled: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            recipientRow(label: "To", text: $toField)
            if showCcBcc {
                recipientRow(label: "Cc", text: $ccField)
                recipientRow(label: "Bcc", text: $bccField)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showCcBcc = true }
                } label: {
                    Text("Cc/Bcc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SharedAppTheme.accent)
                }
                .buttonStyle(.plain)
            }
            recipientRow(label: "Subject", text: $subject)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(isDisabled)
    }

    private func recipientRow(label: String, text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SharedAppTheme.secondaryText)
                .frame(width: 52, alignment: .leading)
            TextField(label, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(SharedAppTheme.primaryText)
                .lineLimit(label == "Subject" ? 2 ... 3 : 1 ... 4)
        }
    }
}

// MARK: - Quoted preview (read-only reference)

public struct ReplyComposerQuotedPreview: View {
    let preview: String
    @Binding var isExpanded: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.85))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                    Text(isExpanded ? "Hide original message" : "Show original message")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SharedAppTheme.secondaryText)
                    Spacer()
                    Text("Read-only")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(SharedAppTheme.secondaryText.opacity(0.35))
                        .frame(width: 3)
                        .padding(.vertical, 8)

                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.9))
                        .italic()
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.trailing, 12)
                }
                .background(Color.white.opacity(0.03))
            }
        }
        .background(SharedAppTheme.secondaryBackground.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Message body editor (primary typing area)

public struct ReplyComposerBodyEditor: View {
    @Binding var bodyText: String
    var isDisabled: Bool
    var isFocused: FocusState<Bool>.Binding

    private var isEmpty: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused.wrappedValue ? SharedAppTheme.accent : SharedAppTheme.secondaryText)
                Text("Your reply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused.wrappedValue ? SharedAppTheme.primaryText : SharedAppTheme.secondaryText)
                Spacer()
                if isFocused.wrappedValue {
                    Text("Typing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SharedAppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SharedAppTheme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)

            ZStack(alignment: .topLeading) {
                if isEmpty && !isFocused.wrappedValue {
                    Text("Write your message here…")
                        .font(.body)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.55))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .focused(isFocused)
                    .disabled(isDisabled)
            }
            .frame(minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFocused.wrappedValue ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused.wrappedValue ? SharedAppTheme.accent.opacity(0.85) : Color.white.opacity(0.14),
                        lineWidth: isFocused.wrappedValue ? 2 : 1
                    )
            )
            .shadow(
                color: isFocused.wrappedValue ? SharedAppTheme.accent.opacity(0.12) : .clear,
                radius: 8,
                y: 2
            )
            .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(SharedAppTheme.primaryBackground)
    }
}

// MARK: - Quick Reply panel

public struct ReplyComposerQuickReplyPanel: View {
    @Bindable var model: ReplyDraftViewModel
    var focusQuickAsk: FocusState<Bool>.Binding

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Reply")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharedAppTheme.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickReplyAction.allCases.filter { $0 != .custom }) { action in
                        Button {
                            Task { await model.generateQuickReply(action: action) }
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SharedAppTheme.secondaryBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isGeneratingQuickReply)
                    }
                }
            }

            TextField("What do you want to say?", text: $model.quickReplyAsk, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)
                .disabled(model.isGeneratingQuickReply)
                .focused(focusQuickAsk)
                .onSubmit {
                    Task { await model.generateQuickReply(action: .custom) }
                }

            HStack(spacing: 8) {
                Button {
                    Task { await model.generateQuickReply(action: .custom) }
                } label: {
                    if model.isGeneratingQuickReply {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)
                .disabled(model.isGeneratingQuickReply || model.quickReplyAsk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Insert") { model.insertQuickReply() }
                    .buttonStyle(.bordered)
                    .disabled(model.quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGeneratingQuickReply)
            }

            if let err = model.quickReplyError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let msg = model.quickReplyAvailabilityMessage, !model.isQuickReplyAvailable {
                Text(msg).font(.caption).foregroundStyle(SharedAppTheme.secondaryText)
            }

            if !model.quickReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(model.quickReplyDraft)
                        .font(.callout)
                        .foregroundStyle(SharedAppTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 72, maxHeight: 120)
                .background(SharedAppTheme.secondaryBackground.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SharedAppTheme.secondaryBackground.opacity(0.35))
    }
}

// MARK: - Action bar

#if os(macOS)
/// Action button with an inline keycap badge (matches Catch Up control styling).
private struct ReplyComposerMacActionButton: View {
    let title: String
    let shortcutDisplay: String
    var systemImage: String? = nil
    var shortcutKey: KeyEquivalent
    var shortcutModifiers: EventModifiers = []
    var style: ReplyComposerMacActionButtonStyle = .secondary
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !isLoading {
                    Spacer(minLength: 4)
                    shortcutBadge
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: minButtonWidth)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcutKey, modifiers: shortcutModifiers)
        .disabled(isDisabled || isLoading)
        .onHover { isHovered = $0 }
        .opacity(isDisabled ? 0.45 : 1)
        .help(helpText)
    }

    private var shortcutBadge: some View {
        Text(shortcutDisplay)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(badgeBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(badgeForeground.opacity(0.28), lineWidth: 0.5)
            )
    }

    private var minButtonWidth: CGFloat {
        switch style {
        case .prominent: return 108
        case .secondary:
            // Room for label + keycap (e.g. "Quick Reply" + ⌥Q).
            return title.count > 10 ? 168 : 132
        }
    }

    private var helpText: String {
        switch shortcutDisplay {
        case "⌥Q": return "Toggle AI Quick Reply"
        case "⌘S": return "Save draft in Gmail and close"
        case "⌘↩": return "Send reply"
        default: return title
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .prominent: return .black
        case .secondary: return SharedAppTheme.primaryText
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .prominent:
            return isHovered ? SharedAppTheme.accent.opacity(0.88) : SharedAppTheme.accent
        case .secondary:
            return isHovered
                ? SharedAppTheme.secondaryBackground.opacity(0.9)
                : SharedAppTheme.secondaryBackground.opacity(0.55)
        }
    }

    private var borderColor: Color {
        switch style {
        case .prominent: return .clear
        case .secondary: return SharedAppTheme.secondaryText.opacity(isHovered ? 0.22 : 0.12)
        }
    }

    private var badgeForeground: Color {
        style == .prominent ? Color.black.opacity(0.65) : SharedAppTheme.secondaryText
    }

    private var badgeBackground: Color {
        style == .prominent ? Color.black.opacity(0.08) : SharedAppTheme.primaryBackground.opacity(0.35)
    }
}

private enum ReplyComposerMacActionButtonStyle {
    case secondary
    case prominent
}
#endif

public struct ReplyComposerActionBar: View {
    @Bindable var model: ReplyDraftViewModel
    var onSend: () -> Void
    var onSaveDraft: () -> Void
    var showQuickReplyShortcut: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
            #if os(macOS)
            ReplyComposerMacActionButton(
                title: model.isQuickReplyVisible ? "Hide AI" : "Quick Reply",
                shortcutDisplay: "⌥Q",
                systemImage: "sparkles",
                shortcutKey: KeyEquivalent("q"),
                shortcutModifiers: .option,
                isDisabled: model.errorMessage != nil || model.isSending
            ) {
                model.toggleQuickReplyVisibility()
            }
            .fixedSize(horizontal: true, vertical: false)

            ReplyComposerMacActionButton(
                title: "Save draft",
                shortcutDisplay: "⌘S",
                shortcutKey: KeyEquivalent("s"),
                shortcutModifiers: .command,
                isDisabled: !model.canSaveDraft,
                isLoading: model.isSaving,
                action: onSaveDraft
            )
            .fixedSize(horizontal: true, vertical: false)
            #else
            Button {
                model.toggleQuickReplyVisibility()
            } label: {
                Label(
                    model.isQuickReplyVisible ? "Hide AI" : "Quick Reply",
                    systemImage: "sparkles"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(model.errorMessage != nil || model.isSending)

            Button(action: onSaveDraft) {
                if model.isSaving {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Text("Save draft")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!model.canSaveDraft)
            #endif

            Spacer(minLength: 8)

            if let sendError = model.sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: 220, alignment: .trailing)
            }

            #if os(macOS)
            ReplyComposerMacActionButton(
                title: "Send",
                shortcutDisplay: "⌘↩",
                shortcutKey: .return,
                shortcutModifiers: .command,
                style: .prominent,
                isDisabled: !model.canSend,
                action: onSend
            )
            .fixedSize(horizontal: true, vertical: false)
            #else
            Button(action: onSend) {
                Text("Send")
                    .fontWeight(.semibold)
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(SharedAppTheme.accent)
            .disabled(!model.canSend)
            .keyboardShortcut(.return, modifiers: [.command])
            #endif
            }

            if let msg = model.quickReplyAvailabilityMessage, !model.isQuickReplyAvailable {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let err = model.quickReplyError, !model.isQuickReplyAvailable {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SharedAppTheme.primaryBackground)
    }
}

// MARK: - Catch-up outcome sheet

public struct ReplyCatchUpOutcomeSheet: View {
    let onSelect: (CatchUpReplyOutcome) -> Void

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 36))
                .foregroundStyle(SharedAppTheme.accent)
            Text("Reply sent")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SharedAppTheme.primaryText)
            Text("What should happen to this email in Catch Up?")
                .font(.subheadline)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                outcomeButton("Mark read & next", icon: "envelope.open.fill", outcome: .markReadAndAdvance)
                outcomeButton("Keep unread & next", icon: "envelope.badge", outcome: .keepUnreadAndAdvance)
                outcomeButton("Stay on this email", icon: "arrow.uturn.backward", outcome: .stay)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
    }

    private func outcomeButton(_ title: String, icon: String, outcome: CatchUpReplyOutcome) -> some View {
        Button {
            onSelect(outcome)
        } label: {
            Label(title, systemImage: icon)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(outcome == .markReadAndAdvance ? SharedAppTheme.accent : SharedAppTheme.secondaryBackground)
    }
}

// MARK: - Sending overlay

public struct ReplyComposerSendingOverlay: View {
    public var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.1).tint(SharedAppTheme.accent)
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
    }
}
