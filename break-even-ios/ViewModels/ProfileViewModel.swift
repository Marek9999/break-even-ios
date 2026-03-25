//
//  ProfileViewModel.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import SwiftUI
import ConvexMobile
internal import Combine

@MainActor
@Observable
class ProfileViewModel {
    // UI State
    var showAddContact = false
    var showCurrencyPicker = false
    var showSignOutConfirmation = false
    var showPhotoLibrary = false
    var showCamera = false
    var isUpdatingPhoto = false
    var error: String?
    var isLoading = false
    
    // Avatar / dominant color
    var cachedAvatarImage: UIImage?
    var dominantColor: Color?
    
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
    var receivedInvitations: [ReceivedInvitation] = []
    
    // Subscriptions
    private var friendsSubscription: Task<Void, Never>?
    private var userSubscription: Task<Void, Never>?
    private var invitationsSubscription: Task<Void, Never>?
    private var receivedInvitationsSubscription: Task<Void, Never>?
    
    private func handleSubscriptionFailure(_ context: String, error: Error) {
        self.error = "Couldn't refresh Profile right now."
        
        #if DEBUG
        print("Profile subscription failed (\(context)): \(error)")
        #endif
    }
    
    /// Subscribe to friends list
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
                
                for try await friendsList in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.friends = friendsList
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("friends:listFriends", error: error)
            }
        }
    }
    
    /// Subscribe to current user
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
    
    /// Subscribe to sent invitations
    func subscribeToInvitations(clerkId: String) {
        invitationsSubscription?.cancel()
        
        invitationsSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "invitations:listSentInvitations",
                    with: ["clerkId": clerkId],
                    yielding: [EnrichedInvitation].self
                )
                .values
                
                for try await invites in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.sentInvitations = invites
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("invitations:listSentInvitations", error: error)
            }
        }
    }
    
    /// Subscribe to received invitations (for in-app accept/deny)
    func subscribeToReceivedInvitations(clerkId: String) {
        receivedInvitationsSubscription?.cancel()
        
        receivedInvitationsSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "invitations:listReceivedInvitations",
                    with: ["clerkId": clerkId],
                    yielding: [ReceivedInvitation].self
                )
                .values
                
                for try await invites in subscription {
                    if Task.isCancelled { break }
                    self.error = nil
                    self.receivedInvitations = invites
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("invitations:listReceivedInvitations", error: error)
            }
        }
    }
    
    /// Unsubscribe from all subscriptions
    func unsubscribe() {
        friendsSubscription?.cancel()
        userSubscription?.cancel()
        invitationsSubscription?.cancel()
        receivedInvitationsSubscription?.cancel()
    }
    
    /// Get non-self friends (excludes invite_received since those are shown in invitations section)
    var otherFriends: [ConvexFriend] {
        friends.filter { !$0.isSelf && $0.inviteStatus != "invite_received" }
    }
    
    /// Oldest friends (by createdAt), max 3, for the profile card preview
    var oldestFriendPreviews: [ConvexFriend] {
        Array(otherFriends.sorted { $0.createdAt < $1.createdAt }.prefix(3))
    }
    
    /// Load the user's avatar image and extract dominant color
    func loadAvatarImage(from urlString: String?) async {
        guard let urlString, let url = URL(string: urlString) else {
            cachedAvatarImage = nil
            dominantColor = nil
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return }
            cachedAvatarImage = uiImage
            if let color = uiImage.dominantColor() {
                withAnimation(.easeInOut(duration: 0.4)) {
                    dominantColor = color
                }
            }
        } catch {
            // Silently fail -- initials placeholder will remain
        }
    }
    
    /// Add a new friend
    func addFriend(clerkId: String, name: String, email: String?, phone: String?) async throws -> CreateFriendResponse {
        isLoading = true
        defer { isLoading = false }
        
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
        let result: CreateFriendResponse = try await client.mutation(
            "friends:createDummyFriend",
            with: args
        )
        
        return result
    }
    
    /// Delete a friend
    func deleteFriend(clerkId: String, friendId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let client = ConvexService.shared.client
        let _: Bool = try await client.mutation(
            "friends:deleteFriend",
            with: [
                "clerkId": clerkId,
                "friendId": friendId
            ]
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
    func sendInvitation(clerkId: String, friendId: String, email: String?, phone: String?) async throws -> CreateInvitationResponse {
        isLoading = true
        defer { isLoading = false }
        
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
        let result: CreateInvitationResponse = try await client.mutation(
            "invitations:createInvitation",
            with: args
        )
        
        return result
    }
}
