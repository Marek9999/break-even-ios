//
//  ConvexService.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import SwiftUI
import ConvexMobile
import Clerk
internal import Combine

// MARK: - Clerk Auth Provider for Convex

/// Custom AuthProvider that integrates Clerk authentication with Convex
final class ClerkAuthProvider: AuthProvider {
    private let authStateSubject = CurrentValueSubject<AuthState, Never>(.unauthenticated)
    private var cancellables = Set<AnyCancellable>()
    
    var authState: AnyPublisher<AuthState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }
    
    /// Fetch the current JWT token from Clerk
    func fetchToken(forceRefresh: Bool) async -> String? {
        guard let session = Clerk.shared.session else {
            return nil
        }
        
        do {
            // Try to get token with Convex template first
            let options = Session.GetTokenOptions(template: "convex")
            
            if let tokenResource = try await session.getToken(options) {
                return tokenResource.jwt
            }
            
            // Fallback to default session token
            if let tokenResource = try await session.getToken() {
                return tokenResource.jwt
            }
            
            return nil
        } catch {
            // If convex template doesn't exist, try default token
            do {
                if let tokenResource = try await session.getToken() {
                    return tokenResource.jwt
                }
            } catch {
                print("Failed to get Clerk token: \(error)")
            }
            return nil
        }
    }
    
    /// Login is handled by Clerk, not by this provider
    func login() async throws {
        // Clerk handles login externally via AuthView
        // This is called after Clerk login to sync state
        if let token = await fetchToken(forceRefresh: false) {
            authStateSubject.send(.authenticated(token: token))
        }
    }
    
    /// Logout - clear auth state
    func logout() {
        authStateSubject.send(.unauthenticated)
    }
    
    /// Update auth state based on Clerk session
    func updateAuthState() async {
        if let token = await fetchToken(forceRefresh: false) {
            authStateSubject.send(.authenticated(token: token))
        } else {
            authStateSubject.send(.unauthenticated)
        }
    }
}

// MARK: - Auth State

enum AuthState {
    case unauthenticated
    case authenticated(token: String)
    case loading
}

// MARK: - Auth Provider Protocol

protocol AuthProvider {
    var authState: AnyPublisher<AuthState, Never> { get }
    func fetchToken(forceRefresh: Bool) async -> String?
    func login() async throws
    func logout()
}

// MARK: - Convex Service

/// Singleton service for managing Convex client and authentication
@MainActor
@Observable
final class ConvexService {
    /// Shared singleton instance
    static let shared = ConvexService()
    
    /// The Convex client instance
    let client: ConvexClient
    
    /// Auth provider for Clerk integration
    private let authProvider = ClerkAuthProvider()
    
    /// Track connection status
    var isConnected = false
    
    /// Track if user is synced with Convex
    var isUserSynced = false
    
    /// Current user ID in Convex
    var currentUserId: String?
    
    /// Current auth token
    private var currentToken: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Get and validate the deployment URL
        let deploymentUrl = Configuration.convexDeploymentURL
        print("🔌 ConvexService initializing with URL: \(deploymentUrl)")
        
        // Validate URL format
        guard let url = URL(string: deploymentUrl),
              url.scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            fatalError("Invalid Convex deployment URL: '\(deploymentUrl)'. Check that ConvexConfiguration.xcconfig has CONVEX_HOST set correctly.")
        }
        
        print("🔌 ConvexService URL validated - host: \(host)")
        client = ConvexClient(deploymentUrl: deploymentUrl)
        
        // Subscribe to auth state changes
        authProvider.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    await self?.handleAuthStateChange(state)
                }
            }
            .store(in: &cancellables)
        
        print("🔌 ConvexService initialized successfully")
    }
    
    // MARK: - Auth State Handling
    
    private func handleAuthStateChange(_ state: AuthState) async {
        switch state {
        case .unauthenticated:
            currentToken = nil
            isConnected = false
            isUserSynced = false
            currentUserId = nil
        case .authenticated(let token):
            currentToken = token
            isConnected = true
        case .loading:
            break
        }
    }
    
    // MARK: - Authentication
    
    /// Sync user with Convex after Clerk authentication
    func syncUser(clerk: Clerk) async throws {
        print("📤 syncUser: Starting...")
        
        guard let user = clerk.user else {
            print("📤 syncUser: No user found in Clerk")
            throw ConvexServiceError.notAuthenticated
        }
        
        // Update auth provider state
        await authProvider.updateAuthState()
        
        // Get user details from Clerk
        let clerkId = user.id
        let email = user.primaryEmailAddress?.emailAddress ?? ""
        
        // Construct full name from firstName and lastName
        var name = "User"
        if let firstName = user.firstName {
            name = firstName
            if let lastName = user.lastName {
                name = "\(firstName) \(lastName)"
            }
        }
        
        let phone = user.primaryPhoneNumber?.phoneNumber
        let avatarUrl = user.imageUrl
        
        print("📤 syncUser: clerkId=\(clerkId), email=\(email), name=\(name)")
        
        // Build arguments - only include optional fields if they have values
        // Convex v.optional() accepts undefined (omitted) but NOT null
        var args: [String: String] = [
            "clerkId": clerkId,
            "email": email,
            "name": name,
            "defaultCurrency": "USD"
        ]
        
        // Only add optional fields if they have values
        if let phone = phone, !phone.isEmpty {
            args["phone"] = phone
        }
        if !avatarUrl.isEmpty {
            args["avatarUrl"] = avatarUrl
        }
        
        print("📤 syncUser: Sending args: \(args.keys.joined(separator: ", "))")
        
        // Call Convex to get or create user
        do {
            let userId: String = try await client.mutation(
                "users:getOrCreateUser",
                with: args
            )
            
            print("📤 syncUser: Success! userId=\(userId)")
            currentUserId = userId
            isUserSynced = true
        } catch {
            print("📤 syncUser: Mutation failed with error: \(error)")
            throw error
        }
    }
    
    /// Sign out and clear Convex auth
    func signOut() async {
        authProvider.logout()
        isConnected = false
        isUserSynced = false
        currentUserId = nil
    }
    
    /// Refresh the Convex auth token from Clerk
    func refreshToken() async throws {
        await authProvider.updateAuthState()
    }
    
    /// Get current auth token for API calls
    func getAuthToken() async -> String? {
        return await authProvider.fetchToken(forceRefresh: false)
    }
    
    /// Seed sample data for the current user (for development/testing)
    func seedSampleData(clerkId: String) async throws -> String {
        struct SeedResult: Decodable {
            let message: String
        }
        
        let result: SeedResult = try await client.mutation(
            "seed:seedForCurrentUser",
            with: ["clerkId": clerkId]
        )
        
        return result.message
    }
}

// MARK: - Environment Key

private struct ConvexServiceKey: EnvironmentKey {
    static let defaultValue: ConvexService = ConvexService.shared
}

extension EnvironmentValues {
    var convexService: ConvexService {
        get { self[ConvexServiceKey.self] }
        set { self[ConvexServiceKey.self] = newValue }
    }
}

// MARK: - Errors

enum ConvexServiceError: LocalizedError {
    case notAuthenticated
    case syncFailed
    case queryFailed(String)
    case mutationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .syncFailed:
            return "Failed to sync user with backend"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .mutationFailed(let message):
            return "Mutation failed: \(message)"
        }
    }
}
