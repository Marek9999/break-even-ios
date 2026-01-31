//
//  SlideToSettleView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2026-01-11.
//

import Foundation
import SwiftUI

// MARK: - Settle State

enum SettleState: Equatable {
    case idle
    case processing
    case completed
    case failed
}

// MARK: - Slide To Settle View

struct SlideToSettleView: View {
    var title: String = "Slide to Settle"
    @Binding var state: SettleState
    var onSlideComplete: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var shakeOffset: CGFloat = 0
    @State private var lastHapticOffset: CGFloat = 0
    
    // Design Constants
    private let height: CGFloat = 56
    private let knobSize: CGFloat = 48
    private let padding: CGFloat = 4
    
    // MARK: - Haptic Feedback Configuration
    // Adjust these values to tune the haptic experience
    
    /// Progress threshold where haptics start (0.0 to 1.0)
    /// Set to 0.05 to start haptics after 5% progress
    private let hapticStartProgress: Double = 0.05
    
    /// Progress threshold where haptics reach maximum intensity (0.0 to 1.0)
    /// Set to 0.85 to reach max intensity at 85% (where slide completes)
    private let hapticMaxProgress: Double = 0.85
    
    /// Minimum distance (in points) the knob must move to trigger the next haptic
    /// Lower = more frequent haptics, Higher = less frequent
    private let hapticTriggerDistance: CGFloat = 8
    
    // MARK: - Computed Properties
    
    private var currentIcon: String {
        switch state {
        case .idle:
            return "chevron.forward.dotted.chevron.forward"
        case .processing:
            return "progress.indicator"
        case .completed:
            return "checkmark"
        case .failed:
            return "xmark"
        }
    }
    
    private var iconColor: Color {
        switch state {
        case .idle, .processing, .completed:
            return .accent
        case .failed:
            return .appDestructive
        }
    }
    
    private var backgroundTintColor: Color {
        switch state {
        case .idle, .processing, .completed:
            return .accent
        case .failed:
            return .appDestructive
        }
    }
    
    private var displayText: String {
        switch state {
        case .idle:
            return title
        case .processing:
            return "Processing..."
        case .completed:
            return "Settled!"
        case .failed:
            return "Failed"
        }
    }
    
    private var textColor: Color {
        switch state {
        case .idle, .processing, .completed:
            return .white
        case .failed:
            return .appDestructive
        }
    }
    
    private var isDragEnabled: Bool {
        state == .idle
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxDrag = totalWidth - knobSize - (padding * 2)
            let dragProgress = maxDrag > 0 ? Double(dragOffset) / Double(maxDrag) : 0
            
            ZStack(alignment: .leading) {
                // 1. Background Track
                Capsule()
                    .glassEffect(.regular.tint(backgroundTintColor.opacity(0.3 + dragProgress * 0.5)).interactive())
                
                // 2. Center Text
                Text(displayText)
                    .font(.headline)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .opacity(state == .idle ? 0.8 + dragProgress : 1.0)
                    .contentTransition(.interpolate)
                
                // 3. Draggable Knob
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        
                        Image(systemName: currentIcon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(iconColor)
                            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                            .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.8)), isActive: state == .idle)
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous), isActive: state == .processing)
                            
                    }
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: state == .idle ? dragOffset : maxDrag)
                    .offset(x: shakeOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard isDragEnabled else { return }
                                let translation = value.translation.width
                                let newOffset = min(max(translation, 0), maxDrag)
                                
                                // Trigger haptic feedback if moved enough
                                let distanceMoved = abs(newOffset - lastHapticOffset)
                                if distanceMoved >= hapticTriggerDistance {
                                    let progress = maxDrag > 0 ? Double(newOffset) / Double(maxDrag) : 0
                                    triggerProgressHaptic(progress: progress)
                                    lastHapticOffset = newOffset
                                }
                                
                                dragOffset = newOffset
                            }
                            .onEnded { value in
                                guard isDragEnabled else { return }
                                
                                // Reset haptic tracking
                                lastHapticOffset = 0
                                
                                if dragOffset >= maxDrag * 0.85 {
                                    // Threshold reached - Snap to end and trigger action
                                    withAnimation(.spring()) {
                                        dragOffset = maxDrag
                                    }
                                    // Final strong haptic
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
                                    // Trigger the callback
                                    onSlideComplete()
                                } else {
                                    // Snap back
                                    withAnimation(.spring()) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
                .padding(padding)
            }
            .animation(.easeInOut(duration: 0.3), value: state)
        }
        .frame(height: height)
        .onChange(of: state) { oldValue, newValue in
            if newValue == .failed {
                triggerShakeAnimation()
            }
            if newValue == .idle {
                // Reset drag offset when returning to idle
                withAnimation(.spring()) {
                    dragOffset = 0
                }
            }
        }
    }
    
    // MARK: - Shake Animation
    
    private func triggerShakeAnimation() {
        let shakeSequence: [(CGFloat, Double)] = [
            (10, 0.05),
            (-10, 0.05),
            (8, 0.05),
            (-8, 0.05),
            (5, 0.05),
            (-5, 0.05),
            (0, 0.05)
        ]
        
        var delay: Double = 0
        for (offset, duration) in shakeSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: duration)) {
                    shakeOffset = offset
                }
            }
            delay += duration
        }
    }
    
    // MARK: - Haptic Feedback
    
    /// Triggers haptic feedback with intensity based on slide progress
    /// - Parameter progress: Current drag progress from 0.0 to 1.0
    private func triggerProgressHaptic(progress: Double) {
        // Don't trigger if below start threshold
        guard progress >= hapticStartProgress else { return }
        
        // Calculate intensity: maps progress from [hapticStartProgress...hapticMaxProgress] to [0.3...1.0]
        // Minimum intensity is 0.3, maximum is 1.0
        let normalizedProgress = (progress - hapticStartProgress) / (hapticMaxProgress - hapticStartProgress)
        let clampedProgress = min(max(normalizedProgress, 0), 1)
        
        // Intensity range: 0.3 (light) to 1.0 (heavy)
        // Adjust these values to change the feel:
        let minIntensity: CGFloat = 0.3  // Starting intensity
        let maxIntensity: CGFloat = 1.0  // Maximum intensity
        let intensity = minIntensity + (maxIntensity - minIntensity) * clampedProgress
        
        // Use medium style for good balance, intensity controls the strength
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: intensity)
    }
}



#Preview {
    ScrollView {
        VStack(spacing: 30) {
            // Interactive demo showing all states
            InteractivePreview()
            
            // Static state previews
            StaticStatePreview()
        }
        .padding(.vertical, 20)
    }
    .safeAreaBar(edge: .bottom) {
        BottomBarPreview()
    }
}

// MARK: - Preview Helpers

private struct InteractivePreview: View {
    @State private var settleState: SettleState = .idle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interactive Demo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading)
            
            Text("State: \(String(describing: settleState))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading)
            
            SlideToSettleView(
                title: "Slide to Pay $24.50",
                state: $settleState,
                onSlideComplete: {
                    // Simulate processing
                    settleState = .processing
                    
                    // Simulate API call
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        // Randomly succeed or fail for demo
                        withAnimation {
                            settleState = Bool.random() ? .completed : .failed
                        }
                        
                        // Reset after showing result
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                settleState = .idle
                            }
                        }
                    }
                }
            )
            .padding(.horizontal)
            
            // Manual state buttons for testing
            HStack(spacing: 8) {
                ForEach([SettleState.idle, .processing, .completed, .failed], id: \.self) { state in
                    Button(String(describing: state).capitalized) {
                        withAnimation {
                            settleState = state
                        }
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct StaticStatePreview: View {
    @State private var idleState: SettleState = .idle
    @State private var processingState: SettleState = .processing
    @State private var completedState: SettleState = .completed
    @State private var failedState: SettleState = .failed
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Static States")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading)
            
            VStack(spacing: 12) {
                SlideToSettleView(title: "Slide to Settle", state: $idleState, onSlideComplete: {})
                SlideToSettleView(title: "Slide to Settle", state: $processingState, onSlideComplete: {})
                SlideToSettleView(title: "Slide to Settle", state: $completedState, onSlideComplete: {})
                SlideToSettleView(title: "Slide to Settle", state: $failedState, onSlideComplete: {})
            }
            .padding(.horizontal)
        }
    }
}

private struct BottomBarPreview: View {
    @State private var settleState: SettleState = .idle
    
    var body: some View {
        SlideToSettleView(
            state: $settleState,
            onSlideComplete: {
                settleState = .processing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        settleState = .completed
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            settleState = .idle
                        }
                    }
                }
            }
        )
        .padding()
    }
}

