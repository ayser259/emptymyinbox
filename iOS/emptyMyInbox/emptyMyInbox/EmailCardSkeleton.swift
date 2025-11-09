//
//  EmailCardSkeleton.swift
//  emptyMyInbox
//
//  Skeleton loading view for email cards
//

import SwiftUI

struct EmailCardSkeleton: View {
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            // Header skeleton
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                // Sender and date row
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525").opacity(0.3))
                        .frame(width: 150, height: 20)
                    
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525").opacity(0.3))
                        .frame(width: 80, height: 16)
                }
                
                // Subject row
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#252525").opacity(0.3))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
            }
            .padding(AppTheme.spacingMedium)
            .background(Color(hex: "#252525"))
            
            // Body skeleton
            GeometryReader { scrollGeometry in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<8) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#252525").opacity(0.2))
                            .frame(height: 16)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(AppTheme.spacingMedium)
            }
            .background(Color(hex: "#252525"))
        }
        .background(Color(hex: "#252525"))
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.accent, lineWidth: 2)
        )
        .padding(.horizontal, AppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: geometry.size.height * 0.85)
        .shimmer()
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
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
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width + 200
                }
            }
    }
}

#Preview {
    GeometryReader { geometry in
        EmailCardSkeleton(geometry: geometry)
    }
}

