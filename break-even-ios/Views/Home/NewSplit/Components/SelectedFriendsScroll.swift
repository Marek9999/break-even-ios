//
//  SelectedFriendsScroll.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Horizontal scroll view showing selected friends with avatar and name
struct SelectedFriendsScroll: View {
    let friends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    let onRemove: (ConvexFriend) -> Void
    let onAddMore: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(friends, id: \.id) { friend in
                    FriendChipView(
                        friend: friend,
                        isSelf: friend.id == selfFriend?.id,
                        onRemove: { onRemove(friend) }
                    )
                }
                
                // Add more button
                addButton
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button(action: onAddMore) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.accent)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Chip View

struct FriendChipView: View {
    let friend: ConvexFriend
    let isSelf: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            FriendChipAvatar(friend: friend, size: 32)
            
            // Name
            Text(friend.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            // Remove button (not for self)
            if !isSelf {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, isSelf ? 12 : 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Friend Chip Avatar

private struct FriendChipAvatar: View {
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

#Preview("Selected Friends Scroll") {
    struct PreviewWrapper: View {
        @State private var friends: [ConvexFriend] = []
        
        var body: some View {
            VStack {
                SelectedFriendsScroll(
                    friends: friends,
                    selfFriend: nil,
                    onRemove: { _ in },
                    onAddMore: { }
                )
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
