//
//  PaidByPickerSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct PaidByPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    @Binding var selectedFriend: ConvexFriend?
    let onSelect: (ConvexFriend) -> Void
    
    @State private var searchText = ""
    
    private var allOptions: [ConvexFriend] {
        var options = allFriends
        if let self_ = selfFriend, !options.contains(where: { $0.id == self_.id }) {
            options.insert(self_, at: 0)
        }
        return options
    }
    
    private var filteredOptions: [ConvexFriend] {
        if searchText.isEmpty {
            return allOptions
        }
        return allOptions.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if filteredOptions.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No people match \"\(searchText)\"")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, friend in
                            Button {
                                selectedFriend = friend
                                onSelect(friend)
                                dismiss()
                            } label: {
                                HStack {
                                    FriendAvatar(friend: friend, size: 36)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName)
                                            .foregroundStyle(.text)
                                        
                                        if let email = friend.email {
                                            Text(email)
                                                .font(.caption)
                                                .foregroundStyle(.text.opacity(0.6))
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedFriend?.id == friend.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accent)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if index < filteredOptions.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("Who Paid?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
#Preview("Paid By Picker") {
    PaidByPickerSheet(
        allFriends: [.previewSelf, .previewAlice, .previewBob],
        selfFriend: .previewSelf,
        selectedFriend: .constant(.previewSelf),
        onSelect: { _ in }
    )
}
#endif
