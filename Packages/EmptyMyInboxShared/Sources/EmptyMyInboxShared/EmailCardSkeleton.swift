//
//  EmailCardSkeleton.swift
//  EmptyMyInboxShared
//

import SwiftUI

public struct EmailCardSkeleton: View {
    public let geometry: GeometryProxy

    public init(geometry: GeometryProxy) {
        self.geometry = geometry
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SharedAppTheme.spacingExtraSmall) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525").opacity(0.3))
                        .frame(width: 150, height: 20)

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525").opacity(0.3))
                        .frame(width: 80, height: 16)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#252525").opacity(0.3))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
            }
            .padding(SharedAppTheme.spacingMedium)
            .background(Color(hex: "#252525"))

            GeometryReader { _ in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#252525").opacity(0.2))
                            .frame(height: 16)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(SharedAppTheme.spacingMedium)
            }
            .background(Color(hex: "#252525"))
        }
        .background(Color(hex: "#252525"))
        .cornerRadius(SharedAppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium)
                .stroke(SharedAppTheme.accent, lineWidth: 2)
        )
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: geometry.size.height * 0.85)
        .shimmer()
    }
}

public extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.2),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 200)
                    .offset(x: phase)
                    .onAppear {
                        let w = max(geometry.size.width, 400)
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = w + 200
                        }
                    }
                }
            )
    }
}
