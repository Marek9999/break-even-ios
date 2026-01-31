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
    /// Shared Clerk instance for authentication
    @State private var clerk = Clerk.shared
    
    /// Convex service for backend operations
    @State private var convexService = ConvexService.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.clerk, clerk)
                .environment(\.convexService, convexService)
                .onAppear {
                    // Pre-warm keyboard to eliminate first TextField focus lag
                    // This must be called after the window exists
                    KeyboardPrewarmer.prewarm()
                }
                .task {
                    // Configure Clerk
                    print("🔧 Configuring Clerk...")
                    clerk.configure(publishableKey: Configuration.clerkPublishableKey)
                    print("🔧 Convex URL: \(Configuration.convexDeploymentURL)")
                    try? await clerk.load()
                    print("🔧 Clerk loaded, session: \(clerk.session != nil ? "exists" : "nil")")
                    
                    // If already logged in, sync user
                    if clerk.session != nil {
                        print("🔧 Session exists on launch, syncing user...")
                        do {
                            try await convexService.syncUser(clerk: clerk)
                            print("✅ User synced with Convex successfully (on launch)")
                        } catch {
                            print("❌ Failed to sync user on launch: \(error)")
                        }
                    }
                }
                .onChange(of: clerk.session) { oldSession, newSession in
                    // Sync with Convex when auth state changes
                    print("🔄 Session changed: \(oldSession != nil) -> \(newSession != nil)")
                    Task {
                        if newSession != nil {
                            do {
                                print("🔄 Syncing user with Convex...")
                                try await convexService.syncUser(clerk: clerk)
                                print("✅ User synced with Convex successfully")
                            } catch {
                                print("❌ Failed to sync user with Convex: \(error)")
                            }
                        } else {
                            print("🔄 Signing out...")
                            await convexService.signOut()
                        }
                    }
                }
        }
    }
}
