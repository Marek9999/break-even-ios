import SwiftUI
import ConvexMobile
internal import Combine

@MainActor
@Observable
final class SessionCoordinator {
    enum AuthPhase: Equatable {
        case bootstrapping
        case signedOut
        case signedIn
    }

    enum UserLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var authPhase: AuthPhase = .bootstrapping
    var bootstrapErrorMessage: String?
    var bootstrapAttempt = 0

    var currentUser: ConvexUser?
    var currentUserLoadState: UserLoadState = .idle
    var currentUserErrorMessage: String?

    private var currentUserSubscription: Task<Void, Never>?
    private var currentUserSubscriptionKey: String?

    func beginBootstrap() {
        authPhase = .bootstrapping
        bootstrapErrorMessage = nil
    }

    func completeBootstrap(signedIn: Bool, clerkId: String? = nil) {
        authPhase = signedIn ? .signedIn : .signedOut
        bootstrapErrorMessage = nil

        if !signedIn {
            stopCurrentUserSubscription(clearData: true)
        } else if clerkId == nil {
            currentUserLoadState = .idle
        }
    }

    func failBootstrap(message: String) {
        authPhase = .bootstrapping
        bootstrapErrorMessage = message
    }

    func retryBootstrap() {
        bootstrapAttempt += 1
        beginBootstrap()
    }

    func startCurrentUserSubscription(
        clerkId: String,
        restartToken: Int,
        client: ConvexClientWithAuth<String>
    ) {
        let subscriptionKey = "\(clerkId):\(restartToken)"
        guard currentUserSubscriptionKey != subscriptionKey else { return }

        currentUserSubscription?.cancel()
        currentUserSubscriptionKey = subscriptionKey
        currentUserErrorMessage = nil

        if currentUser == nil {
            currentUserLoadState = .loading
        }

        currentUserSubscription = Task {
            do {
                let subscription = client.subscribe(
                    to: "users:getCurrentUser",
                    with: ["clerkId": clerkId],
                    yielding: ConvexUser?.self
                )
                .values

                for try await user in subscription {
                    if Task.isCancelled { break }
                    currentUser = user
                    currentUserErrorMessage = nil
                    currentUserLoadState = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                currentUserErrorMessage = error.localizedDescription
                currentUserLoadState = .failed(error.localizedDescription)
            }
        }
    }

    func stopCurrentUserSubscription(clearData: Bool) {
        currentUserSubscription?.cancel()
        currentUserSubscription = nil
        currentUserSubscriptionKey = nil
        currentUserErrorMessage = nil

        if clearData {
            currentUser = nil
            currentUserLoadState = .idle
        }
    }
}

private struct SessionCoordinatorKey: EnvironmentKey {
    static let defaultValue = SessionCoordinator()
}

extension EnvironmentValues {
    var sessionCoordinator: SessionCoordinator {
        get { self[SessionCoordinatorKey.self] }
        set { self[SessionCoordinatorKey.self] = newValue }
    }
}
