//
//  SplitBreakdownView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct SplitBreakdownView: View {
    @Bindable var viewModel: NewSplitViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Split Breakdown")
                .font(.headline)
            
            switch viewModel.splitMethod {
            case .equal:
                equalSplitView
            case .unequal:
                unequalSplitView
            case .byParts:
                byPartsSplitView
            case .byItem:
                byItemSplitView
            }
        }
    }
    
    // MARK: - Equal Split View
    
    private var equalSplitView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.participants, id: \.id) { friend in
                HStack {
                    FriendAvatar(friend: friend, size: 32)
                    
                    Text(friend.displayName)
                        .font(.body)
                    
                    Spacer()
                    
                    Text(viewModel.formattedShare(for: friend))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - Unequal Split View
    
    private var unequalSplitView: some View {
        VStack(spacing: 12) {
            // Remaining to assign
            HStack {
                Text("Remaining to assign")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(viewModel.remainingToAssign.asCurrency)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(viewModel.remainingToAssign > 0 ? .orange : .green)
            }
            .padding(.horizontal)
            
            ForEach(viewModel.participants, id: \.id) { friend in
                HStack {
                    FriendAvatar(friend: friend, size: 32)
                    
                    Text(friend.displayName)
                        .font(.body)
                    
                    Spacer()
                    
                    TextField("0.00", value: Binding(
                        get: { viewModel.getCustomAmount(for: friend) },
                        set: { viewModel.setCustomAmount($0, for: friend) }
                    ), format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - By Parts Split View
    
    private var byPartsSplitView: some View {
        VStack(spacing: 12) {
            // Total parts info
            HStack {
                Text("Total parts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(viewModel.totalParts)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            
            ForEach(viewModel.participants, id: \.id) { friend in
                HStack {
                    FriendAvatar(friend: friend, size: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .font(.body)
                        
                        Text(viewModel.formattedShare(for: friend))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Parts stepper
                    HStack(spacing: 12) {
                        Button {
                            viewModel.decrementParts(for: friend)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(viewModel.getParts(for: friend) <= 1)
                        
                        Text("\(viewModel.getParts(for: friend))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(minWidth: 30)
                        
                        Button {
                            viewModel.incrementParts(for: friend)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.accent)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - By Item Split View
    
    private var byItemSplitView: some View {
        VStack(spacing: 16) {
            // Add item button
            Button {
                // Show add item sheet
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Item")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Items list
            ForEach(viewModel.items) { item in
                ItemSplitRow(
                    item: item,
                    participants: viewModel.participants,
                    onToggleAssignment: { friend in
                        viewModel.toggleItemAssignment(item: item, friend: friend)
                    },
                    onRemove: {
                        viewModel.removeItem(item)
                    }
                )
            }
            
            // Items total
            if !viewModel.items.isEmpty {
                HStack {
                    Text("Items Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(viewModel.itemsTotal.asCurrency)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal)
            }
            
            // Per-person breakdown
            if !viewModel.items.isEmpty {
                Divider()
                
                Text("Per Person")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                ForEach(viewModel.participants, id: \.id) { friend in
                    HStack {
                        FriendAvatar(friend: friend, size: 28)
                        
                        Text(friend.displayName)
                            .font(.body)
                        
                        Spacer()
                        
                        Text(viewModel.formattedShare(for: friend))
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Friend Avatar

struct FriendAvatar: View {
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

// MARK: - Item Split Row

struct ItemSplitRow: View {
    let item: SplitItem
    let participants: [ConvexFriend]
    let onToggleAssignment: (ConvexFriend) -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(item.formattedAmount)
                    .font(.body)
                    .fontWeight(.semibold)
                
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Assign to people
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(participants, id: \.id) { friend in
                        Button {
                            onToggleAssignment(friend)
                        } label: {
                            HStack(spacing: 4) {
                                FriendAvatar(friend: friend, size: 24)
                                
                                Text(friend.displayName)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                item.assignedTo.contains(friend.id)
                                    ? Color.accent.opacity(0.2)
                                    : Color.secondary.opacity(0.1)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        item.assignedTo.contains(friend.id)
                                            ? Color.accent
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview("Equal Split") {
    let vm = NewSplitViewModel.preview
    vm.splitMethod = .equal
    return SplitBreakdownView(viewModel: vm)
        .padding()
}
