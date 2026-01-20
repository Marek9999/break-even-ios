//
//  HistoryViewModel.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import ConvexMobile
internal import Combine

enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case pending = "Pending"
    case settled = "Settled"
}

enum SortOrder: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
}

@MainActor
@Observable
class HistoryViewModel {
    // Filters
    var selectedFilter: HistoryFilter = .all
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
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .pending:
            result = result.filter { !$0.isFullySettled }
        case .settled:
            result = result.filter { $0.isFullySettled }
        }
        
        // Apply search
        if !searchText.isEmpty {
            result = result.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .newest:
            result.sort { $0.date > $1.date }
        case .oldest:
            result.sort { $0.date < $1.date }
        }
        
        return result
    }
}
