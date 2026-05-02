//
//  RootView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

struct RootView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    @Environment(\.sessionCoordinator) private var sessionCoordinator

    private var currentUserSubscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.sessionState):\(convexService.subscriptionRestartToken)"
    }

    private var needsUsername: Bool? {
        guard let currentUser = sessionCoordinator.currentUser else { return nil }
        return currentUser.username == nil || currentUser.username?.isEmpty == true
    }

    private var startupRecoveryMessage: String? {
        sessionCoordinator.currentUserErrorMessage ?? convexService.lastRecoveryError
    }

    private var shouldShowUsernameSetup: Bool {
        sessionCoordinator.currentUserLoadState == .loaded && needsUsername == true
    }

    private var shouldShowMainShell: Bool {
        sessionCoordinator.currentUserLoadState == .loaded && needsUsername == false
    }
    
    var body: some View {
        Group {
            switch sessionCoordinator.authPhase {
            case .bootstrapping:
                bootstrapView
            case .signedOut:
                LoginView()
            case .signedIn:
                if shouldShowUsernameSetup {
                    UsernameSetupView {
                        Task {
                            try? await convexService.recoverAuthenticatedSession(
                                clerk: clerk,
                                forceTokenRefresh: true,
                                restartSubscriptions: false
                            )
                        }
                    }
                    .transition(.move(edge: .trailing))
                } else {
                    authenticatedContent
                }
            }
        }
        .task(id: currentUserSubscriptionKey) {
            guard sessionCoordinator.authPhase == .signedIn,
                  let clerkId = clerk.user?.id,
                  convexService.sessionState == .authenticated else {
                return
            }

            sessionCoordinator.startCurrentUserSubscription(
                clerkId: clerkId,
                restartToken: convexService.subscriptionRestartToken,
                client: convexService.client
            )
        }
    }

    @ViewBuilder
    private var bootstrapView: some View {
        if let message = sessionCoordinator.bootstrapErrorMessage {
            ContentUnavailableView(
                "Couldn't Restore Your Session",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text(message)
            )
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Try Again") {
                        sessionCoordinator.retryBootstrap()
                    }
                }
            }
        } else {
            launchHoldScreen
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if shouldShowMainShell {
            MainTabView()
        } else if case .failed = sessionCoordinator.currentUserLoadState,
                  let message = startupRecoveryMessage {
            authRecoveryView(message: message)
        } else {
            launchHoldScreen
        }
    }

    private var launchHoldScreen: some View {
        Color.black
            .ignoresSafeArea()
    }

    private func authRecoveryView(message: String) -> some View {
        ContentUnavailableView(
            "Reconnecting",
            systemImage: "arrow.triangle.2.circlepath",
            description: Text(message)
        )
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Try Again") {
                    Task {
                        try? await convexService.recoverAuthenticatedSession(
                            clerk: clerk,
                            forceTokenRefresh: true,
                            restartSubscriptions: false
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
}
