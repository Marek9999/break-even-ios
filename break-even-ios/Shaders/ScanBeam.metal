#include <metal_stdlib>
using namespace metal;

/// Scanning beam colorEffect shader with trailing motion, edge curvature,
/// and asymmetric Gaussian glow.
///
/// Parameters (after the two SwiftUI-provided ones):
///   size        – view dimensions in points
///   scanY       – normalised vertical position of the beam centre (0 = top, 1 = bottom)
///   velocity    – normalised beam velocity (positive = moving down, negative = up, 0 = stopped)
///   beamWidth   – base spread of the glow (reasonable range 0.01 – 0.15)
///   intensity   – overall brightness multiplier (reasonable range 0.1 – 1.5)
///   trailLength – how far the beam stretches behind its direction of travel (0 – 0.15)
///   curvature   – how much the beam bows outward at left/right edges (0 – 0.15)
[[ stitchable ]] half4 scanBeam(
    float2 position,
    half4  currentColor,
    float2 size,
    float  scanY,
    float  velocity,
    float  beamWidth,
    float  intensity,
    float  trailLength,
    float  curvature
) {
    float nx = position.x / size.x;
    float ny = position.y / size.y;

    // --- Edge curvature ---
    // The beam stays perfectly straight across the middle ~70% of the width.
    // Only in the outer ~15% on each side does it flick outward, as if the
    // light is clinging to the screen edges.
    float nx01 = abs(nx - 0.5) * 2.0;              // 0 at centre, 1 at edges
    float edgeFactor = smoothstep(0.7, 1.0, nx01);  // 0 in the flat zone, ramps to 1 at edges

    float curveDir = velocity >= 0.0 ? 1.0 : -1.0;
    float effectiveScanY = scanY + curvature * edgeFactor * curveDir;

    // Edges also get softer/wider to simulate dispersion.
    float edgeWidthScale = 1.0 + edgeFactor * curvature * 6.0;

    // --- Asymmetric (trailing) beam ---
    float signedDist = ny - effectiveScanY;
    float absDist    = abs(signedDist);
    float absVel     = abs(velocity);
    float trail      = absVel * trailLength;

    // Trailing side = behind the direction of travel.
    //   Going down (velocity > 0): pixels above the beam (signedDist < 0) are trailing.
    //   Going up   (velocity < 0): pixels below the beam (signedDist > 0) are trailing.
    bool isTrailing = (signedDist * velocity) < 0.0;

    float baseWidth      = beamWidth * edgeWidthScale;
    float effectiveWidth = isTrailing ? (baseWidth + trail) : baseWidth;

    // Dual-Gaussian glow (sharp core + soft halo)
    float sigmaSharp = effectiveWidth * 0.3;
    float sigmaSoft  = effectiveWidth;

    float sharp = exp(-absDist * absDist / (2.0 * sigmaSharp * sigmaSharp));
    float soft  = exp(-absDist * absDist / (2.0 * sigmaSoft  * sigmaSoft));

    // Leading edge brightens, trailing edge dims proportionally to speed.
    float intensityMod = isTrailing
        ? mix(1.0, 0.4, absVel)
        : mix(1.0, 1.3, absVel);

    float glow = (sharp * 0.65 + soft * 0.35) * intensity * intensityMod;

    // Blend towards white; preserve the original alpha.
    half3 blended = mix(currentColor.rgb, half3(1.0), half(saturate(glow)));
    return half4(blended, currentColor.a);
}
