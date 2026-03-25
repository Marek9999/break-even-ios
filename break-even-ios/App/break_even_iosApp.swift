//
//  break_even_iosApp.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

@main
struct break_even_iosApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    /// Shared Clerk instance for authentication
    @State private var clerk = Clerk.shared
    
    /// Convex service for backend operations
    @State private var convexService = ConvexService.shared
    
    @State private var notificationManager = NotificationManager.shared
    @State private var lastForegroundRecoveryAt: Date?
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(\.clerk, clerk)
                .environment(\.convexService, convexService)
                .environment(\.notificationManager, notificationManager)
                .task {
                    clerk.configure(publishableKey: Configuration.clerkPublishableKey)
                    try? await clerk.load()
                    
                    if clerk.session != nil {
                        await recoverAuthenticatedSession(reason: "launch", forceTokenRefresh: false)
                    }
                }
                .onChange(of: clerk.session) { _, newSession in
                    Task {
                        if newSession != nil {
                            await recoverAuthenticatedSession(reason: "session-changed", forceTokenRefresh: true)
                        } else {
                            notificationManager.handleSignedOutLocally()
                            await convexService.signOut()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, clerk.session != nil else { return }
                    Task {
                        await recoverAuthenticatedSession(reason: "scene-active", forceTokenRefresh: true)
                    }
                }
        }
    }
    
    @MainActor
    private func recoverAuthenticatedSession(reason: String, forceTokenRefresh: Bool) async {
        if let lastForegroundRecoveryAt,
           Date().timeIntervalSince(lastForegroundRecoveryAt) < 1.0,
           reason == "scene-active" {
            return
        }
        
        if reason == "scene-active" {
            lastForegroundRecoveryAt = Date()
        }
        
        do {
            try await convexService.recoverAuthenticatedSession(
                clerk: clerk,
                forceTokenRefresh: forceTokenRefresh
            )
            
            if let clerkId = clerk.user?.id {
                await notificationManager.handleAuthenticatedSession(clerkId: clerkId)
            }
        } catch {
            #if DEBUG
            print("❌ Failed to recover authenticated session (\(reason)): \(error)")
            #endif
        }
    }
}
