import SwiftUI
import CoreHaptics

/// A view modifier that applies the EdgeCurve Metal shader as an analyzing
/// animation overlay — identical to the Edge Curve Lab setup including
/// haptics, colors, opacity, and blend mode (.softLight for the shader line).
/// Only the "Analyzing" text uses .difference so it stays visible on any background.
struct EdgeCurveOverlay: ViewModifier {
    let isActive: Bool

    private let lineWidth: Double = 0.0231
    private let edgeHeight: Double = 0.086
    private let edgeSharpness: Double = 6.4
    private let meltTop: Double = 0.035
    private let meltBottom: Double = 0.022
    private let meltStartTop: Double = 0.63
    private let meltStartBottom: Double = 0.63
    private let blurCenter: Double = 0.0477
    private let blurEdge: Double = 0.1297
    private let blurCurve: Double = 2.09
    private let motionBlur: Double = 0.2215
    private let chromaAmount: Double = 0.0323
    private let stretchAmount: Double = 0.0994
    private let stretchFalloff: Double = 0.2794
    private let lineColor: Color = .white
    private let opacityCenter: Double = 0.9759
    private let opacityEdge: Double = 0.9233

    private let topY: Double = 0.12
    private let bottomY: Double = 0.88
    private let travelDuration: Double = 2.34
    private let cp1x: Double = 0.38
    private let cp1y: Double = 0.10
    private let cp2x: Double = 0.07
    private let cp2y: Double = 1.0
    private let flipDuration: Double = 0.82
    private let flipBounce: Double = 0.80

    private let hapticIntensity: Double = 0.858
    private let hapticSharpness: Double = 0.6548

    @State private var lineY: Double = 0.12
    @State private var progress: Double = 0.0
    @State private var cycleTask: Task<Void, Never>?
    @State private var haptics = EdgeCurveHapticState()

    private var travelAnimation: Animation {
        .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: travelDuration)
    }

    private var flipAnimation: Animation {
        .spring(duration: flipDuration, bounce: flipBounce)
    }

    func body(content: Content) -> some View {
        if isActive {
            ZStack {
                content
                    .visualEffect { effect, proxy in
                        effect.distortionEffect(
                            ShaderLibrary.bgStretch(
                                .float2(proxy.size),
                                .float(lineY),
                                .float(progress),
                                .float(stretchAmount),
                                .float(stretchFalloff),
                                .float(topY),
                                .float(bottomY)
                            ),
                            maxSampleOffset: CGSize(
                                width: 0,
                                height: stretchAmount * proxy.size.height
                            )
                        )
                    }

                Color.white
                    .visualEffect { effect, proxy in
                        let resolved = lineColor.resolve(in: EnvironmentValues())
                        let rgb = SIMD4<Float>(
                            resolved.linearRed,
                            resolved.linearGreen,
                            resolved.linearBlue,
                            1.0
                        )
                        return effect.colorEffect(
                            ShaderLibrary.edgeCurve(
                                .float2(proxy.size),
                                .float(lineWidth),
                                .float(edgeHeight),
                                .float(edgeSharpness),
                                .float(meltTop),
                                .float(meltBottom),
                                .float(meltStartTop),
                                .float(meltStartBottom),
                                .float(progress),
                                .float(lineY),
                                .float(blurCenter),
                                .float(blurEdge),
                                .float(blurCurve),
                                .float(motionBlur),
                                .float(topY),
                                .float(bottomY),
                                .float(chromaAmount),
                                .float4(rgb.x, rgb.y, rgb.z, rgb.w),
                                .float(opacityCenter),
                                .float(opacityEdge)
                            )
                        )
                    }
                    .blendMode(.softLight)

                Text("Analyzing")
                    .font(.title2.weight(.semibold))
                    .blendMode(.difference)
                    .allowsHitTesting(false)
            }
            .onAppear { startCycle() }
            .onDisappear { stopCycle() }
        } else {
            content
                .onAppear { stopCycle() }
        }
    }

    // MARK: - Animation Cycle

    private func startCycle() {
        cycleTask?.cancel()
        cycleTask = nil
        setupHaptics()

        cycleTask = Task { @MainActor in
            lineY = topY
            progress = 0.0

            withAnimation(travelAnimation) {
                lineY = bottomY
            }
            await waitWithHaptics(duration: travelDuration)
            guard !Task.isCancelled else { return }

            while !Task.isCancelled {
                let goingUp = lineY >= bottomY
                withAnimation(flipAnimation) {
                    progress = goingUp ? 1.0 : 0.0
                }
                withAnimation(travelAnimation) {
                    lineY = goingUp ? topY : bottomY
                }
                await waitWithHaptics(duration: travelDuration)
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func stopCycle() {
        cycleTask?.cancel()
        cycleTask = nil
        teardownHaptics()
    }

    // MARK: - Haptics

    private func setupHaptics() {
        teardownHaptics()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true

            engine.stoppedHandler = { [weak engine] _ in
                try? engine?.start()
            }
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }

            try engine.start()
            haptics.engine = engine
        } catch {}
    }

    private func teardownHaptics() {
        haptics.engine?.stop()
        haptics.engine = nil
    }

    private func fireTransientHaptic(intensity: Float, sharpness: Float) {
        guard let engine = haptics.engine else { return }
        let clampedI = max(0, min(1, intensity))
        let clampedS = max(0, min(1, sharpness))
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedI),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: clampedS)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private func waitWithHaptics(duration: Double) async {
        let start = CACurrentMediaTime()
        var lastThudTime: Double = -1

        let minInterval = 0.035
        let maxInterval = 0.45

        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - start
            if elapsed >= duration { break }

            let t = elapsed / duration
            let velocity = abs(bezierVelocity(at: t))
            let normalizedV = min(velocity / 3.5, 1.0)
            let interval = maxInterval - (maxInterval - minInterval) * pow(normalizedV, 0.6)
            let intensity = Float(min(velocity * hapticIntensity, 1.0))

            if elapsed - lastThudTime >= interval && intensity > 0.02 {
                fireTransientHaptic(intensity: intensity, sharpness: Float(hapticSharpness))
                lastThudTime = elapsed
            }

            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    // MARK: - Bezier Velocity

    private func bezierVelocity(at t: Double) -> Double {
        let u = solveBezierX(t, p1: cp1x, p2: cp2x)
        let dydu = bezierDeriv(u, p1: cp1y, p2: cp2y)
        let dxdu = bezierDeriv(u, p1: cp1x, p2: cp2x)
        return dxdu > 1e-10 ? dydu / dxdu : 0
    }

    private func bezierEval(_ u: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - u
        return 3 * mt * mt * u * p1 + 3 * mt * u * u * p2 + u * u * u
    }

    private func bezierDeriv(_ u: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - u
        return 3 * mt * mt * p1 + 6 * mt * u * (p2 - p1) + 3 * u * u * (1 - p2)
    }

    private func solveBezierX(_ t: Double, p1: Double, p2: Double) -> Double {
        var u = t
        for _ in 0..<8 {
            let err = bezierEval(u, p1: p1, p2: p2) - t
            let d = bezierDeriv(u, p1: p1, p2: p2)
            guard abs(d) > 1e-10 else { break }
            u -= err / d
            u = max(0, min(1, u))
        }
        return u
    }
}

// MARK: - Haptic State

private final class EdgeCurveHapticState {
    var engine: CHHapticEngine?
}

extension View {
    func edgeCurveOverlay(isActive: Bool) -> some View {
        modifier(EdgeCurveOverlay(isActive: isActive))
    }
}
