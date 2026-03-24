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

// MARK: - Clerk Auth Provider for Convex

/// Bridges Clerk sessions to Convex's authenticated Swift client.
final class ClerkConvexAuthProvider: ConvexMobile.AuthProvider {
    typealias T = String
    
    /// Fetch the current JWT token from Clerk.
    func fetchToken(forceRefresh: Bool) async throws -> String {
        guard let session = Clerk.shared.session else {
            throw ConvexServiceError.notAuthenticated
        }
        
        do {
            let options = Session.GetTokenOptions(template: "convex")
            
            if let tokenResource = try await session.getToken(options) {
                return tokenResource.jwt
            }
            
            if let tokenResource = try await session.getToken() {
                return tokenResource.jwt
            }
            
            throw ConvexServiceError.notAuthenticated
        } catch {
            do {
                if let tokenResource = try await session.getToken() {
                    return tokenResource.jwt
                }
            } catch {
                #if DEBUG
                print("Failed to get Clerk token: \(error)")
                #endif
            }
            throw ConvexServiceError.notAuthenticated
        }
    }
    
    func login() async throws -> String {
        try await fetchToken(forceRefresh: false)
    }
    
    func loginFromCache() async throws -> String {
        try await fetchToken(forceRefresh: false)
    }
    
    func logout() async throws {
        // Clerk handles session cleanup; nothing extra needed here.
    }
    
    func extractIdToken(from authResult: String) -> String {
        authResult
    }
}

// MARK: - Convex Service

/// Singleton service for managing Convex client and authentication
@MainActor
@Observable
final class ConvexService {
    /// Shared singleton instance
    static let shared = ConvexService()
    
    /// The Convex client instance
    let client: ConvexClientWithAuth<String>
    
    /// Auth provider for Clerk integration
    private let authProvider = ClerkConvexAuthProvider()
    
    /// Track connection status
    var isConnected = false
    
    /// Track if user is synced with Convex
    var isUserSynced = false
    
    /// Current user ID in Convex
    var currentUserId: String?
    
    /// Set to true when the deployment URL is invalid so callers can show an error.
    var hasConfigurationError = false
    
    private init() {
        let deploymentUrl = Configuration.convexDeploymentURL
        #if DEBUG
        print("🔌 ConvexService initializing with URL: \(deploymentUrl)")
        #endif
        
        if let url = URL(string: deploymentUrl),
           url.scheme == "https",
           let host = url.host,
           !host.isEmpty {
            #if DEBUG
            print("🔌 ConvexService URL validated - host: \(host)")
            #endif
        } else {
            assertionFailure("Invalid Convex deployment URL: '\(deploymentUrl)'. Check that ConvexConfiguration.xcconfig has CONVEX_HOST set correctly.")
            hasConfigurationError = true
        }
        
        client = ConvexClientWithAuth(
            deploymentUrl: deploymentUrl,
            authProvider: authProvider
        )
        
        #if DEBUG
        print("🔌 ConvexService initialized successfully")
        #endif
    }
    
    // MARK: - Authentication Helpers
    
    private func ensureAuthenticatedClient() async throws {
        switch await client.loginFromCache() {
        case .success:
            isConnected = true
        case .failure(let error):
            isConnected = false
            throw error
        }
    }
    
    // MARK: - Authentication
    
    /// Sync user with Convex after Clerk authentication
    func syncUser(clerk: Clerk) async throws {
        guard let user = clerk.user else {
            throw ConvexServiceError.notAuthenticated
        }
        
        try await ensureAuthenticatedClient()
        
        let clerkId = user.id
        let email = user.primaryEmailAddress?.emailAddress ?? ""
        
        var name = "User"
        if let firstName = user.firstName {
            name = firstName
            if let lastName = user.lastName {
                name = "\(firstName) \(lastName)"
            }
        }
        
        let phone = user.primaryPhoneNumber?.phoneNumber
        let avatarUrl = user.imageUrl
        
        // Convex v.optional() accepts undefined (omitted) but NOT null
        var args: [String: String] = [
            "clerkId": clerkId,
            "email": email,
            "name": name,
            "defaultCurrency": "USD"
        ]
        
        if let phone = phone, !phone.isEmpty {
            args["phone"] = phone
        }
        // Always send avatarUrl: use the actual URL or empty string to signal removal
        args["avatarUrl"] = avatarUrl.isEmpty ? "" : avatarUrl
        
        do {
            let userId: String = try await client.mutation(
                "users:getOrCreateUser",
                with: args
            )
            
            currentUserId = userId
            isUserSynced = true
        } catch {
            #if DEBUG
            print("📤 syncUser: Mutation failed with error: \(error)")
            #endif
            throw error
        }
    }
    
    /// Sign out and clear Convex auth
    func signOut() async {
        await client.logout()
        isConnected = false
        isUserSynced = false
        currentUserId = nil
    }
    
    /// Refresh the Convex auth token from Clerk
    func refreshToken() async throws {
        try await ensureAuthenticatedClient()
    }
    
    /// Get current auth token for API calls
    func getAuthToken() async -> String? {
        return try? await authProvider.fetchToken(forceRefresh: false)
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
