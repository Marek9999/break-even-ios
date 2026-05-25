#include <metal_stdlib>
using namespace metal;

/// Draws a white anti-aliased curve on a black background.
/// The line is flat at y = 0.5 across the centre of the screen and rises
/// exponentially toward the top at both the left and right edges.
/// Near the screen edges the line "melts" — spreading vertically so the
/// top boundary curves upward and the bottom boundary curves downward.
///
/// Parameters (after the two SwiftUI-provided ones):
///   size          – view dimensions in points
///   lineWidth     – thickness of the line in normalised units (0.003 – 0.02)
///   edgeHeight    – how far up the curve rises at the screen edges (0 – 0.4)
///   edgeSharpness – steepness of the exponential ramp (2 – 20); higher = flatter centre
///   meltTop       – how much the top edge spreads upward at the edges (0 – 0.25)
///   meltBottom    – how much the bottom edge spreads downward at the edges (0 – 0.25)
///   meltStartTop  – where the top melt zone begins (0 = centre, 1 = edge)
///   meltStartBot  – where the bottom melt zone begins (0 = centre, 1 = edge)
///   progress      – 0 = default (curves up), 1 = flipped (curves down, melts swapped)
///   baselineY     – vertical centre of the line in normalised coords (0 = top, 1 = bottom)
///   blurCenter    – blur radius at the horizontal centre (normalised, 0 = sharp)
///   blurEdge      – blur radius at the screen edges (normalised)
///   blurCurve     – power exponent controlling the transition (< 1 = early blur, > 1 = late)
///   motionBlur    – directional trail length behind the line (normalised, 0 = none)
///   travelTop     – top endpoint of the travel range
///   travelBottom  – bottom endpoint of the travel range
///   chromaAmount  – max chromatic aberration offset (normalised, 0 = none)
///   lineColor      – RGB tint colour for the line
///   opacityCenter  – opacity at the vertical centre of the line (0–1)
///   opacityEdge    – opacity at the top/bottom boundary of the line (0–1)
[[ stitchable ]] half4 edgeCurve(
    float2 position,
    half4  currentColor,
    float2 size,
    float  lineWidth,
    float  edgeHeight,
    float  edgeSharpness,
    float  meltTop,
    float  meltBottom,
    float  meltStartTop,
    float  meltStartBot,
    float  progress,
    float  baselineY,
    float  blurCenter,
    float  blurEdge,
    float  blurCurve,
    float  motionBlur,
    float  travelTop,
    float  travelBottom,
    float  chromaAmount,
    float4 lineColor,
    float  opacityCenter,
    float  opacityEdge
) {
    float nx = position.x / size.x;
    float ny = position.y / size.y;

    float fromCentre = abs(nx - 0.5) * 2.0;

    float threshold = 1.0 - 1.0 / (1.0 + edgeSharpness * 0.1);
    float edgeDist  = max(fromCentre - threshold, 0.0) / max(1.0 - threshold, 0.001);

    float rise = edgeHeight * (exp(edgeSharpness * edgeDist) - 1.0)
                            / max(exp(edgeSharpness) - 1.0, 0.001);

    float hw = lineWidth * 0.5;

    float mzT = smoothstep(meltStartTop, 1.0, fromCentre);
    float mcT = mzT * mzT * mzT;
    float mzB = smoothstep(meltStartBot, 1.0, fromCentre);
    float mcB = mzB * mzB * mzB;

    // State A (progress=0): curves up at edges, bottom anchored to baseline
    float topA    = (baselineY - rise) - hw - meltTop    * mcT;
    float bottomA =  baselineY         + hw + meltBottom * mcB;

    // State B (progress=1): curves down at edges, top anchored, melts swapped
    float topB    =  baselineY         - hw - meltBottom * mcB;
    float bottomB = (baselineY + rise) + hw + meltTop    * mcT;

    float topEdge    = mix(topA,    topB,    progress);
    float bottomEdge = mix(bottomA, bottomB, progress);

    float aa = 1.0 / size.y;

    // Progressive blur: sharp in the centre, soft at the edges
    float blurT   = pow(fromCentre, max(blurCurve, 0.01));
    float baseBlr = max(mix(blurCenter, blurEdge, blurT), aa);

    // Speed factor: full in the middle of travel, fades near endpoints
    float travelRange = max(travelBottom - travelTop, 0.001);
    float distFromNearest = min(baselineY - travelTop, travelBottom - baselineY);
    float speedFactor = clamp(distFromNearest / (travelRange * 0.3), 0.0f, 1.0f);
    float effectiveMotion = motionBlur * speedFactor;

    // Directional motion trail: extends behind the line.
    // progress=0 → moving down → trail above (top edge softened)
    // progress=1 → moving up   → trail below (bottom edge softened)
    float p = clamp(progress, 0.0f, 1.0f);
    float trailUp   = effectiveMotion * (1.0 - p);
    float trailDown = effectiveMotion * p;

    float blrTop = max(baseBlr + trailUp, aa);
    float blrBot = max(baseBlr + trailDown, aa);

    // Chromatic aberration: R and B channels offset vertically,
    // stronger at horizontal edges and in the motion trail direction.
    float caEdge = fromCentre * fromCentre;          // quadratic horizontal ramp
    float caDir  = 1.0 - 2.0 * p;                    // +1 moving down, −1 moving up
    float caShift = chromaAmount * caEdge * speedFactor;

    // R shifts in trail direction, B opposite, G stays centred
    float nyR = ny + caShift * caDir;
    float nyB = ny - caShift * caDir;

    // Per-channel alpha
    float alphaR = 1.0 - max(smoothstep(0.0, blrTop, topEdge - nyR),
                              smoothstep(0.0, blrBot, nyR - bottomEdge));

    float alphaG = 1.0 - max(smoothstep(0.0, blrTop, topEdge - ny),
                              smoothstep(0.0, blrBot, ny - bottomEdge));

    float alphaB = 1.0 - max(smoothstep(0.0, blrTop, topEdge - nyB),
                              smoothstep(0.0, blrBot, nyB - bottomEdge));

    // Within-line opacity gradient: full at core, fades toward top/bottom.
    float lineMid       = (topEdge + bottomEdge) * 0.5;
    float halfThickness = max((bottomEdge - topEdge) * 0.5, 0.001);
    float withinLine    = clamp(abs(ny - lineMid) / halfThickness, 0.0, 1.0);
    float opacityMult   = mix(opacityCenter, opacityEdge, withinLine);

    half4 col = half4(lineColor);
    half  om  = half(opacityMult);
    half r = half(alphaR) * col.r * om;
    half g = half(alphaG) * col.g * om;
    half b = half(alphaB) * col.b * om;
    half a = max(r, max(g, b));
    return half4(r, g, b, a);
}


/// Distortion shader that stretches background pixels on the trailing
/// side of the moving line, creating a rubber-sheet smear.
/// Pixels closer to the line are displaced more; pixels beyond
/// stretchFalloff are untouched.  The effect fades when the line
/// decelerates near the travel endpoints.
///
///   baselineY     – current normalised Y of the line
///   progress      – flip state (0 = moving down, 1 = moving up)
///   stretchAmount – peak displacement in normalised units
///   stretchFalloff– how far from the line the stretch reaches (normalised)
///   travelTop     – top travel bound (normalised)
///   travelBottom  – bottom travel bound (normalised)
[[ stitchable ]] float2 bgStretch(
    float2 position,
    float2 size,
    float  baselineY,
    float  progress,
    float  stretchAmount,
    float  stretchFalloff,
    float  travelTop,
    float  travelBottom
) {
    float ny = position.y / size.y;
    float linePos = baselineY;

    // Speed factor – reduce stretch near travel bounds
    float travelRange = max(travelBottom - travelTop, 0.001);
    float distFromNearest = min(abs(baselineY - travelTop),
                                abs(baselineY - travelBottom));
    float speedFactor = clamp(distFromNearest / (travelRange * 0.3), 0.0, 1.0);

    float p = clamp(progress, 0.0, 1.0);
    float falloff = max(stretchFalloff, 0.001);

    float2 result = position;

    // Soft ramp-in zone: displacement is zero right at the line, peaks
    // a short distance away, then tapers via the quadratic falloff.
    // This eliminates the hard seam at the line boundary.
    float softZone = falloff * 0.25;

    // Moving down (p ≈ 0): stretch pixels above the line downward.
    float downWeight = 1.0 - p;
    if (ny < linePos && downWeight > 0.001) {
        float dist = linePos - ny;
        float t = clamp(dist / falloff, 0.0, 1.0);
        float rampIn  = smoothstep(0.0, softZone, dist);
        float rampOut = (1.0 - t) * (1.0 - t);
        float offset = stretchAmount * rampIn * rampOut * speedFactor * downWeight;
        result.y = position.y - offset * size.y;
    }

    // Moving up (p ≈ 1): stretch pixels below the line upward.
    float upWeight = p;
    if (ny > linePos && upWeight > 0.001) {
        float dist = ny - linePos;
        float t = clamp(dist / falloff, 0.0, 1.0);
        float rampIn  = smoothstep(0.0, softZone, dist);
        float rampOut = (1.0 - t) * (1.0 - t);
        float offset = stretchAmount * rampIn * rampOut * speedFactor * upWeight;
        result.y = position.y + offset * size.y;
    }

    return result;
}
