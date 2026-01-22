//
//  PendingSplitRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct PendingSplitRow: View {
    let split: EnrichedSplit
    let transaction: EnrichedTransaction
    
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                // Emoji/Icon
                Text(transaction.emoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Split Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text("Pay \(transaction.payerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(split.formattedAmount)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    
                    Text(transaction.dateValue.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SplitDetailSheet(split: split, transaction: transaction)
        }
    }
}

struct SplitDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let split: EnrichedSplit
    let transaction: EnrichedTransaction
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Amount Card
                    VStack(spacing: 8) {
                        Text("You Owe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(split.formattedAmount)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.orange)
                        
                        Text("to \(transaction.payerName)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(label: "Transaction", value: transaction.title)
                        DetailRow(label: "Paid by", value: transaction.payerName)
                        DetailRow(label: "Date", value: transaction.dateValue.smartFormatted)
                        
                        if let percentage = split.percentage {
                            DetailRow(label: "Your Share", value: percentage.asPercentage)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Split Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    PendingSplitRow(
        split: EnrichedSplit(
            _id: "split1",
            transactionId: "tx1",
            friendId: "friend1",
            amount: 50.0,
            percentage: nil,
            createdAt: Date().timeIntervalSince1970 * 1000,
            friend: nil
        ),
        transaction: EnrichedTransaction(
            _id: "tx1",
            createdById: "user1",
            paidById: "friend1",
            title: "Dinner",
            emoji: "🍕",
            description: nil,
            totalAmount: 100.0,
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
                name: "John",
                email: nil,
                phone: nil,
                avatarUrl: nil,
                isDummy: false,
                isSelf: false,
                createdAt: Date().timeIntervalSince1970 * 1000
            ),
            splits: [],
            receiptUrl: nil
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
