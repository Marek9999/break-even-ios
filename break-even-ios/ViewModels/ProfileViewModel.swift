//
//  ProfileViewModel.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import ConvexMobile
internal import Combine

@MainActor
@Observable
class ProfileViewModel {
    // UI State
    var showAddContact = false
    var showCurrencyPicker = false
    var error: String?
    var isLoading = false
    
    // Seed sample data state (DEBUG only)
    var isSeedingData = false
    var seedMessage: String?
    var seedError = false
    
    // Clear data state (DEBUG only)
    var isClearingData = false
    var clearMessage: String?
    var clearError = false
    var showClearConfirmation = false
    
    // Sync state (DEBUG only)
    var isSyncing = false
    var syncMessage: String?
    var syncError = false
    
    // Data from Convex
    var friends: [ConvexFriend] = []
    var currentUser: ConvexUser?
    var sentInvitations: [EnrichedInvitation] = []
    
    // Subscriptions
    private var friendsSubscription: Task<Void, Never>?
    private var userSubscription: Task<Void, Never>?
    private var invitationsSubscription: Task<Void, Never>?
    
    /// Subscribe to friends list
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
            
            for await friendsList in subscription {
                if Task.isCancelled { break }
                self.friends = friendsList
            }
        }
    }
    
    /// Subscribe to current user
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
    
    /// Subscribe to sent invitations
    func subscribeToInvitations(clerkId: String) {
        invitationsSubscription?.cancel()
        
        invitationsSubscription = Task {
            let client = ConvexService.shared.client
            let subscription = client.subscribe(
                to: "invitations:listSentInvitations",
                with: ["clerkId": clerkId],
                yielding: [EnrichedInvitation].self
            )
            .replaceError(with: [])
            .values
            
            for await invites in subscription {
                if Task.isCancelled { break }
                self.sentInvitations = invites
            }
        }
    }
    
    /// Unsubscribe from all subscriptions
    func unsubscribe() {
        friendsSubscription?.cancel()
        userSubscription?.cancel()
        invitationsSubscription?.cancel()
    }
    
    /// Get non-self friends
    var otherFriends: [ConvexFriend] {
        friends.filter { !$0.isSelf }
    }
    
    /// Add a new friend
    func addFriend(clerkId: String, name: String, email: String?, phone: String?) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        // Build args - only include optional fields if they have values
        var args: [String: String] = [
            "clerkId": clerkId,
            "name": name
        ]
        if let email = email, !email.isEmpty {
            args["email"] = email
        }
        if let phone = phone, !phone.isEmpty {
            args["phone"] = phone
        }
        
        let client = ConvexService.shared.client
        let friendId: String = try await client.mutation(
            "friends:createDummyFriend",
            with: args
        )
        
        return friendId
    }
    
    /// Delete a friend
    func deleteFriend(friendId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let client = ConvexService.shared.client
        let _: Bool = try await client.mutation(
            "friends:deleteFriend",
            with: ["friendId": friendId]
        )
    }
    
    /// Update user profile
    func updateProfile(clerkId: String, name: String?, phone: String?, defaultCurrency: String?) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Build args - only include optional fields if they have values
        var args: [String: String] = ["clerkId": clerkId]
        if let name = name, !name.isEmpty {
            args["name"] = name
        }
        if let phone = phone, !phone.isEmpty {
            args["phone"] = phone
        }
        if let defaultCurrency = defaultCurrency, !defaultCurrency.isEmpty {
            args["defaultCurrency"] = defaultCurrency
        }
        
        let client = ConvexService.shared.client
        let _: String = try await client.mutation(
            "users:updateProfile",
            with: args
        )
    }
    
    /// Send friend invitation
    func sendInvitation(clerkId: String, friendId: String, email: String?, phone: String?) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        // Build args - only include optional fields if they have values
        var args: [String: String] = [
            "clerkId": clerkId,
            "friendId": friendId
        ]
        if let email = email, !email.isEmpty {
            args["recipientEmail"] = email
        }
        if let phone = phone, !phone.isEmpty {
            args["recipientPhone"] = phone
        }
        
        let client = ConvexService.shared.client
        
        struct InvitationResult: Codable {
            let invitationId: String
            let token: String
            let isExisting: Bool
        }
        
        let result: InvitationResult = try await client.mutation(
            "invitations:createInvitation",
            with: args
        )
        
        return result.token
    }
}
