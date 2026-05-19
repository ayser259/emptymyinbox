//
//  MacReplyComposerSlideInContainer.swift
//  EmptyMyInboxShared
//
//  Split layout: original message on the left, reply composer sliding in from the right.
//

#if os(macOS)
import SwiftUI

public struct MacReplyComposerSlideInContainer<Content: View>: View {
    @Binding var replyPresentation: ReplyComposerPresentation?
    var panelMinWidth: CGFloat
    var panelIdealWidth: CGFloat
    var panelMaxWidth: CGFloat
    var onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)?
    @ViewBuilder private let content: () -> Content

    public init(
        replyPresentation: Binding<ReplyComposerPresentation?>,
        panelMinWidth: CGFloat = 520,
        panelIdealWidth: CGFloat = 580,
        panelMaxWidth: CGFloat = 680,
        onCatchUpOutcome: ((CatchUpReplyOutcome) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._replyPresentation = replyPresentation
        self.panelMinWidth = panelMinWidth
        self.panelIdealWidth = panelIdealWidth
        self.panelMaxWidth = panelMaxWidth
        self.onCatchUpOutcome = onCatchUpOutcome
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)

            if let presentation = replyPresentation {
                Divider().opacity(0.35)

                EmailReplyComposerView(
                    email: presentation.email,
                    mode: presentation.mode,
                    isCatchUpContext: presentation.isCatchUpContext,
                    onCatchUpOutcome: presentation.isCatchUpContext ? onCatchUpOutcome : nil,
                    onDismiss: { replyPresentation = nil }
                )
                .id(presentation.id)
                .frame(width: panelIdealWidth, alignment: .top)
                .frame(maxHeight: .infinity)
                .layoutPriority(2)
                .background(SharedAppTheme.primaryBackground)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.28), value: replyPresentation?.id)
    }
}
#endif
