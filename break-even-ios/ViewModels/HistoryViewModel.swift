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
    var selectedFriendId: String? = nil  // nil means "All Friends"
    
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
    
    // MARK: - Unique Friends for Filter
    
    /// Get all unique friends involved in transactions (excluding self)
    var uniqueFriends: [ConvexFriend] {
        var friendsDict: [String: ConvexFriend] = [:]
        
        for transaction in transactions {
            // Add payer if not self
            if let payer = transaction.payer, !payer.isSelf {
                friendsDict[payer.id] = payer
            }
            
            // Add split participants who are not self
            for split in transaction.splits {
                if let friend = split.friend, !friend.isSelf {
                    friendsDict[friend.id] = friend
                }
            }
        }
        
        // Sort alphabetically by name
        return Array(friendsDict.values).sorted { $0.name < $1.name }
    }
    
    /// Currently selected friend for display
    var selectedFriend: ConvexFriend? {
        guard let friendId = selectedFriendId else { return nil }
        return uniqueFriends.first { $0.id == friendId }
    }
    
    // MARK: - Filtering & Sorting
    
    var filteredTransactions: [EnrichedTransaction] {
        var result = transactions
        
        // Apply friend filter
        if let friendId = selectedFriendId {
            result = result.filter { transaction in
                // Check if friend is the payer
                if transaction.payer?.id == friendId {
                    return true
                }
                // Check if friend is in the splits
                return transaction.splits.contains { $0.friend?.id == friendId }
            }
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
    
    /// Clear friend filter
    func clearFriendFilter() {
        selectedFriendId = nil
    }
}
