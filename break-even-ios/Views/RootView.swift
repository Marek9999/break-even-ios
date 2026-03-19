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
    
    var body: some View {
        Group {
            if clerk.user != nil {
                MainTabView()
                    .task {
                        do {
                            try await convexService.syncUser(clerk: clerk)
                        } catch {
                            #if DEBUG
                            print("Failed to sync user with Convex: \(error)")
                            #endif
                        }
                    }
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    RootView()
}
