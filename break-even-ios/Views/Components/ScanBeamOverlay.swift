import SwiftUI

/// A reusable modifier that applies a Metal scanning-beam effect to its
/// content and shows an "Analyzing" label with inverted blend mode.
///
/// The beam features:
/// - Asymmetric trailing glow that stretches behind the direction of travel
/// - Edge curvature that bows the beam outward at left/right screen edges
/// - Dual-Gaussian core + halo for an Apple-quality light sweep
struct ScanBeamOverlay: ViewModifier {
    let isActive: Bool
    var beamWidth: Double
    var intensity: Double
    var cycleDuration: Double
    var trailLength: Double
    var curvature: Double

    private let startDate = Date()

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                let scanY = Self.scanPosition(
                    time: elapsed,
                    cycleDuration: cycleDuration
                )
                let velocity = Self.scanVelocity(
                    time: elapsed,
                    cycleDuration: cycleDuration
                )

                content
                    .visualEffect { effect, proxy in
                        effect.colorEffect(
                            ShaderLibrary.scanBeam(
                                .float2(proxy.size),
                                .float(scanY),
                                .float(velocity),
                                .float(beamWidth),
                                .float(intensity),
                                .float(trailLength),
                                .float(curvature)
                            )
                        )
                    }
                    .overlay {
                        Text("Analyzing")
                            .font(.title2.weight(.semibold))
                            .blendMode(.difference)
                            .allowsHitTesting(false)
                    }
            }
        } else {
            content
        }
    }

    // MARK: - Animation Maths

    /// Ping-pong ease-out scan position (0 → 1 → 0).
    static func scanPosition(time: Double, cycleDuration: Double) -> Double {
        let cycle = time.truncatingRemainder(dividingBy: cycleDuration)
        let half = cycleDuration / 2.0
        let goingDown = cycle < half
        let t = goingDown ? cycle / half : (cycle - half) / half
        let eased = 1.0 - pow(1.0 - t, 3.0)
        return goingDown ? eased : 1.0 - eased
    }

    /// Normalised velocity of the beam at the current moment.
    /// Positive = moving down, negative = moving up.
    /// Magnitude is derived from the cubic ease-out derivative: 3·(1-t)².
    static func scanVelocity(time: Double, cycleDuration: Double) -> Double {
        let cycle = time.truncatingRemainder(dividingBy: cycleDuration)
        let half = cycleDuration / 2.0
        let goingDown = cycle < half
        let t = goingDown ? cycle / half : (cycle - half) / half
        let speed = pow(1.0 - t, 2.0) // normalised magnitude (1 at start, 0 at end)
        return goingDown ? speed : -speed
    }
}

extension View {
    /// Applies the scanning-beam shader overlay while `isActive` is true.
    func scanBeamOverlay(
        isActive: Bool,
        beamWidth: Double = 0.05,
        intensity: Double = 0.8,
        cycleDuration: Double = 2.5,
        trailLength: Double = 0.06,
        curvature: Double = 0.04
    ) -> some View {
        modifier(
            ScanBeamOverlay(
                isActive: isActive,
                beamWidth: beamWidth,
                intensity: intensity,
                cycleDuration: cycleDuration,
                trailLength: trailLength,
                curvature: curvature
            )
        )
    }
}
