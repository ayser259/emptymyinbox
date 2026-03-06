import SwiftUI

struct LLMUpsellView: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 46))
                .foregroundColor(AppTheme.accent)

            VStack(spacing: AppTheme.spacingSmall) {
                Text(title)
                    .font(AppTheme.title2)
                    .primaryText()
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AppTheme.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingLarge)
            }

            Button(actionTitle) {
                onAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
    }
}
