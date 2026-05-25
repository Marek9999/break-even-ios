import SwiftUI

struct HomeEdgeLightConfiguration: Equatable {
    var rimWidth: Double = 0.0033
    var glowWidth: Double = 0.015
    var cornerSpread: Double = 0.55
    var cornerPower: Double = 5.00
    var hotspotWidth: Double = 0.35
    var hotspotIntensity: Double = 0.94
    var driftSpeed: Double = 0.95
    var shimmerAmount: Double = 0.4
    var pulseAmount: Double = 0.3
    var intensity: Double = 0.53
    var sideReach: Double = 0.18
    var sideIntensity: Double = 0.84
    var falloffSharpness: Double = 1.56
    var blurReach: Double = 2.5
}

struct HomeEdgeLightOverlay: View {
    let edge: VerticalEdge
    let color: Color
    let configuration: HomeEdgeLightConfiguration
    
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Color.white
                .visualEffect { effect, proxy in
                    let resolved = color.resolve(in: EnvironmentValues())
                    return effect.colorEffect(
                        ShaderLibrary.rimEdgeLight(
                            .float2(proxy.size),
                            .float(time),
                            .float(edge == .top ? 0.0 : 1.0),
                            .float(configuration.rimWidth),
                            .float(configuration.glowWidth),
                            .float(configuration.cornerSpread),
                            .float(configuration.cornerPower),
                            .float(configuration.hotspotWidth),
                            .float(configuration.hotspotIntensity),
                            .float(configuration.driftSpeed),
                            .float(configuration.shimmerAmount),
                            .float(configuration.pulseAmount),
                            .float(configuration.intensity),
                            .float(configuration.sideReach),
                            .float(configuration.sideIntensity),
                            .float(configuration.falloffSharpness),
                            .float(configuration.blurReach),
                            .float4(
                                resolved.linearRed,
                                resolved.linearGreen,
                                resolved.linearBlue,
                                resolved.opacity
                            )
                        )
                    )
                }
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}
