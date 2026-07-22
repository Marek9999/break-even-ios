//
//  RootView.swift
//  PayUp
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
        "\(clerk.user?.id ?? "signed-out"):\(convexService.sessionState):\(convexService.isUserSynced):\(convexService.subscriptionRestartToken)"
    }

    private var needsOnboarding: Bool? {
        guard let currentUser = sessionCoordinator.currentUser else { return nil }
        return !currentUser.hasCompletedOnboarding
    }

    private var startupRecoveryMessage: String? {
        sessionCoordinator.currentUserErrorMessage ?? convexService.lastRecoveryError
    }

    private var shouldShowOnboarding: Bool {
        sessionCoordinator.currentUserLoadState == .loaded && needsOnboarding == true
    }

    private var shouldShowMainShell: Bool {
        sessionCoordinator.currentUserLoadState == .loaded && needsOnboarding == false
    }

    private var shouldShowProvisioningRecovery: Bool {
        if case .failed = sessionCoordinator.currentUserLoadState {
            return startupRecoveryMessage != nil
        }
        // Sync/provisioning failed before the subscription started.
        return !convexService.isUserSynced && startupRecoveryMessage != nil
    }
    
    var body: some View {
        Group {
            switch sessionCoordinator.authPhase {
            case .bootstrapping:
                bootstrapView
            case .signedOut:
                LoginView()
            case .signedIn:
                if shouldShowOnboarding {
                    onboardingGate
                    .transition(.move(edge: .trailing))
                } else {
                    authenticatedContent
                }
            }
        }
        .task(id: currentUserSubscriptionKey) {
            guard SessionProvisioning.shouldStartCurrentUserSubscription(
                authPhase: sessionCoordinator.authPhase,
                sessionState: convexService.sessionState,
                isUserSynced: convexService.isUserSynced
            ), let clerkId = clerk.user?.id else {
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
        } else if shouldShowProvisioningRecovery,
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

    private var onboardingGate: some View {
        OnboardingFlowView(
            onClose: {},
            startsAtProfileSetup: true,
            currentUser: sessionCoordinator.currentUser
        ) {
            try await convexService.recoverAuthenticatedSession(
                clerk: clerk,
                forceTokenRefresh: true,
                restartSubscriptions: true
            )
        }
    }

    private func authRecoveryView(message: String) -> some View {
        ContentUnavailableView(
            "Couldn't Finish Setup",
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
                                forceTokenRefresh: true,
                                restartSubscriptions: true
                            )
                        } catch {
                            sessionCoordinator.markProvisioningFailed(
                                message: SessionProvisioning.userFacingMessage(for: error)
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
}
