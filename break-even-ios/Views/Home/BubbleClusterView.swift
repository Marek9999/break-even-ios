//
//  BubbleClusterView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct BubbleClusterView: View {
    let contacts: [(friend: ConvexFriend, amount: Double)]
    let isOwedToUser: Bool
    let currencyCode: String  // User's default currency
    let onPersonTap: (ConvexFriend) -> Void
    
    @State private var bubblePositions: [String: CGPoint] = [:]
    @State private var containerSize: CGSize = .zero
    @State private var hasAnimated = false
    
    private let minBubbleSize: CGFloat = 60
    private let maxBubbleSize: CGFloat = 120
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(contacts, id: \.friend.id) { contact in
                    if let position = bubblePositions[contact.friend.id] {
                        BubbleView(
                            friend: contact.friend,
                            amount: contact.amount,
                            size: bubbleSize(for: contact.amount),
                            isOwedToUser: isOwedToUser,
                            currencyCode: currencyCode,
                            onTap: {
                                onPersonTap(contact.friend)
                            }
                        )
                        .position(position)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                containerSize = geometry.size
                calculatePositions()
            }
            .onChange(of: geometry.size) { _, newSize in
                containerSize = newSize
                calculatePositions()
            }
            .onChange(of: contacts.map(\.friend.id)) { _, _ in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    calculatePositions()
                }
            }
        }
    }
    
    private func bubbleSize(for amount: Double) -> CGFloat {
        guard !contacts.isEmpty else { return minBubbleSize }
        
        let amounts = contacts.map(\.amount)
        let minAmount = amounts.min() ?? 0
        let maxAmount = amounts.max() ?? 1
        
        if maxAmount == minAmount {
            return (minBubbleSize + maxBubbleSize) / 2
        }
        
        let normalized = (amount - minAmount) / (maxAmount - minAmount)
        return minBubbleSize + (maxBubbleSize - minBubbleSize) * normalized
    }
    
    private func calculatePositions() {
        guard containerSize.width > 0 && containerSize.height > 0 else { return }
        
        var newPositions: [String: CGPoint] = [:]
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        
        let sortedContacts = contacts.sorted { $0.amount > $1.amount }
        
        if sortedContacts.isEmpty { return }
        
        // Place first (largest) bubble in center
        if let first = sortedContacts.first {
            newPositions[first.friend.id] = CGPoint(x: centerX, y: centerY)
        }
        
        // Place remaining bubbles around
        for (index, contact) in sortedContacts.dropFirst().enumerated() {
            let angle = Double(index) * (2 * .pi / Double(max(sortedContacts.count - 1, 1)))
            let radius = min(containerSize.width, containerSize.height) * 0.3
            
            let x = centerX + cos(angle) * radius
            let y = centerY + sin(angle) * radius
            
            newPositions[contact.friend.id] = CGPoint(x: x, y: y)
        }
        
        // Apply positions with animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            bubblePositions = newPositions
        }
    }
}

// MARK: - Bubble View

struct BubbleView: View {
    let friend: ConvexFriend
    let amount: Double
    let size: CGFloat
    let isOwedToUser: Bool
    let currencyCode: String
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: -4) {
                // Avatar
                if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        initialsView
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .padding(2)
                    .glassEffect(.regular.interactive(), in: Circle())
                } else {
                    initialsView
                }
                
                // Amount in user's currency
                Text(amount.asCurrency(code: currencyCode))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isOwedToUser ? Color.accent : Color.appDestructive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .background(isOwedToUser ? Color.accent.opacity(0.1) : Color.appDestructive.opacity(0.1))
                    .clipShape(Capsule())
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(BubbleButtonStyle())
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.3, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isOwedToUser ? Color.accent.opacity(0.6) : Color.appDestructive.opacity(0.6))
            .clipShape(Circle())
    }
}

// MARK: - Bubble Button Style

struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Empty View

struct BubbleClusterEmptyView: View {
    let isOwedToUser: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isOwedToUser ? "checkmark.circle" : "face.smiling")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(isOwedToUser ? "No one owes you" : "You're all caught up!")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(isOwedToUser ? "Start a split to track who owes you" : "No pending payments")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    BubbleClusterView(
        contacts: [],
        isOwedToUser: true,
        currencyCode: "USD",
        onPersonTap: { _ in }
    )
}
