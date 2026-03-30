//
//  EmailCardView.swift
//  EmptyMyInboxShared
//
//  Email card for Catch Up (iOS + macOS).
//

import SwiftUI

public struct EmailCardView: View {
    public let email: EmailDetail
    public let geometry: GeometryProxy
    public var isActive: Bool
    public var onLoadComplete: (() -> Void)?

    public init(
        email: EmailDetail,
        geometry: GeometryProxy,
        isActive: Bool = true,
        onLoadComplete: (() -> Void)? = nil
    ) {
        self.email = email
        self.geometry = geometry
        self.isActive = isActive
        self.onLoadComplete = onLoadComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SharedAppTheme.spacingExtraSmall) {
                HStack {
                    Text(email.sender_name ?? email.sender)
                        .font(.system(size: 18, weight: .semibold))
                        .primaryText()

                    Spacer()

                    Text(formatCompactDate(email.received_at))
                        .font(.system(size: 14, weight: .medium))
                        .secondaryText()
                }

                HStack {
                    Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                        .font(.system(size: 16, weight: .medium))
                        .primaryText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .padding(SharedAppTheme.spacingMedium)
            .background(Color(hex: "#252525"))

            GeometryReader { scrollGeometry in
                emailBodyScroll(minHeight: scrollGeometry.size.height)
            }
            .background(Color(hex: "#252525"))
        }
        .background(Color(hex: "#252525"))
        .cornerRadius(SharedAppTheme.cornerRadiusMedium)
        .overlay(
            Group {
                if !isActive {
                    Color(hex: "#252525").opacity(0.99)
                        .cornerRadius(SharedAppTheme.cornerRadiusMedium)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium)
                .stroke(SharedAppTheme.accent, lineWidth: 2)
        )
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: geometry.size.height * 0.85)
    }

    @ViewBuilder
    private func emailBodyScroll(minHeight: CGFloat) -> some View {
        #if os(iOS)
        IOSYellowScrollView {
            emailBodyContent(minHeight: minHeight)
        }
        #else
        ScrollView {
            emailBodyContent(minHeight: minHeight)
        }
        #endif
    }

    @ViewBuilder
    private func emailBodyContent(minHeight: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 0) {
            if let bodyHtml = email.body_html, !bodyHtml.isEmpty {
                EmailHTMLWebView(htmlContent: bodyHtml, isDarkMode: false, onLoadComplete: onLoadComplete)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: minHeight)
            } else if !email.body_text.isEmpty {
                if looksLikeHTML(email.body_text) {
                    EmailHTMLWebView(htmlContent: email.body_text, isDarkMode: false, onLoadComplete: onLoadComplete)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: minHeight)
                } else {
                    Text(email.body_text)
                        .font(.system(size: 15))
                        .primaryText()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .onAppear {
                            onLoadComplete?()
                        }
                }
            } else {
                Text(email.snippet)
                    .font(.system(size: 15))
                    .secondaryText()
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .onAppear {
                        onLoadComplete?()
                    }
            }
        }
        .padding(.top, 0)
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .padding(.bottom, SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
    }

    private func looksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") {
            return true
        }
        if trimmed.hasPrefix("<") && (
            trimmed.contains("<head") ||
            trimmed.contains("<body") ||
            trimmed.contains("<div") ||
            trimmed.contains("<table") ||
            trimmed.contains("<style") ||
            trimmed.contains("<meta")
        ) {
            return true
        }
        return false
    }

    private func formatCompactDate(_ dateString: String) -> String {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = formatterWithFractional.date(from: dateString)

        if date == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }

        if date == nil {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            date = dateFormatter.date(from: dateString)
        }

        if let date = date {
            let calendar = Calendar.current

            if calendar.isDateInToday(date) {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "en_US_POSIX")
                timeFormatter.dateFormat = "h:mm a"
                return timeFormatter.string(from: date)
            } else {
                let day = calendar.component(.day, from: date)
                let year = calendar.component(.year, from: date)

                let monthFormatter = DateFormatter()
                monthFormatter.locale = Locale(identifier: "en_US_POSIX")
                monthFormatter.dateFormat = "MMM"
                let monthString = monthFormatter.string(from: date)

                let yearString = "'\(String(year).suffix(2))"

                return "\(day) \(monthString) \(yearString)"
            }
        }

        return dateString
    }
}
