//
//  MacActionItemsTabViews.swift
//  emptymyinboxMacApp
//
//  Planner placeholder + horizontal “boards” layout for Action Items categories (Mac).
//

import SwiftUI
import EmptyMyInboxShared

// MARK: - Planner (WIP)

struct MacPlannerPlaceholderView: View {
    var body: some View {
        ZStack {
            MacAppTheme.primaryBackground
            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(MacAppTheme.accent.opacity(0.85))
                    .symbolRenderingMode(.hierarchical)

                Text("Planner")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)

                Text("A dedicated planning workspace is on the way. You will be able to schedule and balance work across labels and projects from here.")
                    .font(.body)
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Text("Work in progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacAppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .strokeBorder(MacAppTheme.accent.opacity(0.45), lineWidth: 1)
                    )
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Boards (horizontal columns)

private let macBoardColumnWidth: CGFloat = 264
private let macBoardColumnCornerRadius: CGFloat = MacAppTheme.cornerRadiusSmall + 4

struct MacActionItemsBoardsScrollView<Row: View>: View {
    let columns: [ActionItemsBoardColumn]
    /// When `true`, column headers get the label accent color menu (`boardId` is the subject key).
    var isLabelsCategory: Bool = false
    var onAccentPreset: (String, String) -> Void = { _, _ in }
    var onAccentCustomRequest: (String) -> Void = { _ in }
    @ViewBuilder var row: (VaultActionItemRecord) -> Row

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(columns, id: \.boardId) { column in
                    macBoardColumn(column)
                }
            }
            .padding(.horizontal, MacAppTheme.spacingMedium)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    MacAppTheme.primaryBackground,
                    Color(hex: "#050505")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func macBoardColumn(_ column: ActionItemsBoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            MacAppTheme.accent,
                            MacAppTheme.accent.opacity(0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .opacity(0.95)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(column.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("\(column.items.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MacAppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(MacAppTheme.accent.opacity(0.14))
                            .overlay(
                                Capsule()
                                    .strokeBorder(MacAppTheme.accent.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.55)
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                }
            )
            .contextMenu {
                if isLabelsCategory {
                    Menu("Accent color") {
                        ForEach(ContextAccentPalette.presets) { preset in
                            Button(preset.name) {
                                onAccentPreset(column.boardId, preset.hex)
                            }
                        }
                        Divider()
                        Button("Custom hex…") {
                            onAccentCustomRequest(column.boardId)
                        }
                    }
                }
            }

            if column.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.dashed")
                        .font(.title2.weight(.light))
                        .foregroundStyle(MacAppTheme.secondaryText.opacity(0.55))
                        .symbolRenderingMode(.hierarchical)
                    Text("No items")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MacAppTheme.secondaryText.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(column.items) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .background(Color.black.opacity(0.38))
            }
        }
        .frame(width: macBoardColumnWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: macBoardColumnCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1c1c1c"),
                            Color(hex: "#121212")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: macBoardColumnCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: macBoardColumnCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.65), radius: 22, y: 10)
    }
}
