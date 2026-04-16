import SwiftUI

/// Account row for Settings: Mail / Calendar / Drive status and vault link.
public struct SettingsConnectedAccountRow: View {
    let account: GmailAccount
    let vaultConfiguration: VaultActiveConfiguration?
    let accent: Color
    let onDisconnect: () -> Void

    public init(
        account: GmailAccount,
        vaultConfiguration: VaultActiveConfiguration?,
        accent: Color,
        onDisconnect: @escaping () -> Void
    ) {
        self.account = account
        self.vaultConfiguration = vaultConfiguration
        self.accent = accent
        self.onDisconnect = onDisconnect
    }

    private var summary: GmailAccount.ConnectionSummary {
        account.connectionSummary(activeVault: vaultConfiguration)
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

            vaultLinkRow
        }
        .padding(.vertical, 4)
    }

    private var serviceChipsRow: some View {
        HStack(spacing: 10) {
            serviceChip(title: "Mail", on: summary.gmail)
            serviceChip(title: "Calendar", on: summary.calendar)
            serviceChip(title: "Drive", on: summary.drive)
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

    @ViewBuilder
    private var vaultLinkRow: some View {
        if summary.vaultLinked, let line = summary.vaultDetailLine {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 16, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vault linked to this account")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SharedAppTheme.secondaryText)
                    Text(line)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SharedAppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 2)
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.6))
                    .frame(width: 16, alignment: .leading)
                Text("No vault linked to this account (or vault is owned by another account).")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)
        }
    }
}
