//
//  MainTabView.swift
//  PayUp
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

/// Main tab view containing all primary app sections
struct MainTabView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    @Environment(\.notificationManager) private var notificationManager
    @Environment(\.sessionCoordinator) private var sessionCoordinator
    
    @State private var isProfileSheetPresented = false
    @State private var isProfileSheetDetailShowing = false
    
    @State private var isActivitySheetPresented = false
    @State private var historyRequest: HomeHistoryRequest?
    
    @State private var activityViewModel = ActivityViewModel()
    @State private var profileSheetNavigationRequest: ProfileExternalNavigationRequest?
    
    private var userAvatarUrl: String? {
        sessionCoordinator.currentUser?.avatarUrl ?? clerk.user?.imageUrl
    }
    
    private var userInitials: String {
        if let user = clerk.user {
            let first = user.firstName?.first.map(String.init) ?? ""
            let last = user.lastName?.first.map(String.init) ?? ""
            if !first.isEmpty || !last.isEmpty {
                return "\(first)\(last)"
            }
        }
        return "U"
    }
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    var body: some View {
        HomeView(
            userAvatarUrl: userAvatarUrl,
            userInitials: userInitials,
            unreadActivityCount: activityViewModel.unreadCount,
            onOpenProfile: {
                presentProfileSheet()
            },
            onOpenActivity: {
                presentActivitySheet()
            },
            onOpenTransactionInHistory: { transactionId in
                historyRequest = .openTransaction(transactionId)
            },
            historyRequest: $historyRequest
        )
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $isActivitySheetPresented) {
            ActivityView(
                searchText: .constant(""),
                isScrolled: .constant(false),
                isDetailShowing: .constant(false),
                onNavigateToFriends: {
                    presentProfileSheet(destination: .friends)
                },
                usesSheetChrome: true,
                onDismiss: {
                    isActivitySheetPresented = false
                }
            )
            .presentationDetents([.large])
            .presentationBackground(Color.homeSectionBackground)
            .presentationCornerRadius(36)
        }
        .sheet(isPresented: $isProfileSheetPresented) {
            profileSheet
                .presentationDetents([.large])
                .presentationBackground(Color.homeSectionBackground)
                .presentationCornerRadius(36)
        }
        .onChange(of: isActivitySheetPresented) { _, isPresented in
            guard isPresented, let clerkId = clerk.user?.id else { return }
            activityViewModel.markAllAsRead(clerkId: clerkId)
        }
        .task(id: subscriptionKey) {
            if let clerkId = clerk.user?.id {
                activityViewModel.subscribeToUnreadCount(clerkId: clerkId)
            }
        }
        .onAppear {
            applyPendingNotificationRouteIfNeeded()
        }
        .onChange(of: notificationManager.pendingRoute) { _, _ in
            applyPendingNotificationRouteIfNeeded()
        }
    }

    private func presentActivitySheet() {
        isActivitySheetPresented = true
    }
    
    private func presentProfileSheet(destination: ProfileExternalNavigationRequest? = nil) {
        isProfileSheetDetailShowing = false
        
        if isActivitySheetPresented {
            isActivitySheetPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetNavigationRequest = destination
                isProfileSheetPresented = true
            }
        } else {
            profileSheetNavigationRequest = destination
            isProfileSheetPresented = true
        }
    }
    
    private func applyPendingNotificationRouteIfNeeded() {
        guard let route = notificationManager.consumePendingRoute() else { return }
        applyNotificationRoute(route)
    }
    
    private func applyNotificationRoute(_ route: AppNotificationRoute) {
        withAnimation(.spring(duration: 0.35)) {
            switch route {
            case .transaction(let transactionId):
                historyRequest = .openTransaction(transactionId)
            case .friends:
                presentProfileSheet(destination: .friends)
            case .activity:
                isActivitySheetPresented = true
            }
        }
    }
    
    private var profileSheet: some View {
        ProfileView(
            isDetailShowing: $isProfileSheetDetailShowing,
            externalNavigationRequest: $profileSheetNavigationRequest,
            usesProfileSheetChrome: true,
            onDismiss: {
                isProfileSheetPresented = false
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.homeSectionBackground)
    }
}

#Preview {
    MainTabView()
}
