//
//  InlineFriendSearch.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Inline friend search with autocomplete dropdown
struct InlineFriendSearch: View {
    let availableFriends: [ConvexFriend]
    @Binding var selectedFriends: [ConvexFriend]
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    /// Friends filtered by search text, excluding already selected ones
    private var filteredFriends: [ConvexFriend] {
        let unselectedFriends = availableFriends.filter { friend in
            !selectedFriends.contains(where: { $0.id == friend.id })
        }
        
        if searchText.isEmpty {
            return unselectedFriends
        }
        
        return unselectedFriends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    /// Whether to show the dropdown suggestions
    private var showSuggestions: Bool {
        isSearchFocused && !filteredFriends.isEmpty && !searchText.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search TextField
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search friends...", text: $searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            
            // Dropdown suggestions
            if showSuggestions {
                suggestionsList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSuggestions)
    }
    
    // MARK: - Suggestions List
    
    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(filteredFriends.prefix(5), id: \.id) { friend in
                Button {
                    addFriend(friend)
                } label: {
                    HStack(spacing: 12) {
                        // Avatar
                        FriendSearchAvatar(friend: friend, size: 36)
                        
                        // Info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            if let email = friend.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if friend.id != filteredFriends.prefix(5).last?.id {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.top, 4)
    }
    
    // MARK: - Actions
    
    private func addFriend(_ friend: ConvexFriend) {
        withAnimation(.spring(response: 0.3)) {
            selectedFriends.append(friend)
            searchText = ""
            isSearchFocused = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Friend Search Avatar

private struct FriendSearchAvatar: View {
    let friend: ConvexFriend
    let size: CGFloat
    
    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

// MARK: - Preview

#Preview("Inline Friend Search") {
    struct PreviewWrapper: View {
        @State private var selected: [ConvexFriend] = []
        
        var body: some View {
            VStack {
                InlineFriendSearch(
                    availableFriends: [],
                    selectedFriends: $selected
                )
                .padding()
                
                Spacer()
            }
        }
    }
    
    return PreviewWrapper()
}
