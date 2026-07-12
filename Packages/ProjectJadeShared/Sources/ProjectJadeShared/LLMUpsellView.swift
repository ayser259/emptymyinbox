import SwiftUI

public struct LLMUpsellView: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let onAction: () -> Void

    public init(title: String, subtitle: String, actionTitle: String, onAction: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: SharedAppTheme.spacingLarge) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 46))
                .foregroundStyle(SharedAppTheme.accent)

            VStack(spacing: SharedAppTheme.spacingSmall) {
                Text(title)
                    .font(SharedAppTheme.title2)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(SharedAppTheme.body)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SharedAppTheme.spacingLarge)
            }

            Button(actionTitle) {
                onAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(SharedAppTheme.accent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharedAppTheme.primaryBackground)
    }
}
