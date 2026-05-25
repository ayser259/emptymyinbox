//
//  EmailReplyComposerView.swift
//  EmptyMyInboxShared
//
//  Platform-native reply composer (iOS sheet / macOS panel).
//

import SwiftUI

public struct EmailReplyComposerView: View {

    @State private var model: ReplyDraftViewModel
    private let onDismiss: (() -> Void)?

    public init(
        email: EmailDetail,
        mode: ReplyMode = .reply,
        isCatchUpContext: Bool = false,
        onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let intent = ReplyIntent(email: email, mode: mode, isCatchUpContext: isCatchUpContext)
        _model = State(initialValue: ReplyDraftViewModel(intent: intent, onCatchUpOutcome: onCatchUpOutcome))
        self.onDismiss = onDismiss
    }

    public init(
        intent: ReplyIntent,
        onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _model = State(initialValue: ReplyDraftViewModel(intent: intent, onCatchUpOutcome: onCatchUpOutcome))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        #if os(iOS)
        EmailReplyComposerIOSView(model: model)
        #else
        EmailReplyComposerMacView(model: model, onDismiss: onDismiss)
        #endif
    }
}
