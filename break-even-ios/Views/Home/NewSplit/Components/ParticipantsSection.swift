//
//  ParticipantsSection.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Section for selecting multiple participants in a split
struct ParticipantsSection: View {
    @Binding var participants: [ConvexFriend]
    var onAddTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split with")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Add button
                    AddParticipantButton(action: onAddTapped)
                    
                    // Participant chips
                    ForEach(participants, id: \.id) { friend in
                        ParticipantChipView(
                            friend: friend,
                            onRemove: {
                                withAnimation(.spring(response: 0.3)) {
                                    participants.removeAll { $0.id == friend.id }
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
            }
        }
    }
}

// MARK: - Add Participant Button

private struct AddParticipantButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(Color.accent.opacity(0.15)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Participant Chip View

private struct ParticipantChipView: View {
    let friend: ConvexFriend
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            FriendAvatar(friend: friend, size: 28)
            
            Text(friend.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.text)
                .lineLimit(1)
            
            if !friend.isSelf {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.accentSecondary.opacity(0.2)), in: .capsule)
    }
}

// MARK: - Preview

#Preview("Participants Section") {
    struct PreviewWrapper: View {
        @State private var participants: [ConvexFriend] = []
        
        var body: some View {
            VStack {
                ParticipantsSection(
                    participants: $participants,
                    onAddTapped: { }
                )
                .padding()
                
                Spacer()
            }
        }
    }
    
    return PreviewWrapper()
}
