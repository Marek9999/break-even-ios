//
//  AvatarView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Avatar view for displaying a friend's profile image or initials
struct AvatarView: View {
    let friend: ConvexFriend
    var size: CGFloat = 44
    var backgroundColor: Color = Color("AccentSecondary")
    var textColor: Color = Color("AccentColor")
    
    var body: some View {
        Group {
            if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .background(backgroundColor)
        .clipShape(Circle())
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(textColor)
    }
}

// MARK: - Avatar with Amount Pill

struct AvatarWithAmount: View {
    let friend: ConvexFriend
    let amount: Double
    let isOwedToUser: Bool
    var avatarSize: CGFloat = 56
    
    var body: some View {
        VStack(spacing: 4) {
            AvatarView(
                friend: friend,
                size: avatarSize,
                backgroundColor: isOwedToUser ? Color("AccentSecondary") : Color("DesctructiveSecondary"),
                textColor: isOwedToUser ? Color("AccentColor") : Color("Destructive")
            )
            
            Text(amount.asCompactCurrency)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOwedToUser ? Color("AccentColor") : Color("Destructive"))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Decorative Avatar Circles (for summary cards)

struct DecorativeAvatarCircles: View {
    let count: Int
    let accentColor: Color
    let secondaryColor: Color
    
    var body: some View {
        HStack(spacing: -8) {
            Circle()
                .fill(secondaryColor.opacity(0.6))
                .frame(width: 28, height: 28)
            
            Circle()
                .fill(secondaryColor)
                .frame(width: 36, height: 36)
            
            if count > 3 {
                Text("+\(count - 3)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)
                    .background(secondaryColor.opacity(0.5))
                    .clipShape(Circle())
                    .offset(x: -4, y: -12)
            }
        }
    }
}

// MARK: - Person Avatar (Glassmorphism style)

struct PersonAvatar: View {
    let friend: ConvexFriend
    var size: CGFloat = 44
    var showGlass: Bool = true
    
    var body: some View {
        Group {
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

#Preview {
    VStack(spacing: 20) {
        // Decorative circles
        DecorativeAvatarCircles(
            count: 5,
            accentColor: Color("AccentColor"),
            secondaryColor: Color("AccentSecondary")
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
