import SwiftUI

/// Account row for the settings / menu list (iOS + macOS).
public struct SettingsConnectedAccountRow: View {
    let account: GmailAccount
    let accent: Color
    let onDisconnect: () -> Void

    public init(account: GmailAccount, accent: Color, onDisconnect: @escaping () -> Void) {
        self.account = account
        self.accent = accent
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
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

                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.87, blue: 0.5))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
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
        }
        .padding(.vertical, 4)
    }
}
