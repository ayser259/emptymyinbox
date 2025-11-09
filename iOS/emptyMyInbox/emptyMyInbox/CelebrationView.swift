//
//  CelebrationView.swift
//  emptyMyInbox
//
//  Celebration view for reaching inbox zero
//

import SwiftUI

struct CelebrationView: View {
    @State private var currentMessageIndex = 0
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var animationTimer: Timer?
    
    private let messages = [
        "Good job on reaching inbox zero!",
        "You did it! You cleared your inbox.",
        "Inbox zero achieved! 🎉",
        "Congratulations! Your inbox is empty!",
        "Amazing work! All caught up!",
        "You're a productivity champion!",
        "Inbox zero unlocked! 🚀",
        "Mission accomplished!",
        "You've mastered your inbox!"
    ]
    
    // Image names - rotating one per day
    private var celebrationImageName: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let imageIndex = (dayOfYear - 1) % 10 + 1 // Rotate through catchup1 to catchup10
        return "catchup\(imageIndex)"
    }
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            // Confetti
            ForEach(confettiParticles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
            }
            
            VStack(spacing: AppTheme.spacingLarge) {
                Spacer()
                
                // Celebration image (rotates once per day)
                Image(celebrationImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .padding()
                
                // Rotating message
                Text(messages[currentMessageIndex])
                    .font(AppTheme.title)
                    .primaryText()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingLarge)
                    .transition(.opacity.combined(with: .scale))
                
                Spacer()
            }
            .onAppear {
                startCelebration()
            }
            .onDisappear {
                animationTimer?.invalidate()
            }
        }
    }
    
    private func startCelebration() {
        // Create confetti particles
        createConfetti()
        
        // Rotate messages every 3 seconds
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentMessageIndex = (currentMessageIndex + 1) % messages.count
            }
        }
    }
    
    private func createConfetti() {
        let screenWidth = UIScreen.main.bounds.width
        
        confettiParticles = (0..<100).map { _ in
            ConfettiParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...screenWidth),
                    y: -20
                ),
                color: [AppTheme.accent, Color.red, Color.blue, Color.green, Color.yellow, Color.pink, Color.orange].randomElement() ?? AppTheme.accent,
                size: CGFloat.random(in: 8...16),
                velocity: CGPoint(
                    x: CGFloat.random(in: -50...50),
                    y: CGFloat.random(in: 100...200)
                )
            )
        }
        
        // Animate confetti falling
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let screenHeight = UIScreen.main.bounds.height
            let screenWidth = UIScreen.main.bounds.width
            
            var updatedParticles = confettiParticles
            for i in updatedParticles.indices {
                updatedParticles[i].position.x += updatedParticles[i].velocity.x * 0.05
                updatedParticles[i].position.y += updatedParticles[i].velocity.y * 0.05
                
                // Reset particles that fall off screen
                if updatedParticles[i].position.y > screenHeight + 50 {
                    updatedParticles[i].position = CGPoint(
                        x: CGFloat.random(in: 0...screenWidth),
                        y: -20
                    )
                }
            }
            confettiParticles = updatedParticles
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    let velocity: CGPoint
}

#Preview {
    CelebrationView()
}

