//
//  ContactsListView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile

struct ContactsListView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    let friends: [ConvexFriend]
    
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var friendToDelete: ConvexFriend?
    @State private var showDeleteAlert = false
    @State private var deleteError: String?
    
    private var filteredFriends: [ConvexFriend] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (friend.phone?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        List {
            if filteredFriends.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No People" : "No Results",
                    systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Add people to split expenses with them." : "No people match \"\(searchText)\"")
                )
            } else {
                ForEach(filteredFriends, id: \.id) { friend in
                    ContactRow(friend: friend)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                friendToDelete = friend
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search people")
        .navigationTitle("My People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddPersonSheet()
        }
        .alert("Delete Person", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                friendToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let friend = friendToDelete {
                    deleteFriend(friend)
                }
            }
        } message: {
            if let friend = friendToDelete {
                Text("Are you sure you want to delete \(friend.name)? This cannot be undone.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
    }
    
    private func deleteFriend(_ friend: ConvexFriend) {
        Task {
            do {
                let _: Bool = try await convexService.client.mutation(
                    "friends:deleteFriend",
                    with: ["friendId": friend.id]
                )
                friendToDelete = nil
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    friendToDelete = nil
                }
            }
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let friend: ConvexFriend
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialsAvatar
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                initialsAvatar
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(friend.name)
                        .font(.body)
                    
                    if friend.isDummy {
                        Text("Not on app")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                if let email = friend.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var initialsAvatar: some View {
        Text(friend.initials)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

#Preview {
    NavigationStack {
        ContactsListView(friends: [])
    }
}
