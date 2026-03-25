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
    
    private func handleSubscriptionFailure(_ context: String, error: Error) {
        self.error = "Couldn't refresh History right now."
        
        #if DEBUG
        print("History subscription failed (\(context)): \(error)")
        #endif
    }
    
    /// Subscribe to transactions
    func subscribeToTransactions(clerkId: String) {
        transactionsSubscription?.cancel()
        
        transactionsSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "transactions:listTransactions",
                    with: ["clerkId": clerkId],
                    yielding: [EnrichedTransaction].self
                )
                .values
                
                for try await txs in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.transactions = txs
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("transactions:listTransactions", error: error)
            }
        }
    }
    
    /// Subscribe to current user (for settings like default currency)
    func subscribeToUser(clerkId: String) {
        userSubscription?.cancel()
        
        userSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "users:getCurrentUser",
                    with: ["clerkId": clerkId],
                    yielding: ConvexUser?.self
                )
                .values
                
                for try await user in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.currentUser = user
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("users:getCurrentUser", error: error)
            }
        }
    }
    
    /// Unsubscribe from all subscriptions
    func unsubscribe() {
        transactionsSubscription?.cancel()
        userSubscription?.cancel()
    }
    
    // MARK: - Filtering & Sorting
    
    private static let dateSearchFormatters: [DateFormatter] = {
        let short = DateFormatter()
        short.dateStyle = .medium
        short.timeStyle = .none
        
        let monthYear = DateFormatter()
        monthYear.dateFormat = "MMMM yyyy"
        
        let monthOnly = DateFormatter()
        monthOnly.dateFormat = "MMMM"
        
        let shortMonth = DateFormatter()
        shortMonth.dateFormat = "MMM d, yyyy"
        
        return [short, monthYear, monthOnly, shortMonth]
    }()
    
    var filteredTransactions: [EnrichedTransaction] {
        var result = transactions
        
        if !searchText.isEmpty {
            let query = searchText
            result = result.filter { matchesSearch($0, query: query) }
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
    
    private func matchesSearch(_ transaction: EnrichedTransaction, query: String) -> Bool {
        if transaction.title.localizedCaseInsensitiveContains(query) { return true }
        
        if transaction.description?.localizedCaseInsensitiveContains(query) == true { return true }
        
        if transaction.emoji.localizedCaseInsensitiveContains(query) { return true }
        
        if let payer = transaction.payer {
            if payer.name.localizedCaseInsensitiveContains(query) { return true }
            if payer.displayName.localizedCaseInsensitiveContains(query) { return true }
        }
        
        for split in transaction.splits {
            if let friend = split.friend {
                if friend.name.localizedCaseInsensitiveContains(query) { return true }
                if friend.displayName.localizedCaseInsensitiveContains(query) { return true }
            }
        }
        
        let date = Date(timeIntervalSince1970: transaction.date / 1000)
        for formatter in Self.dateSearchFormatters {
            if formatter.string(from: date).localizedCaseInsensitiveContains(query) { return true }
        }
        
        if let items = transaction.items {
            for item in items {
                if item.name.localizedCaseInsensitiveContains(query) { return true }
            }
        }
        
        if transaction.currency.localizedCaseInsensitiveContains(query) { return true }
        
        let amountString = String(format: "%.2f", transaction.totalAmount)
        if amountString.contains(query) { return true }
        if transaction.formattedAmount.localizedCaseInsensitiveContains(query) { return true }
        
        let methodDisplay = transaction.splitMethod
            .replacingOccurrences(of: "byItem", with: "by item")
            .replacingOccurrences(of: "byParts", with: "by parts")
        if methodDisplay.localizedCaseInsensitiveContains(query) { return true }
        
        return false
    }
}
