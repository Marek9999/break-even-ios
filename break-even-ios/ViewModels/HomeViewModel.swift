//
//  HomeViewModel.swift
//  break-even-ios
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
    var currentUser: ConvexUser?
    
    // User's default currency (derived from currentUser)
    var userCurrency: String {
        currentUser?.defaultCurrency ?? "USD"
    }
    
    // Subscriptions
    private var balancesSubscription: Task<Void, Never>?
    private var friendsSubscription: Task<Void, Never>?
    private var userSubscription: Task<Void, Never>?
    
    /// Subscribe to friends with balances
    func subscribeToBalances(clerkId: String) {
        balancesSubscription?.cancel()
        
        balancesSubscription = Task {
            let client = ConvexService.shared.client
            let subscription = client.subscribe(
                to: "friends:getFriendsWithBalances",
                with: ["clerkId": clerkId],
                yielding: FriendsWithBalancesResponse.self
            )
            .replaceError(with: FriendsWithBalancesResponse(balances: [], userCurrency: "USD"))
            .values
            
            for await response in subscription {
                if Task.isCancelled { break }
                self.friendsWithBalances = response.balances
                // userCurrency from response can be used if needed, 
                // but we already have it from currentUser subscription
            }
        }
    }
    
    /// Subscribe to all friends
    func subscribeToFriends(clerkId: String) {
        friendsSubscription?.cancel()
        
        friendsSubscription = Task {
            let client = ConvexService.shared.client
            let subscription = client.subscribe(
                to: "friends:listFriends",
                with: ["clerkId": clerkId],
                yielding: [ConvexFriend].self
            )
            .replaceError(with: [])
            .values
            
            for await friends in subscription {
                if Task.isCancelled { break }
                self.allFriends = friends
                self.selfFriend = friends.first(where: { $0.isSelf })
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
        balancesSubscription?.cancel()
        friendsSubscription?.cancel()
        userSubscription?.cancel()
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
        allFriends.filter { !$0.isSelf }
    }
}
