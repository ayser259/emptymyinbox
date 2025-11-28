//
//  CelebrationView.swift
//  emptyMyInbox
//
//  Celebration view for reaching inbox zero
//

import SwiftUI
import UIKit

struct CelebrationView: View {
    let emailsCleared: Int?
    let sessionStartTime: Date?
    let accountEmail: String?
    
    @State private var currentMessageIndex = 0
    @State private var timerEndTime: Date? // When celebration view appeared (timer stops)
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var pulseScale: CGFloat = 1.0
    @State private var emojiScale: CGFloat = 0.0
    @State private var showContent = false
    @State private var ringScale: CGFloat = 0.0
    @State private var ringOpacity: Double = 1.0
    @State private var backgroundGlow: Double = 0.0
    @Environment(\.dismiss) var dismiss
    
    init(emailsCleared: Int? = nil, sessionStartTime: Date? = nil, accountEmail: String? = nil) {
        self.emailsCleared = emailsCleared
        self.sessionStartTime = sessionStartTime
        self.accountEmail = accountEmail
    }
    
    private var messages: [String] {
        let baseMessages = [
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
        
        // Add context-aware messages
        var contextMessages: [String] = []
        
        if let cleared = emailsCleared, cleared > 0 {
            if cleared == 1 {
                contextMessages.append("One email down, inbox zero achieved! 🎯")
            } else if cleared < 5 {
                contextMessages.append("You cleared \(cleared) emails! Great work! 💪")
            } else if cleared < 20 {
                contextMessages.append("Wow! \(cleared) emails cleared! You're on fire! 🔥")
            } else {
                contextMessages.append("Incredible! \(cleared) emails cleared! You're unstoppable! ⚡")
            }
        }
        
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            contextMessages.append("What a productive morning! ☀️")
        } else if hour < 17 {
            contextMessages.append("Afternoon inbox zero! Keep it up! 🌤️")
        } else if hour < 21 {
            contextMessages.append("Evening victory! Well done! 🌆")
        } else {
            contextMessages.append("Late night productivity! Impressive! 🌙")
        }
        
        return contextMessages + baseMessages
    }
    
    private var timeTaken: TimeInterval? {
        guard let startTime = sessionStartTime else { return nil }
        // Timer stops when celebration view appears
        let endTime = timerEndTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }
    
    private var formattedTime: String? {
        guard let time = timeTaken else { return nil }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
    
    var body: some View {
        ZStack {
            // Background with gradient and glow
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            // Radial gradient glow
            RadialGradient(
                gradient: Gradient(colors: [
                    AppTheme.accent.opacity(backgroundGlow * 0.3),
                    AppTheme.accent.opacity(backgroundGlow * 0.1),
                    Color.clear
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            .opacity(backgroundGlow)
            
            // Pulsing rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        AppTheme.accent.opacity(ringOpacity * 0.4),
                        lineWidth: 2
                    )
                    .frame(width: 200 + CGFloat(index * 100), height: 200 + CGFloat(index * 100))
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
            }
            
            // Confetti particles (behind stats)
            ForEach(confettiParticles) { particle in
                ConfettiShape(shape: particle.shape)
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .rotationEffect(.degrees(particle.rotation))
                    .position(particle.position)
            }
            
            VStack(spacing: AppTheme.spacingLarge) {
                Spacer()
                
                // Premium single card containing logo, message, and stats
                VStack(spacing: AppTheme.spacingLarge) {
                    // Animated app icon
                    LogoView(size: 80)
                        .scaleEffect(emojiScale)
                        .opacity(showContent ? 1 : 0)
                    
                    // Main celebration message with pulse
                    Text(messages[currentMessageIndex])
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.spacingMedium)
                        .scaleEffect(pulseScale)
                        .opacity(showContent ? 1 : 0)
                        .transition(.opacity.combined(with: .scale))
                    
                    // Stats area
                    if let cleared = emailsCleared, cleared > 0 {
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal, AppTheme.spacingLarge)
                        
                        if let time = formattedTime {
                            Text("You cleared \(cleared) email\(cleared == 1 ? "" : "s") in \(time)!")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.spacingMedium)
                        } else {
                            Text("You cleared \(cleared) email\(cleared == 1 ? "" : "s")!")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.spacingMedium)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingXLarge)
                .padding(.vertical, AppTheme.spacingXLarge)
                .background(
                    ZStack {
                        // Base gradient background
                        RoundedRectangle(cornerRadius: 32)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "#0a0a0a"),
                                        Color(hex: "#1a1a1a"),
                                        Color.black
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Subtle accent glow
                        RoundedRectangle(cornerRadius: 32)
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        AppTheme.accent.opacity(0.15),
                                        AppTheme.accent.opacity(0.05),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 200
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    AppTheme.accent.opacity(0.8),
                                    AppTheme.accent.opacity(0.4),
                                    AppTheme.accent.opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.black.opacity(0.8), radius: 40, x: 0, y: 20)
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 30, x: 0, y: 15)
                .shadow(color: AppTheme.accent.opacity(0.1), radius: 20, x: 0, y: 10)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1.0 : 0.8)
                .zIndex(100) // Above confetti
                
                Spacer()
                
                // Action buttons
                VStack(spacing: AppTheme.spacingMedium) {
                    // Done button
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(AppTheme.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingUnit)
                            .background(AppTheme.accent)
                            .cornerRadius(AppTheme.cornerRadiusMedium)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(showContent ? 1 : 0)
                }
                .padding(.horizontal, AppTheme.spacingLarge)
                .padding(.bottom, AppTheme.spacingXLarge)
            }
        }
        .onAppear {
            // Stop timer when celebration view appears
            if timerEndTime == nil {
                timerEndTime = Date()
            }
            startCelebration()
        }
    }
    
    private var shareMessage: String {
        var message = "🎉 I just reached inbox zero!"
        if let cleared = emailsCleared, cleared > 0 {
            message += " Cleared \(cleared) email\(cleared == 1 ? "" : "s")"
            if let time = formattedTime {
                message += " in \(time)"
            }
            message += "!"
        }
        return message
    }
    
    private func startCelebration() {
        // Haptic feedback on appear
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Initial burst of confetti
        createConfettiBurst()
        
        // Animate content appearance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showContent = true
            emojiScale = 1.0
            backgroundGlow = 1.0
        }
        
        // Pulse animation for message
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        
        // Pulsing rings animation
        withAnimation(.easeOut(duration: 2.0)) {
            ringScale = 1.5
            ringOpacity = 0.0
        }
        
        // Continuous confetti
        startContinuousConfetti()
        
        // Rotate messages every 3 seconds
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentMessageIndex = (currentMessageIndex + 1) % messages.count
            }
        }
    }
    
    private func createConfettiBurst() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        
        // Create burst from center
        confettiParticles = (0..<150).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = Double.random(in: 0...300)
            let x = centerX + CGFloat(cos(angle) * distance)
            let y = centerY + CGFloat(sin(angle) * distance)
            
            return ConfettiParticle(
                position: CGPoint(x: x, y: y),
                color: [AppTheme.accent, Color.red, Color.blue, Color.green, Color.yellow, Color.pink, Color.orange, Color.purple, Color.cyan].randomElement() ?? AppTheme.accent,
                size: CGFloat.random(in: 8...20),
                velocity: CGPoint(
                    x: CGFloat.random(in: -100...100),
                    y: CGFloat.random(in: -100...100)
                ),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -180...180),
                shape: [.circle, .star, .diamond].randomElement() ?? .circle
            )
        }
    }
    
    private func startContinuousConfetti() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // Add new particles periodically
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Add 2-3 new particles at random positions from top
            for _ in 0..<Int.random(in: 2...3) {
                let newParticle = ConfettiParticle(
                    position: CGPoint(
                        x: CGFloat.random(in: 0...screenWidth),
                        y: -20
                    ),
                    color: [AppTheme.accent, Color.red, Color.blue, Color.green, Color.yellow, Color.pink, Color.orange, Color.purple, Color.cyan].randomElement() ?? AppTheme.accent,
                    size: CGFloat.random(in: 8...16),
                    velocity: CGPoint(
                        x: CGFloat.random(in: -50...50),
                        y: CGFloat.random(in: 100...200)
                    ),
                    rotation: Double.random(in: 0...360),
                    rotationSpeed: Double.random(in: -90...90),
                    shape: [.circle, .star, .diamond].randomElement() ?? .circle
                )
                
                confettiParticles.append(newParticle)
            }
            
            // Update existing particles
            var updatedParticles: [ConfettiParticle] = []
            for i in confettiParticles.indices {
                var particle = confettiParticles[i]
                particle.position.x += particle.velocity.x * 0.05
                particle.position.y += particle.velocity.y * 0.05
                particle.rotation += particle.rotationSpeed * 0.05
                
                // Reset particles that fall off screen
                if particle.position.y > screenHeight + 50 {
                    particle.position = CGPoint(
                        x: CGFloat.random(in: 0...screenWidth),
                        y: -20
                    )
                    particle.velocity = CGPoint(
                        x: CGFloat.random(in: -50...50),
                        y: CGFloat.random(in: 100...200)
                    )
                    particle.rotation = Double.random(in: 0...360)
                }
                
                // Keep particles that are still on screen
                if particle.position.x >= -50 && particle.position.x <= screenWidth + 50 {
                    updatedParticles.append(particle)
                }
            }
            
            // Keep only last 200 particles for performance
            if updatedParticles.count > 200 {
                updatedParticles = Array(updatedParticles.suffix(200))
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
    var velocity: CGPoint
    var rotation: Double
    let rotationSpeed: Double
    let shape: ConfettiShapeType
}

enum ConfettiShapeType {
    case circle
    case star
    case diamond
}

struct ConfettiShape: Shape {
    let shape: ConfettiShapeType
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = min(rect.width, rect.height)
        
        switch shape {
        case .circle:
            path.addEllipse(in: rect)
        case .star:
            // 5-pointed star
            let points = 5
            let outerRadius = size / 2
            let innerRadius = outerRadius * 0.4
            for i in 0..<points * 2 {
                let angle = Double(i) * .pi / Double(points) - .pi / 2
                let radius = i % 2 == 0 ? outerRadius : innerRadius
                let x = center.x + CGFloat(cos(angle) * radius)
                let y = center.y + CGFloat(sin(angle) * radius)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: center.x, y: center.y - size/2))
            path.addLine(to: CGPoint(x: center.x + size/2, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size/2))
            path.addLine(to: CGPoint(x: center.x - size/2, y: center.y))
            path.closeSubpath()
        }
        
        return path
    }
}

#Preview {
    CelebrationView(emailsCleared: 15, sessionStartTime: Date().addingTimeInterval(-300), accountEmail: "test@example.com")
}
