//
//  OnboardingWelcomeView.swift
//  PayUp
//
//  First onboarding screen. Avatar bubbles are shot from the bottom
//  one-by-one with haptic feedback (slow opening, then a fast burst);
//  once the cannon finishes, the heading and the stacked Apple/Google
//  glass buttons fade in.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    var onAppleTap: () -> Void = {}
    var onGoogleTap: () -> Void = {}

    @State private var showText = false
    @State private var showGradient = false

    /// Same bluish/lavender rim color used on the home screen's top half.
    private let topEdgeLightColor = Color(red: 128 / 255, green: 123 / 255, blue: 1.0, opacity: 1.0)

    /// Per-screen shader config. Stays local so it can never affect the
    /// home screen's overlay (which owns its own configuration).
    private let edgeLightConfiguration: HomeEdgeLightConfiguration = {
        var config = HomeEdgeLightConfiguration()
        config.rimWidth = 0.007
        config.glowWidth = 0.048
        config.cornerSpread = 0.377
        config.cornerPower = 5.000
        config.hotspotWidth = 0.577
        config.hotspotIntensity = 1.245
        config.driftSpeed = 0.950
        config.shimmerAmount = 0.400
        config.pulseAmount = 0.300
        config.intensity = 0.530
        config.sideReach = 0.180
        config.sideIntensity = 0.840
        config.falloffSharpness = 1.560
        config.blurReach = 2.500
        return config
    }()

    private let bubbles: [BuoyancyPhysicsEngine.BubbleSpec] = OnboardingWelcomeView.makeSampleBubbles()

    var body: some View {
        ZStack {
            Color.homeSectionBackground
                .ignoresSafeArea()

            topEdgeShader
                .ignoresSafeArea()

            BuoyantBubbleClusterView(
                bubbles: bubbles,
                onCannonComplete: { revealText() }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 24) {
                    tagline
                        .padding(.bottom, 32)
                    socialButtons
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 24)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.easeOut(duration: 1.2)) {
                showGradient = true
            }
        }
    }

    private func revealText() {
        withAnimation(.easeOut(duration: 0.6)) {
            showText = true
        }
    }

    // MARK: - Top Edge Shader

    /// Reuses the home screen's rim-light shader, pinned to the top edge of
    /// the onboarding screen. Uses a local @State configuration so tuning on
    /// this screen never propagates to the home screen's overlay.
    private var topEdgeShader: some View {
        HomeEdgeLightOverlay(
            edge: .top,
            color: topEdgeLightColor,
            configuration: edgeLightConfiguration
        )
        .opacity(showGradient ? 1 : 0)
    }

    // MARK: - Tagline

    private var tagline: some View {
        Text("Let the app do the maths,\nyou enjoy the drinks")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: 12) {
            Button(action: onAppleTap) {
                HStack(spacing: 10) {
                    Image("apple")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                    Text("Login with Apple")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)

            Button(action: onGoogleTap) {
                HStack(spacing: 10) {
                    Image("google")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                    Text("Login with Google")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Sample bubble specs

    private static let bubbleEmojiPool: [String] = [
        // Activity
        "🏀", "⚽️", "🎾", "🏈", "⚾️", "🏐", "🥊", "🏓", "🎳", "⛳️",
        "🏒", "🏸", "🎣", "🎱", "🎯", "🎮", "🎲", "🎸", "🎺", "🎷", "🎻", "🎨",
        // Animal
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
        "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🦆", "🦅", "🦉", "🦄",
        "🐝", "🦋", "🐢", "🐠", "🦀", "🦑", "🐙",
        // Food
        "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍒", "🍑", "🥭",
        "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🌽", "🥕", "🍞", "🧀",
        "🥐", "🍕", "🍔", "🌮", "🍣", "🍩", "🍪", "☕️", "🍻"
    ]

    private static func makeSampleBubbles() -> [BuoyancyPhysicsEngine.BubbleSpec] {
        let palette = AvatarColors.palette.map(\.color)
        let radii: [CGFloat] = [44, 32, 38, 28, 46, 34, 30, 40, 36, 42, 30, 36, 28, 44, 34, 38, 32, 40]

        // Sample emojis without replacement so each bubble is distinct.
        var pool = bubbleEmojiPool.shuffled()
        func nextEmoji() -> String {
            if pool.isEmpty { pool = bubbleEmojiPool.shuffled() }
            return pool.removeLast()
        }

        let circles = radii.enumerated().map { index, radius in
            let color = palette[index % palette.count]
            return BuoyancyPhysicsEngine.BubbleSpec(
                id: "onboarding-bubble-\(index)",
                radius: radius,
                color: color,
                emoji: nextEmoji()
            )
        }

        // Continuous-rounded-rect "app icon" bubble. Side is 84pt; physics
        // treats it as a circle of radius 42 so it behaves exactly like the
        // other bubbles. Shot last so it caps off the cannon.
        let appIconSide: CGFloat = 84
        let appIcon = BuoyancyPhysicsEngine.BubbleSpec(
            id: "onboarding-bubble-app-icon",
            radius: appIconSide / 2,
            color: .white.opacity(0.001),
            shape: .roundedRect(side: appIconSide, cornerRadius: 22),
            // Lock between the bubble cluster on top and the tagline below,
            // aimed a bit above center and pinned horizontally to the middle.
            relativeTargetY: 0.38,
            relativeTargetX: 0.5
        )

        return circles + [appIcon]
    }
}

#Preview {
    OnboardingWelcomeView()
}
