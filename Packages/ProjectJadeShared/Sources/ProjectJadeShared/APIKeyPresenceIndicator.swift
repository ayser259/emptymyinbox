import SwiftUI

/// Shows whether a provider API key is stored, without revealing key material.
public struct APIKeyPresenceIndicator: View {
    public let status: LLMAPIKeyStatus?

    public init(status: LLMAPIKeyStatus?) {
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("API key")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SharedAppTheme.secondaryText)

                Spacer(minLength: 8)

                if status != nil {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SharedAppTheme.accent)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("Not added")
                        .font(.subheadline)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
            }

            if let status {
                Text("Added on \(Self.formattedDate(status.addedAt))")
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let status {
            return "API key added on \(Self.formattedDate(status.addedAt))"
        }
        return "API key not added"
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
