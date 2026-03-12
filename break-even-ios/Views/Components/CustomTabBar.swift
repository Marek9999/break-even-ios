//
//  CustomTabBar.swift
//  break-even-ios
//
//  Custom Liquid Glass tab bar with morphing transitions for iOS 26.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var isHistoryScrolled: Bool
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    let isDetailShowing: Bool
    let userAvatarUrl: String?
    let userInitials: String
    
    @Namespace private var tabBarNamespace
    @Namespace private var searchNamespace
    
    private var isCollapsed: Bool {
        selectedTab == 1 && isHistoryScrolled && !isDetailShowing
    }
    
    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 8) {
                if selectedTab == 1 && !isCollapsed && !isSearchActive && !isDetailShowing {
                    floatingSearchButton
                }
                
                mainTabRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .animation(.spring(duration: 0.35), value: isCollapsed)
        .animation(.spring(duration: 0.35), value: selectedTab)
        .animation(.spring(duration: 0.35), value: isDetailShowing)
    }
    
    // MARK: - Main Tab Row
    
    private var mainTabRow: some View {
        HStack(spacing: 12) {
            tabsGroup
            
            if isCollapsed && !isDetailShowing {
                inlineSearchPlaceholder
            }
            
            if !isCollapsed {
                Spacer()
            }
            
            profileButton
        }
    }
    
    // MARK: - Tabs Group
    
    @ViewBuilder
    private var tabsGroup: some View {
        if isCollapsed {
            Button {
                withAnimation(.spring(duration: 0.35)) {
                    isHistoryScrolled = false
                }
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
                    .glassEffectID("tabsPill", in: tabBarNamespace)
            }
        } else {
            HStack(spacing: 0) {
                tabIcon(symbol: "house", tab: 0)
                tabIcon(symbol: "clock", tab: 1)
            }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("tabsPill", in: tabBarNamespace)
        }
    }
    
    // MARK: - Tab Icon
    
    private func tabIcon(symbol: String, tab: Int) -> some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                selectedTab = tab
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: isTabSelected(tab) ? .medium : .regular))
                .foregroundStyle(.white.opacity(iconOpacity(for: tab)))
                .frame(width: 72, height: 48)
                .background(isTabSelected(tab) ? Color.text.opacity(0.1) : Color.text.opacity(0))
                .containerShape(Capsule())
        }
        .transaction { transaction in
            if !isTabSelected(tab) {
                transaction.animation = nil
            }
        }
    }
    
    private func isTabSelected(_ tab: Int) -> Bool {
        selectedTab == tab && selectedTab != 2
    }
    
    private func iconOpacity(for tab: Int) -> Double {
        if selectedTab == 2 { return 0.6 }
        return selectedTab == tab ? 1.0 : 0.6
    }
    
    // MARK: - Profile Button
    
    private var avatarSize: CGFloat {
        isCollapsed ? 36 : 44
    }
    
    private var profileButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                selectedTab = 2
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            profileAvatarContent
                .padding(6)
                .glassEffect(
                    selectedTab == 2
                    ? .regular.tint(.accent.opacity(0.2)).interactive()
                        : .regular.interactive(),
                    in: .circle
                )
                .glassEffectID("profile", in: tabBarNamespace)
        }
    }
    
    @ViewBuilder
    private var profileAvatarContent: some View {
        if let avatarUrl = userAvatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsAvatar
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            initialsAvatar
        }
    }
    
    private var initialsAvatar: some View {
        Text(userInitials)
            .font(.system(size: avatarSize * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: avatarSize, height: avatarSize)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
    
    // MARK: - Floating Search Button
    
    private static var searchPopTransition: some Transition {
        .blurReplace.combined(with: .scale(0.85))
    }
    
    private var floatingSearchButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                isSearchActive = true
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                Text("Search")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.clear.interactive())
        }
        .matchedGeometryEffect(id: "search", in: searchNamespace)
        .frame(maxWidth: .infinity, alignment: .center)
        .transition(Self.searchPopTransition)
    }
    
    // MARK: - Inline Search Placeholder
    
    private var inlineSearchPlaceholder: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                isSearchActive = true
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.text)
                
                Text(searchText.isEmpty ? "Search splits..." : searchText)
                    .font(.body)
                    .foregroundStyle(.text.opacity(0.6))
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .frame(height: 48)
            .padding(.horizontal, 12)
            .glassEffect(.clear.interactive())
        }
        .matchedGeometryEffect(id: "search", in: searchNamespace)
        .transition(Self.searchPopTransition)
    }
}

// MARK: - Previews

private struct CustomTabBarPreview: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isScrolled = false
    @State private var isSearchActive = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                Text("Selected: \(["Home", "History", "History (collapsed)", "Profile"][min(selectedTab == 1 && isScrolled ? 2 : selectedTab, 3)])")
                    .foregroundStyle(.white)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Button("Home") {
                        withAnimation { selectedTab = 0; isScrolled = false }
                    }
                    Button("History") {
                        withAnimation { selectedTab = 1; isScrolled = false }
                    }
                    Button("Collapsed") {
                        withAnimation { selectedTab = 1; isScrolled = true }
                    }
                    Button("Profile") {
                        withAnimation { selectedTab = 2; isScrolled = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                
                Spacer()
            }
            .padding(.top, 60)
            
            CustomTabBar(
                selectedTab: $selectedTab,
                isHistoryScrolled: $isScrolled,
                searchText: $searchText,
                isSearchActive: $isSearchActive,
                isDetailShowing: false,
                userAvatarUrl: nil,
                userInitials: "RD"
            )
        }
    }
}

#Preview("Interactive") {
    CustomTabBarPreview()
        .preferredColorScheme(.dark)
}
