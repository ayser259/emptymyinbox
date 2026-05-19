//
//  EmailReplyComposerIOSView.swift
//  EmptyMyInboxShared
//

#if os(iOS)
import SwiftUI

struct EmailReplyComposerIOSView: View {
    @Bindable var model: ReplyDraftViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            EmailReplyComposerCoreView(model: model)
                .navigationTitle(model.mode.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            Task {
                                await model.cancelReply()
                                dismiss()
                            }
                        }
                        .disabled(model.isSending)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSending)
        .onChange(of: model.requestDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            isEditorFocused = true
        }
    }
}
#endif
