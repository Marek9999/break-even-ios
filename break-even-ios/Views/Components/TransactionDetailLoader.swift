//
//  TransactionDetailLoader.swift
//  break-even-ios
//
//  Created by Cursor on 2026-03-25.
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

/// Loads a transaction by ID and displays `SplitDetailView`.
struct TransactionDetailLoader: View {
    let transactionId: String
    
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var transaction: EnrichedTransaction?
    @State private var userCurrency: String = "USD"
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let transaction {
                SplitDetailView(transaction: transaction, userCurrency: userCurrency)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Split Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This split may have been deleted")
                )
            }
        }
        .task(id: clerk.user?.id) {
            await loadTransaction()
        }
    }
    
    @MainActor
    private func loadTransaction() async {
        guard let clerkId = clerk.user?.id else {
            isLoading = false
            return
        }
        
        let client = convexService.client
        
        let transactionSubscription = client.subscribe(
            to: "transactions:getTransactionDetail",
            with: ["transactionId": transactionId],
            yielding: EnrichedTransaction?.self
        )
        .replaceError(with: nil)
        .values
        
        for await detail in transactionSubscription {
            if Task.isCancelled { break }
            transaction = detail
            break
        }
        
        let userSubscription = client.subscribe(
            to: "users:getCurrentUser",
            with: ["clerkId": clerkId],
            yielding: ConvexUser?.self
        )
        .replaceError(with: nil)
        .values
        
        for await user in userSubscription {
            if Task.isCancelled { break }
            if let user {
                userCurrency = user.defaultCurrency
            }
            break
        }
        
        isLoading = false
    }
}
