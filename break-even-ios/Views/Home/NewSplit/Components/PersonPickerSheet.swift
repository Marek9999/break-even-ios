//
//  PersonPickerSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct PersonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let friends: [ConvexFriend]
    @Binding var selectedFriends: [ConvexFriend]
    let onDone: () -> Void
    
    @State private var searchText = ""
    
    private var filteredFriends: [ConvexFriend] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredFriends.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No People" : "No Results",
                        systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Add people from Profile to split with them." : "No people match \"\(searchText)\"")
                    )
                } else {
                    ForEach(filteredFriends, id: \.id) { friend in
                        PersonPickerRow(
                            friend: friend,
                            isSelected: selectedFriends.contains(where: { $0.id == friend.id }),
                            onToggle: {
                                toggleSelection(friend)
                            }
                        )
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func toggleSelection(_ friend: ConvexFriend) {
        if let index = selectedFriends.firstIndex(where: { $0.id == friend.id }) {
            selectedFriends.remove(at: index)
        } else {
            selectedFriends.append(friend)
        }
    }
}

// MARK: - Person Picker Row

struct PersonPickerRow: View {
    let friend: ConvexFriend
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Avatar
                if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        initialsView
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    initialsView
                }
                
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
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

// MARK: - Preview

#Preview("Person Picker Sheet") {
    struct PreviewWrapper: View {
        @State private var selected: [ConvexFriend] = []
        
        var body: some View {
            PersonPickerSheet(
                friends: [],
                selectedFriends: $selected,
                onDone: { }
            )
        }
    }
    
    return PreviewWrapper()
}
