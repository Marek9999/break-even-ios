//
//  PayUpApp.swift
//  PayUp
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

@main
struct PayUpApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    /// Shared Clerk instance for authentication
    @State private var clerk = Clerk.shared
    
    /// Convex service for backend operations
    @State private var convexService = ConvexService.shared
    
    @State private var notificationManager = NotificationManager.shared
    @State private var sessionCoordinator = SessionCoordinator()
    @State private var lastForegroundRecoveryAt: Date?

    private enum SessionMaintenanceTrigger {
        case bootstrap
        case userChanged
        case foreground

        var forceTokenRefresh: Bool {
            switch self {
            case .bootstrap:
                return false
            case .userChanged:
                return true
            case .foreground:
                return false
            }
        }

        var restartSubscriptions: Bool {
            switch self {
            case .bootstrap, .foreground:
                return false
            case .userChanged:
                return true
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppAppearanceMode.current.preferredColorScheme)
                .environment(\.clerk, clerk)
                .environment(\.convexService, convexService)
                .environment(\.notificationManager, notificationManager)
                .environment(\.sessionCoordinator, sessionCoordinator)
                .task(id: sessionCoordinator.bootstrapAttempt) {
                    await bootstrapAuthentication()
                }
                .onChange(of: clerk.user?.id) { oldUserId, newUserId in
                    Task {
                        await handleAuthenticatedUserChange(from: oldUserId, to: newUserId)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await handleSceneDidBecomeActive()
                    }
                }
        }
    }
    
    @MainActor
    private func bootstrapAuthentication() async {
        sessionCoordinator.beginBootstrap()
        clerk.configure(publishableKey: Configuration.clerkPublishableKey)

        do {
            try await clerk.load()

            if let clerkId = clerk.user?.id {
                sessionCoordinator.completeBootstrap(signedIn: true, clerkId: clerkId)
                await recoverAuthenticatedSession(trigger: .bootstrap)
            } else {
                sessionCoordinator.completeBootstrap(signedIn: false)
            }
        } catch {
            await resetLocalSessionAfterBootstrapFailure()

            #if DEBUG
            print("❌ Failed to bootstrap Clerk session: \(error)")
            #endif
        }
    }

    @MainActor
    private func resetLocalSessionAfterBootstrapFailure() async {
        try? await clerk.signOut()
        notificationManager.handleSignedOutLocally()
        await convexService.signOut()
        sessionCoordinator.completeBootstrap(signedIn: false)
    }

    @MainActor
    private func handleAuthenticatedUserChange(from oldUserId: String?, to newUserId: String?) async {
        guard sessionCoordinator.authPhase != .bootstrapping else { return }

        if let clerkId = newUserId {
            sessionCoordinator.completeBootstrap(signedIn: true, clerkId: clerkId)
            await recoverAuthenticatedSession(trigger: .userChanged)
        } else if oldUserId != nil {
            notificationManager.handleSignedOutLocally()
            sessionCoordinator.completeBootstrap(signedIn: false)
            await convexService.signOut()
        }
    }

    @MainActor
    private func handleSceneDidBecomeActive() async {
        guard sessionCoordinator.authPhase == .signedIn, clerk.user != nil else { return }

        if let lastForegroundRecoveryAt,
           Date().timeIntervalSince(lastForegroundRecoveryAt) < 1.0 {
            return
        }

        lastForegroundRecoveryAt = Date()
        await recoverAuthenticatedSession(trigger: .foreground)
    }

    @MainActor
    private func recoverAuthenticatedSession(trigger: SessionMaintenanceTrigger) async {
        do {
            try await convexService.recoverAuthenticatedSession(
                clerk: clerk,
                forceTokenRefresh: trigger.forceTokenRefresh,
                restartSubscriptions: trigger.restartSubscriptions
            )
            
            if let clerkId = clerk.user?.id {
                await notificationManager.handleAuthenticatedSession(clerkId: clerkId)
            }
        } catch {
            let message = SessionProvisioning.userFacingMessage(for: error)
            sessionCoordinator.markProvisioningFailed(message: message)

            #if DEBUG
            print("❌ Failed to recover authenticated session (\(trigger)): \(error)")
            #endif
        }
    }
}
