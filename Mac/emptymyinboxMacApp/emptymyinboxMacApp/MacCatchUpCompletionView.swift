//
//  MacCatchUpCompletionView.swift
//  emptymyinboxMacApp
//
//  Desktop completion screen for Catch Up (replaces shared CelebrationView on Mac).
//

import SwiftUI
import EmptyMyInboxShared

struct MacCatchUpCompletionView: View {
    let sessionStats: CatchUpSessionStats
    let sessionStartTime: Date?
    let todaySendersReceived: Int
    let todayUnsubscribesTotal: Int
    let onDone: () -> Void

    @FocusState private var doneFocused: Bool

    private var formattedDuration: String? {
        guard let start = sessionStartTime else { return nil }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        let minutes = seconds / 60
        let rem = seconds % 60
        if minutes > 0 { return "\(minutes)m \(rem)s" }
        return "\(rem)s"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 28) {
                header
                summaryCard
            }
            .frame(maxWidth: 560)

            Spacer(minLength: 32)

            doneButton
                .frame(maxWidth: 360)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(completionBackground)
        .onAppear {
            doneFocused = true
        }
    }

    private var completionBackground: some View {
        ZStack {
            MacAppTheme.primaryBackground
            RadialGradient(
                colors: [
                    MacAppTheme.accent.opacity(0.12),
                    MacAppTheme.accent.opacity(0.04),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(MacAppTheme.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Catch up complete")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(MacAppTheme.primaryText)

            Text("Your inbox is ready for what's next.")
                .font(.body)
                .foregroundStyle(MacAppTheme.secondaryText)
        }
        .multilineTextAlignment(.center)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryRow(
                icon: "tray.fill",
                title: reviewSummaryTitle,
                detail: reviewSummaryDetail
            )

            Divider().opacity(0.2)

            summaryRow(
                icon: "envelope.open.fill",
                title: "Marked read",
                detail: "\(sessionStats.markedAsRead) email\(sessionStats.markedAsRead == 1 ? "" : "s")"
            )

            summaryRow(
                icon: "envelope.badge.fill",
                title: "Kept unread",
                detail: "\(sessionStats.keptUnread) to review later"
            )

            if todaySendersReceived > 0 || !sessionStats.reviewedSenders.isEmpty {
                Divider().opacity(0.2)

                summaryRow(
                    icon: "person.2.fill",
                    title: "Senders today",
                    detail: sendersDetail
                )
            }

            if !sessionStats.potentialUnsubscribeSenders.isEmpty || todayUnsubscribesTotal > 0 {
                Divider().opacity(0.2)

                summaryRow(
                    icon: "minus.circle.fill",
                    title: "Unsubscribes",
                    detail: unsubscribeDetail
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(MacAppTheme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var reviewSummaryTitle: String {
        if let duration = formattedDuration {
            return "You reviewed \(sessionStats.reviewed) email\(sessionStats.reviewed == 1 ? "" : "s") in \(duration)"
        }
        return "You reviewed \(sessionStats.reviewed) email\(sessionStats.reviewed == 1 ? "" : "s")"
    }

    private var reviewSummaryDetail: String {
        if sessionStats.starred > 0 {
            return "Including \(sessionStats.starred) starred"
        }
        return "Nice work clearing the queue"
    }

    private var sendersDetail: String {
        let reviewedCount = sessionStats.reviewedSenders.count
        if todaySendersReceived > 0 {
            var text = "Your inbox today had emails from \(todaySendersReceived) sender\(todaySendersReceived == 1 ? "" : "s")"
            if reviewedCount > 0, reviewedCount != todaySendersReceived {
                text += " · you reviewed \(reviewedCount) sender\(reviewedCount == 1 ? "" : "s")"
            }
            return text
        }
        return "You reviewed mail from \(reviewedCount) sender\(reviewedCount == 1 ? "" : "s")"
    }

    private var unsubscribeDetail: String {
        let couldUnsub = sessionStats.potentialUnsubscribeSenders.count
        var parts: [String] = []
        if couldUnsub > 0 {
            parts.append("You could have unsubscribed from \(couldUnsub) of them")
        }
        if todayUnsubscribesTotal > 0 {
            parts.append("You have unsubscribed from \(todayUnsubscribesTotal) today")
        }
        return parts.joined(separator: ". ")
    }

    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacAppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(MacAppTheme.accent)
        .keyboardShortcut(.defaultAction)
        .keyboardShortcut(.return, modifiers: [])
        .focused($doneFocused)
    }
}
