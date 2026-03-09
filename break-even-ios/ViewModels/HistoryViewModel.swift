//
//  HistoryViewModel.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import ConvexMobile
internal import Combine

enum SortOrder: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case highestAmount = "Highest Amount"
    case lowestAmount = "Lowest Amount"
}

@MainActor
@Observable
class HistoryViewModel {
    var sortOrder: SortOrder = .newest
    var searchText: String = ""
    
    // UI State
    var selectedTransaction: EnrichedTransaction?
    var isLoading = false
    var error: String?
    
    // Data from Convex
    var transactions: [EnrichedTransaction] = []
    var currentUser: ConvexUser?
    
    // User's default currency (derived from currentUser)
    var userCurrency: String {
        currentUser?.defaultCurrency ?? "USD"
    }
    
    // Subscriptions
    private var transactionsSubscription: Task<Void, Never>?
    private var userSubscription: Task<Void, Never>?
    
    /// Subscribe to transactions
    func subscribeToTransactions(clerkId: String) {
        transactionsSubscription?.cancel()
        
        transactionsSubscription = Task {
            let client = ConvexService.shared.client
            let subscription = client.subscribe(
                to: "transactions:listTransactions",
                with: ["clerkId": clerkId],
                yielding: [EnrichedTransaction].self
            )
            .replaceError(with: [])
            .values
            
            for await txs in subscription {
                if Task.isCancelled { break }
                self.transactions = txs
            }
        }
    }
    
    /// Subscribe to current user (for settings like default currency)
    func subscribeToUser(clerkId: String) {
        userSubscription?.cancel()
        
        userSubscription = Task {
            let client = ConvexService.shared.client
            let subscription = client.subscribe(
                to: "users:getCurrentUser",
                with: ["clerkId": clerkId],
                yielding: ConvexUser?.self
            )
            .replaceError(with: nil)
            .values
            
            for await user in subscription {
                if Task.isCancelled { break }
                self.currentUser = user
            }
        }
    }
    
    /// Unsubscribe from all subscriptions
    func unsubscribe() {
        transactionsSubscription?.cancel()
        userSubscription?.cancel()
    }
    
    // MARK: - Filtering & Sorting
    
    var filteredTransactions: [EnrichedTransaction] {
        var result = transactions
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        switch sortOrder {
        case .newest:
            result.sort { $0.date > $1.date }
        case .oldest:
            result.sort { $0.date < $1.date }
        case .highestAmount:
            result.sort { $0.totalAmount > $1.totalAmount }
        case .lowestAmount:
            result.sort { $0.totalAmount < $1.totalAmount }
        }
        
        return result
    }
}
