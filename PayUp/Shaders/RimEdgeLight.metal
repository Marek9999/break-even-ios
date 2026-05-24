#include <metal_stdlib>
using namespace metal;

/// Planet-like rim lighting for the top or bottom edge of a section.
///
/// edgePosition: 0 = top, 1 = bottom
[[ stitchable ]] half4 rimEdgeLight(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float edgePosition,
    float rimWidth,
    float glowWidth,
    float cornerSpread,
    float cornerPower,
    float hotspotWidth,
    float hotspotIntensity,
    float driftSpeed,
    float shimmerAmount,
    float pulseAmount,
    float intensity,
    float sideReach,
    float sideIntensity,
    float falloffSharpness,
    float blurReach,
    float4 lightColor
) {
    float nx = position.x / max(size.x, 1.0);
    float ny = position.y / max(size.y, 1.0);
    
    float edgeDist = edgePosition < 0.5 ? ny : (1.0 - ny);
    float edgeMask = smoothstep(0.22, 0.0, edgeDist);
    
    float edgeCurve = pow(saturate(abs(nx - 0.5) * 2.0), max(cornerPower, 0.01));
    float sideCurve = smoothstep(0.55, 1.0, abs(nx - 0.5) * 2.0);
    float widthBoost = mix(1.0, 1.0 + cornerSpread * 2.4, edgeCurve);
    
    float localRimWidth = max(rimWidth * mix(1.0, 1.0 + cornerSpread * 0.8, edgeCurve), 0.0001);
    float localGlowWidth = max(glowWidth * widthBoost * max(blurReach, 0.001), 0.0001);
    float glowFalloffPower = max(falloffSharpness, 0.05);
    
    float rim = exp(-pow(edgeDist / localRimWidth, 2.0) * 1.4);
    float glow = exp(-pow(edgeDist / localGlowWidth, glowFalloffPower) * 0.8);
    float whiteCore = exp(-pow(edgeDist / max(localRimWidth * 1.8, 0.0001), 2.0) * 1.1);
    
    float hotspotCenter = 0.5
        + 0.34 * sin(time * driftSpeed * 1.15)
        + 0.12 * sin(time * driftSpeed * 0.63 + 1.9);
    float hotspotDistance = abs(nx - hotspotCenter) / max(hotspotWidth, 0.001);
    float hotspot = exp(-pow(hotspotDistance, 2.0) * 2.2);
    
    float secondaryCenter = 0.5
        + 0.40 * sin(-time * driftSpeed * 0.92 + 0.8);
    float secondaryDistance = abs(nx - secondaryCenter) / max(hotspotWidth * 0.7, 0.001);
    float secondaryHotspot = exp(-pow(secondaryDistance, 2.0) * 2.8);
    
    float shimmer = 0.5 + 0.5 * sin(nx * 16.0 - time * driftSpeed * 2.6);
    float edgeSweep = 0.5 + 0.5 * sin(time * driftSpeed * 3.0 + nx * 18.0);
    float cornerSweep = 0.5 + 0.5 * sin(time * driftSpeed * 4.4 + edgeCurve * 20.0 + nx * 10.0);
    float pulse = 1.0 + sin(time * 0.9) * pulseAmount;
    
    float cornerGlow = mix(0.85, 1.0 + cornerSpread * 0.9, edgeCurve);
    float dynamicLight = 1.0
        + hotspot * hotspotIntensity
        + secondaryHotspot * hotspotIntensity * 0.55
        + shimmer * shimmerAmount
        + edgeSweep * sideCurve * 0.55
        + cornerSweep * edgeCurve * 0.7;
    
    float coreAlpha = whiteCore * 1.15 * pulse * intensity;
    float sideMask = smoothstep(max(sideReach, 0.001), 0.0, edgeDist);
    float sideAlpha = sideMask * sideCurve * glow * sideIntensity * (0.65 + edgeSweep * 0.7 + cornerSweep * 0.45);
    float haloAlpha = ((rim * 0.45 + glow * 1.05) * cornerGlow * dynamicLight + sideAlpha) * pulse * intensity;
    float colorAlpha = saturate(lightColor.a);
    coreAlpha *= colorAlpha;
    haloAlpha *= colorAlpha;
    float alpha = saturate(max(coreAlpha, haloAlpha) * edgeMask);
    alpha *= edgeMask;
    
    float3 haloColor = mix(float3(1.0), lightColor.rgb, 0.78);
    float3 haloContribution = haloColor * haloAlpha;
    float3 coreContribution = float3(1.0) * (coreAlpha * 0.82);
    
    // Screen-blend the bright white rim into the colored bloom so the edge
    // feels like a single light source instead of a separate white strip.
    float3 rgbFloat = 1.0 - (1.0 - haloContribution) * (1.0 - coreContribution);
    rgbFloat = min(rgbFloat, float3(1.0));
    half3 rgb = half3(rgbFloat);
    return half4(rgb, half(alpha));
}
