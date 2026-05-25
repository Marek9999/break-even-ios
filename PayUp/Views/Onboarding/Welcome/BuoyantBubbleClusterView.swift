//
//  BuoyantBubbleClusterView.swift
//  PayUp
//
//  SwiftUI host for BuoyancyPhysicsEngine. Sequentially shoots bubbles
//  out from the bottom edge with a haptic per spawn, then lets them
//  rise, collide, and settle against the top "ceiling".
//

import SwiftUI
import UIKit

struct BuoyantBubbleClusterView: View {
    let bubbles: [BuoyancyPhysicsEngine.BubbleSpec]
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var initialDelay: Duration = .milliseconds(650)
    /// Number of bubbles fired in the slow opening phase before the rapid burst begins.
    var slowPhaseCount: Int = 3
    /// Interval between shots in the slow opening phase. Long enough that each
    /// bubble visibly hangs in the air before the next one pops out.
    var slowSpawnInterval: Duration = .milliseconds(1000)
    /// Interval between shots in the fast burst phase.
    var fastSpawnInterval: Duration = .milliseconds(80)
    /// Slow-phase launch is now a strong shove so the bubble reaches mid-screen quickly,
    /// then the heavy damping below bleeds it down to a gentle float.
    var slowVelocityRange: ClosedRange<CGFloat> = -1700 ... -1400
    /// Buoyancy multiplier for slow-phase bubbles. < 1 keeps them floating slowly upward
    /// once the initial impulse has decayed.
    var slowBuoyancyMultiplier: CGFloat = 0.32
    /// Aggressive damping for slow-phase bubbles so the strong launch impulse fades fast.
    var slowDampingOverride: CGFloat = 0.93
    /// Vertical launch velocity range for fast-phase bubbles. Damping bleeds this off fast.
    var fastVelocityRange: ClosedRange<CGFloat> = -2600 ... -2200
    /// Aggressive damping for fast-phase bubbles so they rocket out, then settle.
    var fastDampingOverride: CGFloat = 0.92
    /// Called once every bubble has been fired.
    var onCannonComplete: () -> Void = {}

    @State private var engine = BuoyancyPhysicsEngine()
    @State private var containerSize: CGSize = .zero
    @State private var hasSpawned = false
    @State private var visibleIDs: Set<String> = []

    private let coordinateSpaceName = "buoyantBubbleCluster"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(bubbles) { spec in
                    if visibleIDs.contains(spec.id),
                       let position = engine.position(for: spec.id) {
                        BuoyantBubbleView(
                            spec: spec,
                            engine: engine,
                            coordinateSpaceName: coordinateSpaceName
                        )
                        .position(position)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: coordinateSpaceName)
            .task(id: geometry.size) {
                containerSize = geometry.size
                engine.updateContainer(
                    size: geometry.size,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
                guard !hasSpawned, geometry.size.width > 0, geometry.size.height > 0 else { return }
                hasSpawned = true
                await runCannon()
            }
        }
    }

    // MARK: - Sequential cannon

    private func runCannon() async {
        try? await Task.sleep(for: initialDelay)
        let softGenerator = UIImpactFeedbackGenerator(style: .soft)
        let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
        softGenerator.prepare()
        mediumGenerator.prepare()

        for (index, spec) in bubbles.enumerated() {
            let isSlowPhase = index < slowPhaseCount
            let velocityRange = isSlowPhase ? slowVelocityRange : fastVelocityRange
            let interval = isSlowPhase ? slowSpawnInterval : fastSpawnInterval
            let buoyancyMultiplier: CGFloat = isSlowPhase ? slowBuoyancyMultiplier : 1.0
            let dampingOverride: CGFloat? = isSlowPhase ? slowDampingOverride : fastDampingOverride

            let targetY = spec.relativeTargetY.map { containerSize.height * $0 }
            let targetX = spec.relativeTargetX.map { containerSize.width * $0 }

            engine.shootSingle(
                spec: spec,
                in: containerSize,
                topInset: topInset,
                bottomInset: bottomInset,
                verticalVelocityRange: velocityRange,
                buoyancyMultiplier: buoyancyMultiplier,
                dampingOverride: dampingOverride,
                targetY: targetY,
                targetX: targetX
            )
            visibleIDs.insert(spec.id)

            if isSlowPhase {
                softGenerator.impactOccurred()
                softGenerator.prepare()
            } else {
                mediumGenerator.impactOccurred()
                mediumGenerator.prepare()
            }

            try? await Task.sleep(for: interval)
        }

        onCannonComplete()
    }
}

// MARK: - Bubble View

private struct BuoyantBubbleView: View {
    let spec: BuoyancyPhysicsEngine.BubbleSpec
    let engine: BuoyancyPhysicsEngine
    let coordinateSpaceName: String

    @State private var isDragging = false
    @State private var hasStartedDrag = false
    @State private var hasLaunched = false

    /// Roughly mirrors how long it takes the high initial launch velocity
    /// to decay back to the steady buoyancy cruise speed.
    private let launchBounceDuration: Double = 0.7
    private let onboardingIconTopColorStop: CGFloat = 0.0
    private let onboardingIconBottomColorStop: CGFloat = 0.67

    var body: some View {
        bubbleShape
            .scaleEffect(currentScale)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .gesture(dragGesture)
            .onAppear {
                withAnimation(.spring(response: launchBounceDuration, dampingFraction: 0.62)) {
                    hasLaunched = true
                }
            }
    }

    @ViewBuilder
    private var bubbleShape: some View {
        switch spec.shape {
        case .circle:
            ZStack {
                if let imageName = spec.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: spec.radius * 2, height: spec.radius * 2)
                        .clipShape(Circle())
                } else if let emoji = spec.emoji {
                    emojiContent(emoji, sizeBase: spec.radius * 2)
                } else {
                    Circle()
                        .fill(spec.color)
                }
            }
            .frame(width: spec.radius * 2, height: spec.radius * 2)
            .padding(2)
            .glassEffect(.regular.interactive(), in: Circle())

        case let .roundedRect(side, cornerRadius):
            if let imageName = spec.imageName {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(onboardingIconBackgroundGradient)
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .frame(width: side, height: side)
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                ZStack {
                    if let emoji = spec.emoji {
                        emojiContent(emoji, sizeBase: side)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(spec.color)
                    }
                }
                .frame(width: side, height: side)
                .padding(2)
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        }
    }

    private var onboardingIconBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 151 / 255, green: 151 / 255, blue: 248 / 255, opacity: 0.95),
                    location: onboardingIconTopColorStop
                ),
                .init(
                    color: Color(red: 90 / 255, green: 90 / 255, blue: 1.0, opacity: 0.95),
                    location: onboardingIconBottomColorStop
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Renders a soft blurred copy of the emoji behind a crisp foreground
    /// copy, giving the bubble a glowing, depth-y look.
    @ViewBuilder
    private func emojiContent(_ emoji: String, sizeBase: CGFloat) -> some View {
        ZStack {
            Text(emoji)
                .font(.system(size: sizeBase * 0.52))
                .blur(radius: sizeBase * 0.12)
                .opacity(0.25)

            Text(emoji)
                .font(.system(size: sizeBase * 0.52))
        }
    }

    private var currentScale: CGFloat {
        let dragScale: CGFloat = isDragging ? 1.05 : 1.0
        let launchScale: CGFloat = hasLaunched ? 1.0 : 1.3
        return dragScale * launchScale
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if !hasStartedDrag {
                    hasStartedDrag = true
                    isDragging = true
                    engine.startDrag(id: spec.id, to: value.location)
                } else {
                    engine.updateDrag(id: spec.id, to: value.location)
                }
            }
            .onEnded { _ in
                isDragging = false
                hasStartedDrag = false
                engine.endDrag(id: spec.id)
            }
    }
}
