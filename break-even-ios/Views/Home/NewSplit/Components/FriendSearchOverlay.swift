//
//  FriendSearchOverlay.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-02-28.
//

import SwiftUI

/// Full-screen search overlay for finding and selecting friends to add to a split.
struct FriendSearchOverlay: View {
    let availableFriends: [ConvexFriend]
    @Binding var selectedFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    let onDismiss: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var unselectedFriends: [ConvexFriend] {
        availableFriends.filter { friend in
            !selectedFriends.contains(where: { $0.id == friend.id })
        }
    }

    private var filteredFriends: [ConvexFriend] {
        if searchText.isEmpty {
            return unselectedFriends
        }
        return unselectedFriends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // Non-self selected friends (self can't be removed)
    private var removableSelectedFriends: [ConvexFriend] {
        selectedFriends.filter { $0.id != selfFriend?.id }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            resultsList
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if filteredFriends.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    ForEach(filteredFriends, id: \.id) { friend in
                        FriendResultRow(friend: friend) {
                            addFriend(friend)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if searchText.isEmpty {
            Text("Friends")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        } else {
            HStack(spacing: 4) {
                Text("Results for")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("\"\(searchText)\"")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "No Friends" : "No Results",
            systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
            description: Text(
                searchText.isEmpty
                    ? "Add people from Profile to split with them."
                    : "No people match \"\(searchText)\""
            )
        )
    }

    // MARK: - Bottom Bar (pills + search + cancel)

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if !removableSelectedFriends.isEmpty {
                selectedPills
            }

            searchBarRow
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground).opacity(0), location: 0),
                    .init(color: Color(.systemBackground).opacity(0.85), location: 0.15),
                    .init(color: Color(.systemBackground), location: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.keyboard)
        )
    }

    // MARK: - Selected Friend Pills

    private var selectedPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(removableSelectedFriends, id: \.id) { friend in
                        SelectedFriendPill(friend: friend) {
                            removeFriend(friend)
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Search Bar Row

    private var searchBarRow: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16, weight: .medium))

                    TextField("Add friends...", text: $searchText)
                        .focused($isSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.text.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button(action: dismissOverlay) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 2)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Actions

    private func addFriend(_ friend: ConvexFriend) {
        guard !selectedFriends.contains(where: { $0.id == friend.id }) else { return }
        withAnimation(.spring(response: 0.3)) {
            selectedFriends.append(friend)
            searchText = ""
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeFriend(_ friend: ConvexFriend) {
        withAnimation(.spring(response: 0.3)) {
            selectedFriends.removeAll(where: { $0.id == friend.id })
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func dismissOverlay() {
        isSearchFieldFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            onDismiss()
        }
    }
}

// MARK: - Friend Result Row

private struct FriendResultRow: View {
    let friend: ConvexFriend
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 14) {
                FriendAvatar(friend: friend, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if let email = friend.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selected Friend Pill

private struct SelectedFriendPill: View {
    let friend: ConvexFriend
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            FriendAvatar(friend: friend, size: 24)

            Text(friend.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

// MARK: - Preview

#Preview("Friend Search Overlay") {
    struct PreviewWrapper: View {
        @State private var selected: [ConvexFriend] = [
            ConvexFriend(
                _id: "self-1", ownerId: "o", linkedUserId: nil,
                name: "Alex Me", email: "alex@example.com",
                phone: nil, avatarUrl: nil,
                isDummy: false, isSelf: true, createdAt: 0
            )
        ]

        var body: some View {
            FriendSearchOverlay(
                availableFriends: [
                    ConvexFriend(
                        _id: "f-jane", ownerId: "o", linkedUserId: nil,
                        name: "Jane Smith", email: "jane@example.com",
                        phone: nil, avatarUrl: nil,
                        isDummy: false, isSelf: false, createdAt: 0
                    ),
                    ConvexFriend(
                        _id: "f-bob", ownerId: "o", linkedUserId: nil,
                        name: "Bob Wilson", email: "bob@example.com",
                        phone: nil, avatarUrl: nil,
                        isDummy: false, isSelf: false, createdAt: 0
                    ),
                    ConvexFriend(
                        _id: "f-carol", ownerId: "o", linkedUserId: nil,
                        name: "Carol Davis", email: "carol@example.com",
                        phone: nil, avatarUrl: nil,
                        isDummy: false, isSelf: false, createdAt: 0
                    ),
                ],
                selectedFriends: $selected,
                selfFriend: selected.first,
                onDismiss: {}
            )
        }
    }

    return PreviewWrapper()
}
