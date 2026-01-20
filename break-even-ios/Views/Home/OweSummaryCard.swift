//
//  OweSummaryCard.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct OweSummaryCard: View {
    let title: String
    let totalAmount: Double
    let friends: [(friend: ConvexFriend, amount: Double)]
    let isOwedToUser: Bool
    let currencyCode: String  // User's default currency for display
    
    @State private var showPeopleList = false
    
    private var accentColor: Color {
        isOwedToUser ? Color("AccentColor") : Color("Destructive")
    }
    
    private var secondaryColor: Color {
        isOwedToUser ? Color("AccentSecondary") : Color("DesctructiveSecondary")
    }
    
    private var iconName: String {
        isOwedToUser ? "arrow.down.left" : "arrow.up.right"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                    
                    Text(totalAmount.asCurrency(code: currencyCode))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color("Text"))
                }
            }
            
            Spacer()
            
            // Avatar stack or decorative circles
            avatarStack
                .contentShape(Rectangle())
                .onTapGesture {
                    if !friends.isEmpty {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        showPeopleList = true
                    }
                }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .sheet(isPresented: $showPeopleList) {
            FriendsListSheet(
                title: title,
                friends: friends,
                isOwedToUser: isOwedToUser,
                currencyCode: currencyCode
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    @ViewBuilder
    private var avatarStack: some View {
        if friends.isEmpty {
            // Show decorative circles when no friends
            decorativeCircles
        } else {
            // Show actual avatars
            HStack(spacing: -8) {
                ForEach(Array(friends.prefix(3).enumerated()), id: \.element.friend.id) { index, item in
                    friendAvatar(for: item.friend)
                        .zIndex(Double(3 - index))
                }
                
                if friends.count > 3 {
                    Text("+\(friends.count - 3)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                        .background(secondaryColor.opacity(0.7))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                        )
                }
            }
        }
    }
    
    private func friendAvatar(for friend: ConvexFriend) -> some View {
        Group {
            if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(friend.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            } else {
                Text(friend.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
        }
        .frame(width: 36, height: 36)
        .background(secondaryColor)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
        )
    }
    
    private var decorativeCircles: some View {
        ZStack {
            // Large circle (bottom right)
            Circle()
                .fill(secondaryColor)
                .frame(width: 44, height: 44)
                .offset(x: 8, y: 8)
            
            // Medium circle (top left of large)
            Circle()
                .fill(secondaryColor.opacity(0.7))
                .frame(width: 32, height: 32)
                .offset(x: -16, y: -4)
        }
        .frame(width: 80, height: 60)
    }
}

// MARK: - Friends List Sheet

struct FriendsListSheet: View {
    let title: String
    let friends: [(friend: ConvexFriend, amount: Double)]
    let isOwedToUser: Bool
    let currencyCode: String
    
    @Environment(\.dismiss) private var dismiss
    
    private var accentColor: Color {
        isOwedToUser ? Color("AccentColor") : Color("Destructive")
    }
    
    private var secondaryColor: Color {
        isOwedToUser ? Color("AccentSecondary") : Color("DesctructiveSecondary")
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(friends, id: \.friend.id) { item in
                    FriendAmountRow(
                        friend: item.friend,
                        amount: item.amount,
                        accentColor: accentColor,
                        secondaryColor: secondaryColor,
                        currencyCode: currencyCode
                    )
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Friend Amount Row

struct FriendAmountRow: View {
    let friend: ConvexFriend
    let amount: Double
    let accentColor: Color
    let secondaryColor: Color
    let currencyCode: String
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            Group {
                if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(friend.initials)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                } else {
                    Text(friend.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .frame(width: 44, height: 44)
            .background(secondaryColor)
            .clipShape(Circle())
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                if let email = friend.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            Text(amount.asCurrency(code: currencyCode))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // With friends
        OweSummaryCard(
            title: "Owed to you",
            totalAmount: 723.45,
            friends: [],
            isOwedToUser: true,
            currencyCode: "USD"
        )
        
        OweSummaryCard(
            title: "You owe others",
            totalAmount: 423.25,
            friends: [],
            isOwedToUser: false,
            currencyCode: "EUR"
        )
        
        // Empty state
        OweSummaryCard(
            title: "Owed to you",
            totalAmount: 0,
            friends: [],
            isOwedToUser: true,
            currencyCode: "GBP"
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
