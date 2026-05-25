//
//  HomeViewModel.swift
//  PayUp
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import ConvexMobile
import Clerk
internal import Combine

@MainActor
@Observable
class HomeViewModel {
    // UI State
    var showAddTransaction = false
    var error: String?
    var isLoading = false
    
    // Data from Convex
    var friendsWithBalances: [FriendWithBalance] = []
    var selfFriend: ConvexFriend?
    var allFriends: [ConvexFriend] = []
    
    // Subscriptions
    private var balancesSubscription: Task<Void, Never>?
    private var friendsSubscription: Task<Void, Never>?
    
    private func handleSubscriptionFailure(_ context: String, error: Error) {
        self.error = "Couldn't refresh Home data right now."
        
        #if DEBUG
        print("Home subscription failed (\(context)): \(error)")
        #endif
    }
    
    /// Subscribe to friends with balances
    func subscribeToBalances(clerkId: String) {
        balancesSubscription?.cancel()
        
        balancesSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "friends:getFriendsWithBalances",
                    with: ["clerkId": clerkId],
                    yielding: FriendsWithBalancesResponse.self
                )
                .values
                
                for try await response in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.friendsWithBalances = response.balances
                    // userCurrency from response can be used if needed,
                    // but we already have it from currentUser subscription
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("friends:getFriendsWithBalances", error: error)
            }
        }
    }
    
    /// Subscribe to all friends
    func subscribeToFriends(clerkId: String) {
        friendsSubscription?.cancel()
        
        friendsSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "friends:listFriends",
                    with: ["clerkId": clerkId],
                    yielding: [ConvexFriend].self
                )
                .values
                
                for try await friends in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.allFriends = friends
                    self.selfFriend = friends.first(where: { $0.isSelf })
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("friends:listFriends", error: error)
            }
        }
    }
    
    /// Unsubscribe from all subscriptions
    func unsubscribe() {
        balancesSubscription?.cancel()
        friendsSubscription?.cancel()
    }
    
    // MARK: - Computed Properties
    
    /// Friends who owe the user money
    var owedToMe: [FriendWithBalance] {
        friendsWithBalances
            .filter { $0.isOwedToUser }
            .sorted { $0.netBalance > $1.netBalance }
    }
    
    /// Friends the user owes money to
    var iOwe: [FriendWithBalance] {
        friendsWithBalances
            .filter { !$0.isOwedToUser }
            .sorted { abs($0.netBalance) > abs($1.netBalance) }
    }
    
    /// Total amount owed to the user
    var totalOwedToMe: Double {
        owedToMe.reduce(0) { $0 + $1.netBalance }
    }
    
    /// Total amount the user owes
    var totalIOwe: Double {
        iOwe.reduce(0) { $0 + abs($1.netBalance) }
    }
    
    /// Get non-self friends for selection
    var selectableFriends: [ConvexFriend] {
        allFriends.filter(\.isSelectableForNewSplit)
    }
}
