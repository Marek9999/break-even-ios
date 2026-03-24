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
    
    var body: some View {
        Group {
            if clerk.user != nil {
                if needsUsername == true {
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
        .task(id: clerk.user?.id) {
            guard let clerkUser = clerk.user else {
                needsUsername = nil
                userSubscription?.cancel()
                return
            }
            
            do {
                try await convexService.syncUser(clerk: clerk)
            } catch {
                #if DEBUG
                print("Failed to sync user with Convex: \(error)")
                #endif
            }
            
            userSubscription?.cancel()
            userSubscription = Task {
                let subscription = convexService.client.subscribe(
                    to: "users:getCurrentUser",
                    with: ["clerkId": clerkUser.id],
                    yielding: ConvexUser?.self
                )
                .replaceError(with: nil)
                .values
                
                for await user in subscription {
                    if Task.isCancelled { break }
                    let hasUsername = user?.username != nil && !(user?.username?.isEmpty ?? true)
                    if needsUsername == nil {
                        needsUsername = !hasUsername
                    } else if hasUsername {
                        needsUsername = false
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
}
