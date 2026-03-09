import SwiftUI

#if DEBUG
/// Debug view for tuning the scan-beam shader parameters in real time.
/// Accessible from Profile -> Developer section.
struct ShaderTestView: View {
    @State private var beamWidth: Double = 0.05
    @State private var intensity: Double = 0.8
    @State private var speed: Double = 1.0
    @State private var trailLength: Double = 0.06
    @State private var curvature: Double = 0.04
    @State private var isActive = true

    private var cycleDuration: Double { 2.5 / speed }

    var body: some View {
        VStack(spacing: 0) {
            shaderPreview
            controlPanel
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("Scan Beam Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Preview Area

    private var shaderPreview: some View {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.78, blue: 1.0),
                Color(red: 0.10, green: 0.20, blue: 0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .scanBeamOverlay(
            isActive: isActive,
            beamWidth: beamWidth,
            intensity: intensity,
            cycleDuration: cycleDuration,
            trailLength: trailLength,
            curvature: curvature
        )
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Controls")
                        .font(.headline)

                    Spacer()

                    Button(isActive ? "Pause" : "Play") {
                        isActive.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                parameterSlider(
                    label: "Beam Width",
                    value: $beamWidth,
                    range: 0.01...0.15,
                    format: "%.3f"
                )

                parameterSlider(
                    label: "Intensity",
                    value: $intensity,
                    range: 0.1...1.5,
                    format: "%.2f"
                )

                parameterSlider(
                    label: "Speed",
                    value: $speed,
                    range: 0.3...3.0,
                    format: "%.1fx"
                )

                parameterSlider(
                    label: "Trail Length",
                    value: $trailLength,
                    range: 0.0...0.15,
                    format: "%.3f"
                )

                parameterSlider(
                    label: "Curvature",
                    value: $curvature,
                    range: 0.0...0.15,
                    format: "%.3f"
                )

                Button("Reset Defaults") {
                    withAnimation {
                        beamWidth = 0.05
                        intensity = 0.8
                        speed = 1.0
                        trailLength = 0.06
                        curvature = 0.04
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(maxHeight: 320)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

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

#Preview {
    NavigationStack {
        ShaderTestView()
    }
}
#endif
