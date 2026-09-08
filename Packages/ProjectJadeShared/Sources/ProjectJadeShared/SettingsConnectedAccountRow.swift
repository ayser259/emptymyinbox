import SwiftUI

public struct SettingsConnectedAccountRow: View {
    let account: GmailAccount
    let accent: Color
    let onDisconnect: () -> Void

    public init(
        account: GmailAccount,
        accent: Color,
        onDisconnect: @escaping () -> Void
    ) {
        self.account = account
        self.accent = accent
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.3), accent.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SharedAppTheme.primaryText)
                        .lineLimit(1)

                    Text("Google account")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }

                Spacer()

                Button {
                    onDisconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disconnect \(account.email)")
            }

            serviceChipsRow
        }
        .padding(.vertical, 4)
    }

    private var serviceChipsRow: some View {
        HStack(spacing: 10) {
            serviceChip(title: "Mail", on: true)
        }
    }

    private func serviceChip(title: String, on: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Color.green.opacity(0.9) : SharedAppTheme.secondaryText.opacity(0.55))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SharedAppTheme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SharedAppTheme.secondaryBackground.opacity(0.65))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(on ? "connected" : "not connected")")
    }
}
