//
//  CelebrationView.swift
//  EmptyMyInboxShared
//
//  Inbox-zero celebration (shared iOS + macOS; confetti uses approximate bounds on Mac).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct CatchUpSessionStats: Sendable {
    public var reviewed: Int = 0
    public var markedAsRead: Int = 0
    public var keptUnread: Int = 0
    public var starred: Int = 0
    public var uniqueUnsubscribeDomains: Set<String> = []

    public init(
        reviewed: Int = 0,
        markedAsRead: Int = 0,
        keptUnread: Int = 0,
        starred: Int = 0,
        uniqueUnsubscribeDomains: Set<String> = []
    ) {
        self.reviewed = reviewed
        self.markedAsRead = markedAsRead
        self.keptUnread = keptUnread
        self.starred = starred
        self.uniqueUnsubscribeDomains = uniqueUnsubscribeDomains
    }
}

public struct CelebrationView: View {
    public let emailsCleared: Int?
    public let sessionStartTime: Date?
    public let accountEmail: String?
    public let sessionStats: CatchUpSessionStats?

    @State private var currentMessageIndex = 0
    @State private var timerEndTime: Date?
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var pulseScale: CGFloat = 1.0
    @State private var emojiScale: CGFloat = 0.0
    @State private var showContent = false
    @State private var ringScale: CGFloat = 0.0
    @State private var ringOpacity: Double = 1.0
    @State private var backgroundGlow: Double = 0.0
    @Environment(\.dismiss) private var dismiss

    public init(
        emailsCleared: Int? = nil,
        sessionStartTime: Date? = nil,
        accountEmail: String? = nil,
        sessionStats: CatchUpSessionStats? = nil
    ) {
        self.emailsCleared = emailsCleared
        self.sessionStartTime = sessionStartTime
        self.accountEmail = accountEmail
        self.sessionStats = sessionStats
    }

    private var messages: [String] {
        let base = [
            "Good job on reaching inbox zero!",
            "You did it! You cleared your inbox.",
            "Inbox zero achieved! 🎉",
            "Congratulations! Your inbox is empty!"
        ]
        var extra: [String] = []
        if let cleared = emailsCleared, cleared > 0 {
            extra.append("You cleared \(cleared) email\(cleared == 1 ? "" : "s")! 💪")
        }
        return extra + base
    }

    private var timeTaken: TimeInterval? {
        guard let startTime = sessionStartTime else { return nil }
        let endTime = timerEndTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }

    private var formattedTime: String? {
        guard let time = timeTaken else { return nil }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    public var body: some View {
        ZStack {
            SharedAppTheme.primaryBackground
                .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    SharedAppTheme.accent.opacity(backgroundGlow * 0.3),
                    SharedAppTheme.accent.opacity(backgroundGlow * 0.1),
                    Color.clear
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            .opacity(backgroundGlow)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(SharedAppTheme.accent.opacity(ringOpacity * 0.4), lineWidth: 2)
                    .frame(width: 200 + CGFloat(index * 100), height: 200 + CGFloat(index * 100))
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
            }

            ForEach(confettiParticles) { particle in
                ConfettiShape(shape: particle.shape)
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .rotationEffect(.degrees(particle.rotation))
                    .position(particle.position)
            }

            VStack(spacing: SharedAppTheme.spacingLarge) {
                Spacer()

                VStack(spacing: SharedAppTheme.spacingLarge) {
                    LogoView(size: 80)
                        .scaleEffect(emojiScale)
                        .opacity(showContent ? 1 : 0)

                    Text(messages[currentMessageIndex])
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SharedAppTheme.spacingMedium)
                        .scaleEffect(pulseScale)
                        .opacity(showContent ? 1 : 0)

                    if let stats = sessionStats, stats.reviewed > 0 {
                        Divider().background(Color.white.opacity(0.2))
                        if let time = formattedTime {
                            Text("You reviewed \(stats.reviewed) email(s) in \(time)")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(SharedAppTheme.accent)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("You reviewed \(stats.reviewed) email(s)")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(SharedAppTheme.accent)
                        }
                    } else if let cleared = emailsCleared, cleared > 0 {
                        Divider().background(Color.white.opacity(0.2))
                        Text("You cleared \(cleared) email\(cleared == 1 ? "" : "s")!")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(SharedAppTheme.accent)
                    }
                }
                .padding(SharedAppTheme.spacingXLarge)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0a0a0a"), Color(hex: "#1a1a1a"), Color.black],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(SharedAppTheme.accent.opacity(0.5), lineWidth: 2)
                )
                .opacity(showContent ? 1 : 0)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(SharedAppTheme.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharedAppTheme.spacingUnit)
                        .background(SharedAppTheme.accent)
                        .cornerRadius(SharedAppTheme.cornerRadiusMedium)
                }
                .buttonStyle(.plain)
                .opacity(showContent ? 1 : 0)
                .padding(.horizontal, SharedAppTheme.spacingLarge)
                .padding(.bottom, SharedAppTheme.spacingXLarge)
            }
        }
        .onAppear {
            if timerEndTime == nil { timerEndTime = Date() }
            startCelebration()
        }
    }

    private func startCelebration() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        #endif
        createConfettiBurst()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showContent = true
            emojiScale = 1.0
            backgroundGlow = 1.0
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        withAnimation(.easeOut(duration: 2.0)) {
            ringScale = 1.5
            ringOpacity = 0.0
        }
        startContinuousConfetti()
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentMessageIndex = (currentMessageIndex + 1) % max(messages.count, 1)
            }
        }
    }

    private var confettiBounds: (CGFloat, CGFloat) {
        #if os(iOS)
        return (UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        #else
        return (900, 700)
        #endif
    }

    private func createConfettiBurst() {
        let (screenWidth, screenHeight) = confettiBounds
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        confettiParticles = (0..<120).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = Double.random(in: 0...280)
            return ConfettiParticle(
                position: CGPoint(
                    x: centerX + CGFloat(cos(angle) * distance),
                    y: centerY + CGFloat(sin(angle) * distance)
                ),
                color: [SharedAppTheme.accent, .red, .blue, .green, .yellow].randomElement() ?? SharedAppTheme.accent,
                size: CGFloat.random(in: 8...18),
                velocity: CGPoint(x: CGFloat.random(in: -100...100), y: CGFloat.random(in: -100...100)),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -180...180),
                shape: [.circle, .star, .diamond].randomElement() ?? .circle
            )
        }
    }

    private func startContinuousConfetti() {
        let (screenWidth, screenHeight) = confettiBounds
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            for _ in 0..<Int.random(in: 1...2) {
                let p = ConfettiParticle(
                    position: CGPoint(x: CGFloat.random(in: 0...screenWidth), y: -20),
                    color: [SharedAppTheme.accent, .orange, .cyan].randomElement() ?? SharedAppTheme.accent,
                    size: CGFloat.random(in: 6...14),
                    velocity: CGPoint(x: CGFloat.random(in: -40...40), y: CGFloat.random(in: 80...180)),
                    rotation: Double.random(in: 0...360),
                    rotationSpeed: Double.random(in: -90...90),
                    shape: [.circle, .diamond].randomElement() ?? .circle
                )
                confettiParticles.append(p)
            }
            var next: [ConfettiParticle] = []
            for var particle in confettiParticles {
                particle.position.x += particle.velocity.x * 0.05
                particle.position.y += particle.velocity.y * 0.05
                particle.rotation += particle.rotationSpeed * 0.05
                if particle.position.y < screenHeight + 40 {
                    next.append(particle)
                }
            }
            if next.count > 180 { next = Array(next.suffix(180)) }
            confettiParticles = next
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
    case circle, star, diamond
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
            let points = 5
            let outerRadius = size / 2
            let innerRadius = outerRadius * 0.4
            for i in 0..<points * 2 {
                let angle = Double(i) * .pi / Double(points) - .pi / 2
                let radius = i % 2 == 0 ? outerRadius : innerRadius
                let x = center.x + CGFloat(cos(angle) * radius)
                let y = center.y + CGFloat(sin(angle) * radius)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: center.x, y: center.y - size / 2))
            path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2))
            path.addLine(to: CGPoint(x: center.x - size / 2, y: center.y))
            path.closeSubpath()
        }
        return path
    }
}
