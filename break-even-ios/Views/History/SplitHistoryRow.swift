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
        HStack(spacing: 10) {
            Text(transaction.emoji)
                .font(Font.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Color.accent.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(transaction.payerName)
                    Text("•")
                    Text(transaction.dateValue.smartFormatted)
                }
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            Text(transaction.formattedAmount)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Single Row") {
    SplitHistoryRow(transaction: .previewDinner)
        .padding()
}

#Preview("List Container") {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(EnrichedTransaction.previewList.enumerated()), id: \.element._id) { index, tx in
            SplitHistoryRow(transaction: tx)
            if index < EnrichedTransaction.previewList.count - 1 {
                Divider()
                    .padding(.vertical, 12)
            }
        }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.secondary.opacity(0.6))
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .padding(.horizontal)
}
