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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        )
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
            FriendAvatar(friend: friend, size: 32)
            
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
                        .foregroundStyle(.text.opacity(0.6))
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

// MARK: - Preview

#Preview("Selected Friends Scroll") {
    struct PreviewWrapper: View {
        @State private var friends: [ConvexFriend] = []
        
        var body: some View {
            VStack {
                SelectedFriendsScroll(
                    friends: friends,
                    selfFriend: nil,
                    onRemove: { _ in }
                )
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
