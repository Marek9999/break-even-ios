//
//  ExpandableItemRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Expandable row for itemized split showing item details and friend assignment
struct ExpandableItemRow: View {
    let item: SplitItem
    let participants: [ConvexFriend]
    let currencyCode: String
    let onToggleAssignment: (ConvexFriend) -> Void
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    /// Number of friends assigned to this item
    private var assignedCount: Int {
        item.assignedTo.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            mainRow
            
            // Expanded friend assignment
            if isExpanded {
                friendAssignmentSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
    
    // MARK: - Main Row
    
    private var mainRow: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                // Item name
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Quantity badge (if more than 1)
                Text("QTY")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                // Price
                Text(item.amount.asCurrency(code: currencyCode))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Friend Assignment Section
    
    private var friendAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 8)
            
            // Header
            HStack {
                Text("Assign to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if assignedCount > 0 {
                    Text("\(assignedCount) selected")
                        .font(.caption)
                        .foregroundStyle(.accent)
                }
            }
            
            // Friend chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(participants, id: \.id) { friend in
                        AssignmentChip(
                            friend: friend,
                            isAssigned: item.assignedTo.contains(friend.id),
                            onToggle: { onToggleAssignment(friend) }
                        )
                    }
                }
            }
            
            // Remove item button
            HStack {
                Spacer()
                
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Item", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Assignment Chip

private struct AssignmentChip: View {
    let friend: ConvexFriend
    let isAssigned: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                // Avatar
                AssignmentChipAvatar(friend: friend, size: 24)
                
                // Name
                Text(friend.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                // Checkmark if assigned
                if isAssigned {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isAssigned
                    ? Color.accent.opacity(0.2)
                    : Color.secondary.opacity(0.1)
            )
            .foregroundStyle(isAssigned ? .accent : .primary)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isAssigned ? Color.accent : Color.clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Assignment Chip Avatar

private struct AssignmentChipAvatar: View {
    let friend: ConvexFriend
    let size: CGFloat
    
    var body: some View {
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
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

// MARK: - Preview

#Preview("Expandable Item Row") {
    VStack(spacing: 12) {
        ExpandableItemRow(
            item: SplitItem(name: "Pizza Margherita", amount: 18.99),
            participants: [],
            currencyCode: "USD",
            onToggleAssignment: { _ in },
            onRemove: { }
        )
        
        ExpandableItemRow(
            item: SplitItem(name: "Caesar Salad", amount: 12.50),
            participants: [],
            currencyCode: "USD",
            onToggleAssignment: { _ in },
            onRemove: { }
        )
    }
    .padding()
}
