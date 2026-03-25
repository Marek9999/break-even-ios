//
//  MainTabView.swift
//  break-even-ios
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
    
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isHistoryScrolled = false
    @State private var isSearchActive = false
    @State private var isHistoryDetailShowing = false
    @State private var isProfileDetailShowing = false
    
    @State private var isActivityScrolled = false
    @State private var isActivityDetailShowing = false
    @State private var activitySearchText = ""
    @State private var isActivitySearchActive = false
    @State private var historyNavigationRequest: HistoryExternalNavigationRequest?
    
    @State private var activityViewModel = ActivityViewModel()
    @State private var profileNavigationRequest: ProfileExternalNavigationRequest?
    
    @FocusState private var isSearchFocused: Bool
    
    @State private var keyboardPrewarmText = ""
    @FocusState private var keyboardPrewarmFocused: Bool
    
    private var userAvatarUrl: String? {
        clerk.user?.imageUrl
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
    
    private var currentSearchText: Binding<String> {
        selectedTab == 3 ? $activitySearchText : $searchText
    }
    
    private var currentSearchActive: Binding<Bool> {
        selectedTab == 3 ? $isActivitySearchActive : $isSearchActive
    }
    
    private var isCurrentDetailShowing: Bool {
        switch selectedTab {
        case 1: return isHistoryDetailShowing
        case 3: return isActivityDetailShowing
        default: return false
        }
    }
    
    private var searchPlaceholder: String {
        selectedTab == 3 ? "Search activity..." : "Search past splits..."
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                HomeView { transactionId in
                    historyNavigationRequest = .transaction(transactionId)
                    withAnimation(.spring(duration: 0.35)) {
                        selectedTab = 1
                    }
                }
            }
            .opacity(selectedTab == 0 ? 1 : 0)
            .zIndex(selectedTab == 0 ? 1 : 0)
            
            HistoryView(
                searchText: $searchText,
                isScrolled: $isHistoryScrolled,
                isDetailShowing: $isHistoryDetailShowing,
                externalNavigationRequest: $historyNavigationRequest
            )
            .opacity(selectedTab == 1 ? 1 : 0)
            .zIndex(selectedTab == 1 ? 1 : 0)
            
            ProfileView(
                isDetailShowing: $isProfileDetailShowing,
                externalNavigationRequest: $profileNavigationRequest
            )
                .opacity(selectedTab == 2 ? 1 : 0)
                .zIndex(selectedTab == 2 ? 1 : 0)
            
            ActivityView(
                searchText: $activitySearchText,
                isScrolled: $isActivityScrolled,
                isDetailShowing: $isActivityDetailShowing,
                onNavigateToFriends: {
                    profileNavigationRequest = .friends
                    withAnimation(.spring(duration: 0.35)) {
                        selectedTab = 2
                    }
                }
            )
            .opacity(selectedTab == 3 ? 1 : 0)
            .zIndex(selectedTab == 3 ? 1 : 0)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !isProfileDetailShowing {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isHistoryScrolled: $isHistoryScrolled,
                    isActivityScrolled: $isActivityScrolled,
                    searchText: currentSearchText,
                    isSearchActive: currentSearchActive,
                    isDetailShowing: isCurrentDetailShowing,
                    userAvatarUrl: userAvatarUrl,
                    userInitials: userInitials,
                    unreadActivityCount: activityViewModel.unreadCount
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .bottom) {
            if isSearchActive && selectedTab == 1 && !isHistoryDetailShowing {
                searchBarOverlay(placeholder: "Search past splits...", text: $searchText, onCancel: { cancelSearch() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if isActivitySearchActive && selectedTab == 3 && !isActivityDetailShowing {
                searchBarOverlay(placeholder: "Search activity...", text: $activitySearchText, onCancel: { cancelActivitySearch() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isSearchActive)
        .animation(.spring(duration: 0.3), value: isActivitySearchActive)
        .animation(.spring(duration: 0.35), value: isHistoryDetailShowing)
        .animation(.spring(duration: 0.35), value: isActivityDetailShowing)
        .animation(.spring(duration: 0.35), value: isProfileDetailShowing)
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue == 1 && newValue != 1 {
                cancelSearch()
            }
            if oldValue == 3 && newValue != 3 {
                cancelActivitySearch()
            }
            if newValue == 3, let clerkId = clerk.user?.id {
                activityViewModel.markAllAsRead(clerkId: clerkId)
            }
        }
        .onChange(of: isSearchActive) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isActivitySearchActive) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                if isSearchActive { cancelSearch() }
                if isActivitySearchActive { cancelActivitySearch() }
            }
        }
        .task(id: clerk.user?.id) {
            if let clerkId = clerk.user?.id {
                activityViewModel.subscribeToUnreadCount(clerkId: clerkId)
            }
        }
        .background {
            TextField("", text: $keyboardPrewarmText)
                .focused($keyboardPrewarmFocused)
                .keyboardType(.decimalPad)
                .opacity(0)
                .frame(width: 1, height: 1)
                .offset(x: -1000)
                .allowsHitTesting(false)
        }
        .onAppear {
            prewarmKeyboard()
            applyPendingNotificationRouteIfNeeded()
        }
        .onChange(of: notificationManager.pendingRoute) { _, _ in
            applyPendingNotificationRouteIfNeeded()
        }
    }
    
    // MARK: - Search Bar Overlay
    
    @ViewBuilder
    private func searchBarOverlay(placeholder: String, text: Binding<String>, onCancel: @escaping () -> Void) -> some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.text)
                    
                    TextField(
                        "",
                        text: text,
                        prompt: Text(placeholder)
                            .foregroundStyle(.text.opacity(0.6))
                    )
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .foregroundStyle(.text)
                    
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.text.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(text.wrappedValue.isEmpty ? 0 : 1)
                    .disabled(text.wrappedValue.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(height: 44)
                .glassEffect()
                
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private func cancelSearch() {
        withAnimation(.spring(duration: 0.3)) {
            isSearchActive = false
            searchText = ""
        }
        isSearchFocused = false
    }
    
    private func cancelActivitySearch() {
        withAnimation(.spring(duration: 0.3)) {
            isActivitySearchActive = false
            activitySearchText = ""
        }
        isSearchFocused = false
    }
    
    private func prewarmKeyboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            keyboardPrewarmFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                keyboardPrewarmFocused = false
            }
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
                historyNavigationRequest = .transaction(transactionId)
                selectedTab = 1
            case .friends:
                profileNavigationRequest = .friends
                selectedTab = 2
            case .activity:
                selectedTab = 3
            }
        }
    }
}

#Preview {
    MainTabView()
}
