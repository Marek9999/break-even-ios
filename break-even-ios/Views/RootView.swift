//
//  RootView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct RootView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var needsUsername: Bool? = nil
    @State private var userSubscription: Task<Void, Never>?
    @State private var authErrorMessage: String?
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    private var shouldBlockAuthenticatedContent: Bool {
        clerk.user != nil && convexService.sessionState != .authenticated
    }
    
    var body: some View {
        Group {
            if clerk.user != nil {
                if shouldBlockAuthenticatedContent {
                    authRecoveryView
                } else if needsUsername == true {
                    UsernameSetupView {
                        withAnimation { needsUsername = false }
                    }
                    .transition(.move(edge: .trailing))
                } else if needsUsername == false {
                    MainTabView()
                } else {
                    ProgressView()
                }
            } else {
                LoginView()
            }
        }
        .task(id: subscriptionKey) {
            guard let clerkUser = clerk.user else {
                needsUsername = nil
                authErrorMessage = nil
                userSubscription?.cancel()
                return
            }
            
            guard convexService.sessionState == .authenticated else {
                needsUsername = nil
                return
            }
            
            do {
                try await convexService.syncUser(clerk: clerk)
            } catch {
                authErrorMessage = error.localizedDescription
                #if DEBUG
                print("Failed to sync user with Convex: \(error)")
                #endif
            }
            
            authErrorMessage = nil
            userSubscription?.cancel()
            userSubscription = Task {
                do {
                    let subscription = convexService.client.subscribe(
                        to: "users:getCurrentUser",
                        with: ["clerkId": clerkUser.id],
                        yielding: ConvexUser?.self
                    )
                    .values
                    
                    for try await user in subscription {
                        if Task.isCancelled { break }
                        authErrorMessage = nil
                        let hasUsername = user?.username != nil && !(user?.username?.isEmpty ?? true)
                        if needsUsername == nil {
                            needsUsername = !hasUsername
                        } else if hasUsername {
                            needsUsername = false
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    authErrorMessage = error.localizedDescription
                    needsUsername = nil
                    
                    #if DEBUG
                    print("users:getCurrentUser subscription failed: \(error)")
                    #endif
                    
                    do {
                        try await convexService.recoverAuthenticatedSession(
                            clerk: clerk,
                            forceTokenRefresh: true
                        )
                    } catch {
                        #if DEBUG
                        print("Convex recovery retry from RootView failed: \(error)")
                        #endif
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var authRecoveryView: some View {
        if let message = authErrorMessage {
            ContentUnavailableView(
                "Reconnecting",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text(message)
            )
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Try Again") {
                        Task {
                            do {
                                try await convexService.recoverAuthenticatedSession(
                                    clerk: clerk,
                                    forceTokenRefresh: true
                                )
                            } catch {
                                authErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        } else if let message = convexService.lastRecoveryError {
            ContentUnavailableView(
                "Reconnecting",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text(message)
            )
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Try Again") {
                        Task {
                            do {
                                try await convexService.recoverAuthenticatedSession(
                                    clerk: clerk,
                                    forceTokenRefresh: true
                                )
                            } catch {
                                authErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView("Restoring your data...")
        }
    }
}

#Preview {
    RootView()
}
