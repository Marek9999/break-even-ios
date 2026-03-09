import SwiftUI
import PhotosUI
import CoreHaptics

#if DEBUG
/// Debug view for visualising and tuning the exponential edge-curve shape.
/// A white line on a black background -- flat in the centre, rising at the edges.
struct EdgeCurveLabView: View {
    @State private var lineWidth: Double = 0.0231
    @State private var edgeHeight: Double = 0.086
    @State private var edgeSharpness: Double = 6.4
    @State private var meltTop: Double = 0.035
    @State private var meltBottom: Double = 0.022
    @State private var meltStartTop: Double = 0.63
    @State private var meltStartBottom: Double = 0.63
    @State private var blurCenter: Double = 0.0477
    @State private var blurEdge: Double = 0.1297
    @State private var blurCurve: Double = 2.09
    @State private var motionBlur: Double = 0.2215
    @State private var chromaAmount: Double = 0.0323

    // Animation parameters
    @State private var travelDuration: Double = 2.34
    @State private var cp1x: Double = 0.38
    @State private var cp1y: Double = 0.10
    @State private var cp2x: Double = 0.07
    @State private var cp2y: Double = 1.0
    @State private var flipDuration: Double = 0.82
    @State private var flipBounce: Double = 0.80

    @State private var stretchAmount: Double = 0.0994
    @State private var stretchFalloff: Double = 0.2794

    @State private var lineColor: Color = .white
    @State private var opacityCenter: Double = 0.9759
    @State private var opacityEdge: Double = 0.9233
    @State private var selectedBlendMode: BlendModeOption = .softLight
    @State private var backgroundImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var hapticEnabled: Bool = true
    @State private var hapticIntensity: Double = 0.858
    @State private var hapticSharpness: Double = 0.6548
    @State private var haptics = HapticState()

    @State private var copiedParams = false
    @State private var showControls = true
    @State private var progress: Double = 0.0
    @State private var lineY: Double = 0.12
    @State private var animating = true
    @State private var cycleTask: Task<Void, Never>?

    private let topY = 0.12
    private let bottomY = 0.88

    var body: some View {
        curvePreview
            .onAppear {
                startCycle()
            }
            .onDisappear {
                cycleTask?.cancel()
                cycleTask = nil
            }
            .ignoresSafeArea()
            .navigationTitle("Edge Curve Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showControls = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showControls) {
                controlPanel
                    .presentationDetents([.medium])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.regularMaterial)
            }
    }

    // MARK: - Preview

    private var defaultGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.10, blue: 0.35),
                Color(red: 0.10, green: 0.25, blue: 0.70),
                Color(red: 0.20, green: 0.45, blue: 0.95),
                Color(red: 0.10, green: 0.25, blue: 0.70),
                Color(red: 0.05, green: 0.10, blue: 0.35)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var curvePreview: some View {
        ZStack {
            Group {
                if let backgroundImage {
                    GeometryReader { geo in
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                } else {
                    defaultGradient
                }
            }
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
                .blendMode(selectedBlendMode.mode)
        }
    }

    // MARK: - Controls

    private var controlPanel: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Play / Pause
                    Button {
                        animating.toggle()
                        if animating {
                            startCycle()
                        } else {
                            cycleTask?.cancel()
                            cycleTask = nil
                        }
                    } label: {
                        Label(
                            animating ? "Pause" : "Play",
                            systemImage: animating ? "pause.fill" : "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    sectionHeader("Background")
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label("Choose Image", systemImage: "photo.on.rectangle")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            backgroundImage = nil
                            photoPickerItem = nil
                        } label: {
                            Label("Gradient", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(backgroundImage == nil)
                        .opacity(backgroundImage == nil ? 0.4 : 1.0)
                    }
                    .onChange(of: photoPickerItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                backgroundImage = uiImage
                            }
                        }
                    }
                    parameterSlider(label: "BG Stretch", value: $stretchAmount, range: 0.0...0.3, format: "%.3f")
                    parameterSlider(label: "Stretch Reach", value: $stretchFalloff, range: 0.05...0.6, format: "%.2f")

                    Divider()
                    sectionHeader("Shape")
                    parameterSlider(label: "Line Width", value: $lineWidth, range: 0.003...0.2, format: "%.4f")
                    parameterSlider(label: "Edge Height", value: $edgeHeight, range: 0.0...0.4, format: "%.3f")
                    parameterSlider(label: "Edge Sharpness", value: $edgeSharpness, range: 2.0...20.0, format: "%.1f")

                    Divider()
                    sectionHeader("Melt")
                    parameterSlider(label: "Melt Top", value: $meltTop, range: 0.0...0.25, format: "%.3f")
                    parameterSlider(label: "Melt Bottom", value: $meltBottom, range: 0.0...0.85, format: "%.3f")
                    parameterSlider(label: "Melt Start Top", value: $meltStartTop, range: 0.5...0.95, format: "%.2f")
                    parameterSlider(label: "Melt Start Bottom", value: $meltStartBottom, range: 0.5...0.95, format: "%.2f")

                    Divider()
                    sectionHeader("Blur")
                    parameterSlider(label: "Blur Center", value: $blurCenter, range: 0.0...0.05, format: "%.4f")
                    parameterSlider(label: "Blur Edge", value: $blurEdge, range: 0.0...0.15, format: "%.4f")
                    parameterSlider(label: "Blur Curve", value: $blurCurve, range: 0.2...5.0, format: "%.2f")
                    parameterSlider(label: "Motion Blur", value: $motionBlur, range: 0.0...0.25, format: "%.3f")
                    parameterSlider(label: "Chroma", value: $chromaAmount, range: 0.0...0.06, format: "%.4f")

                    Divider()
                    sectionHeader("Line Color")
                    HStack {
                        ColorPicker("Color", selection: $lineColor, supportsOpacity: false)
                        Spacer()
                        Button("White") {
                            lineColor = .white
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    parameterSlider(label: "Opacity Center", value: $opacityCenter, range: 0.0...1.0, format: "%.2f")
                    parameterSlider(label: "Opacity Edge", value: $opacityEdge, range: 0.0...1.0, format: "%.2f")

                    Divider()
                    sectionHeader("Blend Mode")
                    blendModePicker

                    Divider()
                    sectionHeader("Animation — Travel")

                    bezierPreview
                        .padding(.bottom, 4)

                    parameterSlider(label: "Duration", value: $travelDuration, range: 0.5...6.0, format: "%.2f s")
                    parameterSlider(label: "CP1 X", value: $cp1x, range: 0.0...1.0, format: "%.2f")
                    parameterSlider(label: "CP1 Y", value: $cp1y, range: -0.5...1.5, format: "%.2f")
                    parameterSlider(label: "CP2 X", value: $cp2x, range: 0.0...1.0, format: "%.2f")
                    parameterSlider(label: "CP2 Y", value: $cp2y, range: -0.5...1.5, format: "%.2f")

                    Divider()
                    sectionHeader("Animation — Flip")
                    parameterSlider(label: "Flip Duration", value: $flipDuration, range: 0.2...2.0, format: "%.2f s")
                    parameterSlider(label: "Flip Bounce", value: $flipBounce, range: 0.0...0.8, format: "%.2f")

                    Divider()
                    sectionHeader("Haptics")
                    Toggle("Haptic Feedback", isOn: $hapticEnabled)
                        .font(.subheadline)
                    parameterSlider(label: "Intensity", value: $hapticIntensity, range: 0.0...1.0, format: "%.2f")
                    parameterSlider(label: "Sharpness", value: $hapticSharpness, range: 0.0...1.0, format: "%.2f")
                    HStack(spacing: 12) {
                        Button {
                            testHaptic()
                        } label: {
                            Label("CoreHaptics", systemImage: "iphone.radiowaves.left.and.right")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            let g = UIImpactFeedbackGenerator(style: .heavy)
                            g.prepare()
                            g.impactOccurred()
                        } label: {
                            Label("UIKit Test", systemImage: "hand.tap")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Reset All") {
                        withAnimation {
                            lineWidth = 0.0231; edgeHeight = 0.086; edgeSharpness = 6.4
                            meltTop = 0.035; meltBottom = 0.022
                            meltStartTop = 0.63; meltStartBottom = 0.63
                            blurCenter = 0.0477; blurEdge = 0.1297; blurCurve = 2.09
                            motionBlur = 0.2215; chromaAmount = 0.0323
                            stretchAmount = 0.0994; stretchFalloff = 0.2794
                            lineColor = .white; opacityCenter = 0.9759; opacityEdge = 0.9233
                            selectedBlendMode = .softLight
                            backgroundImage = nil; photoPickerItem = nil
                            travelDuration = 2.34
                            cp1x = 0.38; cp1y = 0.10; cp2x = 0.07; cp2y = 1.0
                            flipDuration = 0.82; flipBounce = 0.80
                            hapticEnabled = true; hapticIntensity = 0.858; hapticSharpness = 0.6548
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        let resolved = lineColor.resolve(in: EnvironmentValues())
                        let text = """
                        lineWidth = \(lineWidth)
                        edgeHeight = \(edgeHeight)
                        edgeSharpness = \(edgeSharpness)
                        meltTop = \(meltTop)
                        meltBottom = \(meltBottom)
                        meltStartTop = \(meltStartTop)
                        meltStartBottom = \(meltStartBottom)
                        blurCenter = \(blurCenter)
                        blurEdge = \(blurEdge)
                        blurCurve = \(blurCurve)
                        motionBlur = \(motionBlur)
                        chromaAmount = \(chromaAmount)
                        stretchAmount = \(stretchAmount)
                        stretchFalloff = \(stretchFalloff)
                        lineColor = Color(red: \(resolved.red), green: \(resolved.green), blue: \(resolved.blue))
                        opacityCenter = \(opacityCenter)
                        opacityEdge = \(opacityEdge)
                        selectedBlendMode = .\(selectedBlendMode.rawValue)
                        travelDuration = \(travelDuration)
                        cp1x = \(cp1x)
                        cp1y = \(cp1y)
                        cp2x = \(cp2x)
                        cp2y = \(cp2y)
                        flipDuration = \(flipDuration)
                        flipBounce = \(flipBounce)
                        hapticEnabled = \(hapticEnabled)
                        hapticIntensity = \(hapticIntensity)
                        hapticSharpness = \(hapticSharpness)
                        """
                        UIPasteboard.general.string = text
                        copiedParams = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedParams = false
                        }
                    } label: {
                        Label(
                            copiedParams ? "Copied!" : "Copy Parameters",
                            systemImage: copiedParams ? "checkmark" : "doc.on.doc"
                        )
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copiedParams ? .green : .secondary)
                }
                .padding()
            }
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Bezier Preview

    private var bezierPreview: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let inset: CGFloat = 16

            // Grid
            var grid = Path()
            grid.move(to: CGPoint(x: inset, y: inset))
            grid.addLine(to: CGPoint(x: inset, y: h - inset))
            grid.addLine(to: CGPoint(x: w - inset, y: h - inset))
            context.stroke(grid, with: .color(.white.opacity(0.15)), lineWidth: 1)

            // Diagonal reference
            var diag = Path()
            diag.move(to: CGPoint(x: inset, y: h - inset))
            diag.addLine(to: CGPoint(x: w - inset, y: inset))
            context.stroke(diag, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            let cw = w - inset * 2
            let ch = h - inset * 2

            func pt(_ tx: Double, _ ty: Double) -> CGPoint {
                CGPoint(x: inset + tx * cw, y: (h - inset) - ty * ch)
            }

            // Control-point handles
            let p0 = pt(0, 0)
            let c1 = pt(cp1x, cp1y)
            let c2 = pt(cp2x, cp2y)
            let p1 = pt(1, 1)

            var handles = Path()
            handles.move(to: p0); handles.addLine(to: c1)
            handles.move(to: p1); handles.addLine(to: c2)
            context.stroke(handles, with: .color(.white.opacity(0.25)), lineWidth: 1)

            // Control points
            for cp in [c1, c2] {
                context.fill(
                    Path(ellipseIn: CGRect(x: cp.x - 4, y: cp.y - 4, width: 8, height: 8)),
                    with: .color(.white.opacity(0.6))
                )
            }

            // Bezier curve
            var curve = Path()
            curve.move(to: p0)
            curve.addCurve(to: p1, control1: c1, control2: c2)
            context.stroke(curve, with: .color(.white), lineWidth: 2)
        }
        .frame(height: 120)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 8))
    }

    // MARK: - Animation Cycle

    private var travelAnimation: Animation {
        .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: travelDuration)
    }

    private var flipAnimation: Animation {
        .spring(duration: flipDuration, bounce: flipBounce)
    }

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

    private func testHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            try engine.start()

            let sharp = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [sharp], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)

            haptics.testEngine = engine
            Task {
                try? await Task.sleep(for: .seconds(1))
                haptics.testEngine = nil
            }
        } catch {}
    }

    /// Fires transient haptic thuds at velocity-based intervals.
    /// Faster movement = rapid-fire thuds; slower movement = spaced-out thuds.
    private func waitWithHaptics(duration: Double) async {
        let start = CACurrentMediaTime()
        var lastThudTime: Double = -1

        let minInterval = 0.035
        let maxInterval = 0.45

        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - start
            if elapsed >= duration { break }

            if hapticEnabled {
                let t = elapsed / duration
                let velocity = abs(bezierVelocity(at: t))
                let normalizedV = min(velocity / 3.5, 1.0)
                let interval = maxInterval - (maxInterval - minInterval) * pow(normalizedV, 0.6)
                let intensity = Float(min(velocity * hapticIntensity, 1.0))

                if elapsed - lastThudTime >= interval && intensity > 0.02 {
                    fireTransientHaptic(intensity: intensity, sharpness: Float(hapticSharpness))
                    lastThudTime = elapsed
                }
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

    /// Evaluate cubic Bezier B(u) with endpoints 0, 1
    private func bezierEval(_ u: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - u
        return 3 * mt * mt * u * p1 + 3 * mt * u * u * p2 + u * u * u
    }

    /// Derivative dB/du
    private func bezierDeriv(_ u: Double, p1: Double, p2: Double) -> Double {
        let mt = 1 - u
        return 3 * mt * mt * p1 + 6 * mt * u * (p2 - p1) + 3 * u * u * (1 - p2)
    }

    /// Newton's method: find u where Bx(u) = t
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

    // MARK: - Blend Mode Picker

    private var blendModePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(BlendModeOption.allCases) { option in
                Button {
                    selectedBlendMode = option
                } label: {
                    Text(option.label)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedBlendMode == option
                                ? AnyShapeStyle(.white.opacity(0.2))
                                : AnyShapeStyle(.white.opacity(0.05)),
                            in: .rect(cornerRadius: 8)
                        )
                        .foregroundStyle(selectedBlendMode == option ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parameterSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Haptic State

final class HapticState {
    var engine: CHHapticEngine?
    var testEngine: CHHapticEngine?
}

// MARK: - Blend Mode Options

enum BlendModeOption: String, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay
    case darken, lighten, colorDodge, colorBurn
    case softLight, hardLight, difference, exclusion
    case hue, saturation, color, luminosity
    case plusLighter, plusDarker, destinationOver

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .darken: "Darken"
        case .lighten: "Lighten"
        case .colorDodge: "Color Dodge"
        case .colorBurn: "Color Burn"
        case .softLight: "Soft Light"
        case .hardLight: "Hard Light"
        case .difference: "Difference"
        case .exclusion: "Exclusion"
        case .hue: "Hue"
        case .saturation: "Saturation"
        case .color: "Color"
        case .luminosity: "Luminosity"
        case .plusLighter: "Plus Lighter"
        case .plusDarker: "Plus Darker"
        case .destinationOver: "Dest Over"
        }
    }

    var mode: BlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .exclusion: .exclusion
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        case .plusLighter: .plusLighter
        case .plusDarker: .plusDarker
        case .destinationOver: .destinationOver
        }
    }
}

#Preview {
    NavigationStack {
        EdgeCurveLabView()
    }
}
#endif
