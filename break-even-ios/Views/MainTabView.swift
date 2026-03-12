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
    
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isHistoryScrolled = false
    @State private var isSearchActive = false
    @State private var isHistoryDetailShowing = false
    @State private var isProfileDetailShowing = false
    
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
    
    var body: some View {
        ZStack {
            NavigationStack {
                HomeView()
            }
            .opacity(selectedTab == 0 ? 1 : 0)
            .zIndex(selectedTab == 0 ? 1 : 0)
            
            HistoryView(
                searchText: $searchText,
                isScrolled: $isHistoryScrolled,
                isDetailShowing: $isHistoryDetailShowing
            )
            .opacity(selectedTab == 1 ? 1 : 0)
            .zIndex(selectedTab == 1 ? 1 : 0)
            
            ProfileView(isDetailShowing: $isProfileDetailShowing)
                .opacity(selectedTab == 2 ? 1 : 0)
                .zIndex(selectedTab == 2 ? 1 : 0)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !isProfileDetailShowing {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isHistoryScrolled: $isHistoryScrolled,
                    searchText: $searchText,
                    isSearchActive: $isSearchActive,
                    isDetailShowing: isHistoryDetailShowing,
                    userAvatarUrl: userAvatarUrl,
                    userInitials: userInitials
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .bottom) {
            if isSearchActive && selectedTab == 1 && !isHistoryDetailShowing {
                searchBarOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isSearchActive)
        .animation(.spring(duration: 0.35), value: isHistoryDetailShowing)
        .animation(.spring(duration: 0.35), value: isProfileDetailShowing)
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue == 1 && newValue != 1 {
                cancelSearch()
            }
        }
        .onChange(of: isSearchActive) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && isSearchActive {
                cancelSearch()
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
        }
    }
    
    // MARK: - Search Bar Overlay
    
    @ViewBuilder
    private var searchBarOverlay: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.text)
                    
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search past splits...")
                            .foregroundStyle(.text.opacity(0.6))
                    )
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .foregroundStyle(.text)
                    
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.text.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(searchText.isEmpty ? 0 : 1)
                    .disabled(searchText.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(height: 44)
                .glassEffect()
                
                Button {
                    cancelSearch()
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
    
    private func prewarmKeyboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            keyboardPrewarmFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                keyboardPrewarmFocused = false
            }
        }
    }
}

#Preview {
    MainTabView()
}
