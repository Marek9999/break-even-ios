//
//  break_even_iosApp.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import UIKit

// MARK: - Keyboard Pre-warming

/// Pre-warms the iOS keyboard to eliminate first-focus lag.
/// iOS lazily initializes the keyboard infrastructure on first use, which causes
/// a noticeable delay ("System gesture gate timed out" errors). This function
/// triggers that initialization at app launch instead of on first user interaction.
enum KeyboardPrewarmer {
    private static var hasPrewarmed = false
    
    static func prewarm() {
        guard !hasPrewarmed else { return }
        hasPrewarmed = true
        
        // Get the key window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        
        // Create a hidden text field to trigger keyboard initialization
        // This eliminates the first-focus lag on TextFields
        let hiddenField = UITextField(frame: .zero)
        hiddenField.autocorrectionType = .no
        hiddenField.spellCheckingType = .no
        
        window.addSubview(hiddenField)
        hiddenField.becomeFirstResponder()
        hiddenField.resignFirstResponder()
        hiddenField.removeFromSuperview()
    }
}

@main
struct break_even_iosApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    
    /// Shared Clerk instance for authentication
    @State private var clerk = Clerk.shared
    
    /// Convex service for backend operations
    @State private var convexService = ConvexService.shared
    
    @State private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(\.clerk, clerk)
                .environment(\.convexService, convexService)
                .environment(\.notificationManager, notificationManager)
                .onAppear {
                    // Pre-warm keyboard to eliminate first TextField focus lag
                    // This must be called after the window exists
                    KeyboardPrewarmer.prewarm()
                }
                .task {
                    clerk.configure(publishableKey: Configuration.clerkPublishableKey)
                    try? await clerk.load()
                    
                    if clerk.session != nil {
                        do {
                            try await convexService.syncUser(clerk: clerk)
                            if let clerkId = clerk.user?.id {
                                await notificationManager.handleAuthenticatedSession(clerkId: clerkId)
                            }
                        } catch {
                            #if DEBUG
                            print("❌ Failed to sync user on launch: \(error)")
                            #endif
                        }
                    }
                }
                .onChange(of: clerk.session) { _, newSession in
                    Task {
                        if newSession != nil {
                            do {
                                try await convexService.syncUser(clerk: clerk)
                                if let clerkId = clerk.user?.id {
                                    await notificationManager.handleAuthenticatedSession(clerkId: clerkId)
                                }
                            } catch {
                                #if DEBUG
                                print("❌ Failed to sync user with Convex: \(error)")
                                #endif
                            }
                        } else {
                            notificationManager.handleSignedOutLocally()
                            await convexService.signOut()
                        }
                    }
                }
        }
    }
}
