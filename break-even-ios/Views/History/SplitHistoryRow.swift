//
//  SplitHistoryRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct SplitHistoryRow: View {
    let transaction: EnrichedTransaction
    
    var body: some View {
        HStack(spacing: 12) {
            // Emoji
            Text(transaction.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(transaction.payerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(transaction.dateValue.smartFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            Text(transaction.formattedAmount)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 8) {
        SplitHistoryRow(
            transaction: EnrichedTransaction(
                _id: "1",
                createdById: "user1",
                paidById: "friend1",
                title: "Team Dinner",
                emoji: "🍕",
                description: nil,
                totalAmount: 156.80,
                currency: "USD",
                splitMethod: "equal",
                receiptFileId: nil,
                items: nil,
                exchangeRates: nil,
                date: Date().timeIntervalSince1970 * 1000,
                createdAt: Date().timeIntervalSince1970 * 1000,
                payer: ConvexFriend(
                    _id: "friend1",
                    ownerId: "user1",
                    linkedUserId: nil,
                    name: "Me",
                    email: nil,
                    phone: nil,
                    avatarUrl: nil,
                    isDummy: false,
                    isSelf: true,
                    createdAt: Date().timeIntervalSince1970 * 1000
                ),
                splits: [],
                receiptUrl: nil
            )
        )
    }
    .padding()
}
