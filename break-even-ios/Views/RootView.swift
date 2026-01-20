//
//  RootView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

/// Root view that handles authentication gating
/// Users must sign in before accessing any app content
struct RootView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    var body: some View {
        Group {
            if clerk.user != nil {
                // User is authenticated - show main app content
                MainTabView()
                    .task {
                        // Sync user with Convex when authenticated
                        do {
                            try await convexService.syncUser(clerk: clerk)
                        } catch {
                            print("Failed to sync user with Convex: \(error)")
                        }
                    }
            } else {
                // User is not authenticated - show auth view
                AuthenticationGateView()
            }
        }
    }
}

/// View shown when user is not authenticated
/// Displays a welcome screen with sign-in button
struct AuthenticationGateView: View {
    @State private var isAuthPresented = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App Logo/Icon
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.accent)
            
            // Welcome Text
            VStack(spacing: 12) {
                Text("Break Even")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Split expenses with friends and family")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Sign In Button
            Button {
                isAuthPresented = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $isAuthPresented) {
            AuthView()
                .interactiveDismissDisabled()
        }
        .onAppear {
            // Automatically present auth view when this view appears
            isAuthPresented = true
        }
    }
}

#Preview {
    RootView()
}
