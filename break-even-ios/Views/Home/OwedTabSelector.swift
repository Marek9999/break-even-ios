//
//  OwedTabSelector.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-08.
//
//


import SwiftUI

class Haptics {
    static let shared = Haptics()
    
    // Selection for taps/switches, Impact for "hitting the wall"
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    
    func selectionChanged() {
        selection.prepare()
        selection.selectionChanged()
    }
    
    func playImpact() {
        impact.prepare()
        impact.impactOccurred()
    }
}

enum OwedTab: String, CaseIterable {
    case owedToYou = "Owed to you"
    case youOwe = "You owe"
}

struct OwedTabSelector: View {
    // 1. External Source of Truth
    @Binding var selectedTab: OwedTab
    
    // 2. Data to Display
    let owedToYouAmount: Double
    let youOweAmount: Double
    
    // 3. Internal Animation State
    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    
    @State private var edgeLock: Int = 0 // 0 = none, -1 = left hit, 1 = right hit
    private let hapticDeadZone: CGFloat = 10 // Pixels to move before re-enabling haptic
    
    // 4. New State to track the touch interaction
    @State private var isDragging: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let paddingAmount: CGFloat = 6
            // Calculate width of one tab based on available space minus padding
            let segmentWidth = (totalWidth - (paddingAmount * 2)) / 2
            
            // 4. Define the geometry of the moving shape ONCE
            // We use this for both the visible glass and the mask

            

            
            ZStack(alignment: .leading) {
                
                // MARK: - Layer 1: Inactive Content (Gray)
                // This is the "Background" text that is always visible
                contentLayer(isSelected: false)
                    .foregroundStyle(.text.opacity(0.4))
                
                // MARK: - Layer 2: The Visual Glass Effect
                VStack {
                    
                }
                    .frame(width: segmentWidth, height: geo.size.height)
                    .glassEffect(.regular, in: ConcentricRectangle(
                        topLeadingCorner: .concentric(minimum: 8),
                        topTrailingCorner: .concentric(minimum: 8),
                        bottomLeadingCorner: .concentric(minimum: 8),
                        bottomTrailingCorner: .concentric(minimum: 8)
                    ))
                    .scaleEffect(isDragging ? 1.05 : 1.0 ) //Scales up to 5%
                    .offset(x: calculateOffset(segmentWidth: segmentWidth))
                
                // MARK: - Layer 3: Active Content (Colored)
                // This is the "Foreground" text that gets revealed by the mask
                contentLayer(isSelected: true)
                    .mask(
                        // The mask is the exact same shape/position as the glass
                        ConcentricRectangle(
                                topLeadingCorner: .concentric(minimum: 8),
                                topTrailingCorner: .concentric(minimum: 8),
                                bottomLeadingCorner: .concentric(minimum: 8),
                                bottomTrailingCorner: .concentric(minimum: 8)
                            )
                            .blur(radius: 5)
                            .frame(width: segmentWidth - 8, height: geo.size.height - (paddingAmount * 2))
                            .scaleEffect(isDragging ? 1.05 : 1.0 ) //Scales up to 5%
                            .offset(x: calculateOffset(segmentWidth: segmentWidth) - segmentWidth/2)
                    )
            }
            // MARK: Container Styling
            .padding(paddingAmount)
            .background(Color.text.opacity(0.03))
            .containerShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            
            // MARK: Gestures
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let segmentWidth = (geo.size.width - (paddingAmount * 2)) / 2
                        let wasAlreadyDragging = isDragging
                        
                        // Play haptic on drag start
                        if !wasAlreadyDragging {
                            Haptics.shared.selectionChanged()
                        }
                        
                        // 1. Scales up IMMEDIATELY on touch down
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
                            isDragging = true
                            dragOffset = value.translation.width
                        }
                        
                        // Edge haptic logic
                        let proposedOffset = getProposedOffset(segmentWidth: segmentWidth)
                        
                        // Check if crossing into left edge
                        if proposedOffset <= 0 && edgeLock != -1 {
                            Haptics.shared.playImpact()
                            edgeLock = -1
                        }
                        // Check if crossing into right edge
                        else if proposedOffset >= segmentWidth && edgeLock != 1 {
                            Haptics.shared.playImpact()
                            edgeLock = 1
                        }
                        // Unlock when moved away from edge
                        else if edgeLock == -1 && proposedOffset > hapticDeadZone {
                            edgeLock = 0
                        }
                        else if edgeLock == 1 && proposedOffset < (segmentWidth - hapticDeadZone) {
                            edgeLock = 0
                        }
                    }
                    .onEnded { value in
                        // 2. We only handle SWIPES here.
                        // Taps are handled by your existing .onTapGesture on the text.
                        let translation = value.translation.width
                        let velocity = value.predictedEndTranslation.width
                        let threshold = segmentWidth / 2
                        
                        var newIndex = selectedIndex
                        
                        // Only switch tab if the user actually DRAGGED far enough
                        if (translation > threshold || velocity > threshold) && selectedIndex == 0 {
                            newIndex = 1
                        } else if (translation < -threshold || velocity < -threshold) && selectedIndex == 1 {
                            newIndex = 0
                        }
                        
                        // 3. Reset the scale and snap to position
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            isDragging = false
                            edgeLock = 0
                            moveSelection(to: newIndex)
                        }
                    }
            )
        }
        .frame(height: 64)
        // MARK: - State Sync
        // Ensure that if the parent view changes the Binding, the animation updates
        .onAppear {
            syncStateWithBinding()
        }
        .onChange(of: selectedTab) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                syncStateWithBinding()
            }
        }
    }
    
    // MARK: - Content Builder (DRY Pattern)
    // This defines the structure of the text/icons once, preventing code duplication
    @ViewBuilder
    func contentLayer(isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            // -- Left Tab: Owed To You --
            HStack {
                VStack(alignment: .leading) {
                    Text(OwedTab.owedToYou.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.text.opacity(0.6))
                    
                    // Display Real Data
                    Text(owedToYouAmount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "arrow.down.left")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isSelected ? .accent : .accent.opacity(0.5))
                    .background(.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { moveSelection(to: 0, playHaptic: false) }
            
            
            // -- Right Tab: You Owe --
            HStack {
                VStack(alignment: .leading) {
                    Text(OwedTab.youOwe.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.text.opacity(0.6))
                    
                    // Display Real Data
                    Text(youOweAmount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isSelected ? .destructive : .destructive.opacity(0.5))
                    .background(.destructive.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { moveSelection(to: 1, playHaptic: false) }
        }
    }
    
    // MARK: - Logic Helpers
    
    private func syncStateWithBinding() {
        selectedIndex = selectedTab == .owedToYou ? 0 : 1
    }

    private func calculateOffset(segmentWidth: CGFloat) -> CGFloat {
        let baseOffset = CGFloat(selectedIndex) * segmentWidth
        let proposedOffset = baseOffset + dragOffset
        return min(max(proposedOffset, 0), segmentWidth)
    }
    
    private func getProposedOffset(segmentWidth: CGFloat) -> CGFloat {
        return CGFloat(selectedIndex) * segmentWidth + dragOffset
    }
    
    private func moveSelection(to index: Int, playHaptic: Bool = true) {
        if playHaptic && selectedIndex != index {
            Haptics.shared.selectionChanged()
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            selectedIndex = index
            dragOffset = 0
            // Update the external binding
            selectedTab = index == 0 ? .owedToYou : .youOwe
        }
    }
}

// MARK: - Preview Logic
private struct PreviewWrapper: View {
    @State private var tab: OwedTab = .owedToYou
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 40) {
                // Test the Component
                OwedTabSelector(
                    selectedTab: $tab,
                    owedToYouAmount: 1250.00,
                    youOweAmount: 42.50
                )
                
                // Verify Binding Works
                Text("Current Selection: \(tab.rawValue)")
                
                // Test Programmatic Change
                Button("Swap Selection") {
                    withAnimation {
                        tab = (tab == .owedToYou) ? .youOwe : .owedToYou
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    PreviewWrapper()
}
