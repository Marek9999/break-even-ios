//
//  ConvexService.swift
//  PayUp
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import SwiftUI
import ConvexMobile
import Clerk
internal import Combine

enum ConvexSessionState: Equatable {
    case loading
    case authenticated
    case unauthenticated
}

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
            let options = Session.GetTokenOptions(
                template: "convex",
                skipCache: forceRefresh
            )
            
            if let tokenResource = try await session.getToken(options) {
                return tokenResource.jwt
            }
            
            let fallbackOptions = Session.GetTokenOptions(skipCache: forceRefresh)
            if let tokenResource = try await session.getToken(fallbackOptions) {
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
        try await fetchToken(forceRefresh: true)
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
    
    /// Auth state reported by Convex's authenticated client.
    var sessionState: ConvexSessionState = .loading
    
    /// Track if user is synced with Convex
    var isUserSynced = false
    
    /// Current user ID in Convex
    var currentUserId: String?
    
    /// Set to true when the deployment URL is invalid so callers can show an error.
    var hasConfigurationError = false
    
    /// Human-readable websocket state for debug and recovery UI.
    var webSocketStatus = "connecting"
    
    /// Recovery UI should treat this as an in-flight auth refresh.
    var isRecoveringSession = false
    
    /// Exposes the latest recovery error without forcing screens to infer from empty data.
    var lastRecoveryError: String?
    
    /// Increment to restart view subscriptions after a successful recovery.
    var subscriptionRestartToken = 0
    
    private var authStateTask: Task<Void, Never>?
    private var webSocketStateTask: Task<Void, Never>?
    private var activeRecoveryTask: Task<Bool, Error>?
    
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
        
        observeAuthState()
        observeWebSocketState()
    }
    
    // MARK: - Authentication Helpers
    
    private func ensureAuthenticatedClient() async throws {
        switch await client.loginFromCache() {
        case .success:
            isConnected = true
            lastRecoveryError = nil
        case .failure(let error):
            isConnected = false
            throw error
        }
    }
    
    private func observeAuthState() {
        authStateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in self.client.authState.values {
                if Task.isCancelled { break }
                switch state {
                case .loading:
                    self.sessionState = .loading
                case .authenticated:
                    self.sessionState = .authenticated
                    self.lastRecoveryError = nil
                case .unauthenticated:
                    self.sessionState = .unauthenticated
                    self.isConnected = false
                }
                
                #if DEBUG
                print("🔐 Convex auth state -> \(self.sessionState)")
                #endif
            }
        }
    }
    
    private func observeWebSocketState() {
        webSocketStateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in self.client.watchWebSocketState().values {
                if Task.isCancelled { break }
                self.webSocketStatus = String(describing: state)
                
                #if DEBUG
                print("🔌 Convex websocket state -> \(self.webSocketStatus)")
                #endif
            }
        }
    }
    
    // MARK: - Authentication
    
    /// Sync user with Convex after Clerk authentication
    func syncUser(
        clerk: Clerk,
        avatarUrlOverride: String? = nil,
        usesAvatarUrlOverride: Bool = false
    ) async throws {
        guard let user = clerk.user else {
            throw ConvexServiceError.notAuthenticated
        }
        
        try await ensureAuthenticatedClient()
        
        let clerkId = user.id
        // Prefer Clerk primary email; fall back to a stable placeholder so Apple
        // Sign In without an email address can still provision a Convex user.
        let email = SessionProvisioning.resolvedEmail(
            clerkPrimaryEmail: user.primaryEmailAddress?.emailAddress,
            clerkId: clerkId
        )
        
        var name = "User"
        if let firstName = user.firstName {
            name = firstName
            if let lastName = user.lastName {
                name = "\(firstName) \(lastName)"
            }
        }
        
        let phone = user.primaryPhoneNumber?.phoneNumber
        let avatarUrl = usesAvatarUrlOverride ? (avatarUrlOverride ?? "") : user.imageUrl
        
        // Convex v.optional() accepts undefined (omitted) but NOT null
        var args: [String: String] = [
            "clerkId": clerkId,
            "email": email,
            "name": name,
            "defaultCurrency": SupportedCurrency.deviceDefault.rawValue
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
            lastRecoveryError = nil
        } catch {
            isUserSynced = false
            #if DEBUG
            print("📤 syncUser: Mutation failed with error: \(error)")
            #endif
            throw error
        }
    }
    
    /// Revalidate Convex auth and resubscribe consumers only when necessary.
    @discardableResult
    func recoverAuthenticatedSession(
        clerk: Clerk,
        forceTokenRefresh: Bool = true,
        restartSubscriptions: Bool = true
    ) async throws -> Bool {
        if let activeRecoveryTask {
            return try await activeRecoveryTask.value
        }

        let recoveryTask = Task<Bool, Error> { @MainActor in
            guard clerk.session != nil, clerk.user != nil else {
                await signOut()
                return true
            }

            // Never skip provisioning: cold launch leaves isUserSynced false even
            // when the Convex client still reports an authenticated JWT session.
            if !forceTokenRefresh,
               sessionState == .authenticated,
               isUserSynced,
               lastRecoveryError == nil {
                return false
            }

            isRecoveringSession = true
            lastRecoveryError = nil

            #if DEBUG
            print("🔄 Starting Convex recovery (forceTokenRefresh: \(forceTokenRefresh), restartSubscriptions: \(restartSubscriptions))")
            #endif

            defer {
                isRecoveringSession = false
                activeRecoveryTask = nil
            }

            do {
                if forceTokenRefresh {
                    _ = try await authProvider.fetchToken(forceRefresh: true)
                }

                try await syncUser(clerk: clerk)

                if restartSubscriptions {
                    subscriptionRestartToken += 1
                }

                #if DEBUG
                print("✅ Convex recovery finished")
                #endif

                return restartSubscriptions
            } catch {
                isConnected = false
                isUserSynced = false
                lastRecoveryError = SessionProvisioning.userFacingMessage(for: error)

                #if DEBUG
                print("❌ Convex recovery failed: \(error)")
                #endif

                throw error
            }
        }

        activeRecoveryTask = recoveryTask
        return try await recoveryTask.value
    }
    
    /// Sign out and clear Convex auth
    func signOut() async {
        activeRecoveryTask?.cancel()
        activeRecoveryTask = nil
        await client.logout()
        isConnected = false
        sessionState = .unauthenticated
        isUserSynced = false
        currentUserId = nil
        lastRecoveryError = nil
        isRecoveringSession = false
        subscriptionRestartToken += 1
    }
    
    /// Refresh the Convex auth token from Clerk
    func refreshToken() async throws {
        _ = try await authProvider.fetchToken(forceRefresh: true)
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

/// Shared first-login / recovery helpers for Convex user provisioning.
enum SessionProvisioning {
    static let accountSetupFailedMessage =
        "Couldn't finish setting up your account. Please try again."

    /// Whether the current-user subscription is allowed to start.
    static func shouldStartCurrentUserSubscription(
        authPhase: SessionCoordinator.AuthPhase,
        sessionState: ConvexSessionState,
        isUserSynced: Bool
    ) -> Bool {
        authPhase == .signedIn && sessionState == .authenticated && isUserSynced
    }

    static func resolvedEmail(clerkPrimaryEmail: String?, clerkId: String) -> String {
        if let email = clerkPrimaryEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        return placeholderEmail(for: clerkId)
    }

    static func placeholderEmail(for clerkId: String) -> String {
        // Keep alphanumerics only for a valid local-part.
        let local = clerkId.lowercased().filter { $0.isLetter || $0.isNumber }
        return "user+\(local.isEmpty ? "unknown" : local)@accounts.payupsplits.app"
    }

    static func userFacingMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let lowered = raw.lowercased()
        if lowered.contains("uniffi")
            || lowered.contains("servererror")
            || lowered.contains("user not found")
            || lowered.contains("not authenticated")
            || lowered.contains("could not connect")
            || lowered.contains("websocket") {
            return accountSetupFailedMessage
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accountSetupFailedMessage
        }
        // Keep short, non-technical messages; rewrite anything that looks like a stack/client dump.
        if raw.count > 120 || raw.contains("[Request ID:") || raw.contains("ClientError") {
            return accountSetupFailedMessage
        }
        return raw
    }
}
