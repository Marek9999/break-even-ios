//
//  SlideToSettleView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2026-01-11.
//

import Foundation
import SwiftUI

struct SlideToSettleView: View {
    var title: String = "Slide to Settle"
    var onUnlock: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isUnlocked = false
    
    // Design Constants
    private let height: CGFloat = 56
    private let knobSize: CGFloat = 48
    private let padding: CGFloat = 4
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxDrag = totalWidth - knobSize - (padding * 2)
            
            ZStack(alignment: .leading) {
                // 1. Background Track
                Capsule()
                    .fill(Color(.secondarySystemGroupedBackground))
                
                // 2. Text Label (Behind the knob)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .opacity(1.0 - (Double(dragOffset) / Double(maxDrag))) // Fade out as you drag
                
                // 3. Draggable Knob
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isUnlocked {
                                    // Limit the drag between 0 and maxDrag
                                    let translation = value.translation.width
                                    dragOffset = min(max(translation, 0), maxDrag)
                                }
                            }
                            .onEnded { value in
                                if dragOffset >= maxDrag * 0.85 {
                                    // Threshold reached - Snap to end and trigger action
                                    withAnimation(.spring()) {
                                        dragOffset = maxDrag
                                        isUnlocked = true
                                    }
                                    // Trigger the action
                                    onUnlock()
                                    
                                    // Reset after a delay (optional)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        withAnimation {
                                            isUnlocked = false
                                            dragOffset = 0
                                        }
                                    }
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
        }
        .frame(height: height)
    }
}



#Preview {
    ZStack {
        // Background to simulate a Sheet or Home screen
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack(spacing: 50) {
            
            // 1. Standard Look
            VStack(alignment: .leading) {
                Text("Default Style")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading)
                
                SlideToSettleView(onUnlock: {
                    print("Slide completed!")
                })
                .padding(.horizontal)
            }
            
            // 2. Custom Title & Interactive State
            InteractivePreview()
        }
    }
}

// Helper to show state changes in Preview
private struct InteractivePreview: View {
    @State private var status = "Pending"
    @State private var boxColor = Color.white
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Interactive Demo: \(status)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading)
                .contentTransition(.numericText())
            
            VStack(spacing: 20) {
                // The Slider
                SlideToSettleView(title: "Slide to Pay $24.50") {
                    // Action triggered on slide complete
                    withAnimation {
                        status = "Paid!"
                        boxColor = Color.green.opacity(0.1)
                    }
                    
                    // Reset for preview fun
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            status = "Pending"
                            boxColor = .white
                        }
                    }
                }
            }
            .padding(20)
            .background(boxColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}
