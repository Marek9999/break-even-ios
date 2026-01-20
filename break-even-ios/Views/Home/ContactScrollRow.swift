//
//  ContactScrollRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct ContactScrollRow: View {
    let contacts: [(friend: ConvexFriend, amount: Double, isOwedToUser: Bool)]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(contacts, id: \.friend.id) { contact in
                    ContactAvatarItem(
                        friend: contact.friend,
                        amount: contact.amount,
                        isOwedToUser: contact.isOwedToUser
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Individual Contact Avatar Item

struct ContactAvatarItem: View {
    let friend: ConvexFriend
    let amount: Double
    let isOwedToUser: Bool
    
    private var backgroundColor: Color {
        isOwedToUser ? Color("AccentSecondary") : Color("DesctructiveSecondary")
    }
    
    private var textColor: Color {
        isOwedToUser ? Color("AccentColor") : Color("Destructive")
    }
    
    private var pillColor: Color {
        isOwedToUser ? Color("AccentColor") : Color("Destructive")
    }
    
    var body: some View {
        VStack(spacing: -4) {
            // Avatar
            avatarView
            
            // Amount pill
            Text(amount.asCompactCurrency)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pillColor)
                .clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } placeholder: {
                initialsView
            }
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(width: 56, height: 56)
            .background(backgroundColor)
            .clipShape(Circle())
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ContactScrollRow(contacts: [])
    }
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}
