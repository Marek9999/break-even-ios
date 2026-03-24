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
    
    var viewModel: ProfileViewModel
    
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var friendToDelete: ConvexFriend?
    @State private var showDeleteAlert = false
    @State private var deleteError: String?
    @State private var actionError: String?
    
    private var friends: [ConvexFriend] {
        viewModel.otherFriends
    }
    
    private var receivedInvitations: [ReceivedInvitation] {
        viewModel.receivedInvitations
    }
    
    private var sentInvitations: [EnrichedInvitation] {
        viewModel.sentInvitations.filter { $0.status != "accepted" }
    }
    
    private var activeFriends: [ConvexFriend] {
        friends.filter { $0.inviteStatus != "removed_by_me" }
    }
    
    private var removedFriends: [ConvexFriend] {
        friends.filter { $0.inviteStatus == "removed_by_me" }
    }
    
    private var filteredFriends: [ConvexFriend] {
        let source = activeFriends
        if searchText.isEmpty { return source }
        return source.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private var filteredRemoved: [ConvexFriend] {
        if searchText.isEmpty { return removedFriends }
        return removedFriends.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        List {
            // Received invitations section
            if !receivedInvitations.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(receivedInvitations) { invite in
                        ReceivedInvitationRow(
                            invitation: invite,
                            onAccept: { acceptInvitation(invite) },
                            onDecline: { declineInvitation(invite) }
                        )
                    }
                } header: {
                    Label("Pending Invitations", systemImage: "envelope.badge")
                }
            }
            
            if !sentInvitations.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(sentInvitations) { invite in
                        SentInvitationRow(
                            invitation: invite,
                            onResend: { resendInvitation(invite) },
                            onCancel: invite.status == "pending" ? { cancelInvitation(invite) } : nil
                        )
                    }
                } header: {
                    Label("Sent Invites", systemImage: "paperplane")
                }
            }
            
            // Main friends list
            if filteredFriends.isEmpty && receivedInvitations.isEmpty && sentInvitations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No People" : "No Results",
                    systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Add people to split expenses with them." : "No people match \"\(searchText)\"")
                )
            } else if !filteredFriends.isEmpty {
                Section {
                    ForEach(filteredFriends, id: \.id) { friend in
                        ContactRow(
                            friend: friend,
                            onResendInvite: { resendInvite(friend) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if friend.inviteStatus != "removed_by_them" {
                                Button(role: .destructive) {
                                    friendToDelete = friend
                                    showDeleteAlert = true
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
            
            // Removed friends
            if !filteredRemoved.isEmpty {
                Section {
                    ForEach(filteredRemoved, id: \.id) { friend in
                        ContactRow(
                            friend: friend,
                            onResendInvite: { resendInvite(friend) }
                        )
                    }
                } header: {
                    Text("Removed")
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
        .alert("Remove Person", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { friendToDelete = nil }
            Button("Remove", role: .destructive) {
                if let friend = friendToDelete {
                    deleteFriend(friend)
                }
            }
        } message: {
            if let friend = friendToDelete {
                Text("Remove \(friend.name)? Past splits will be preserved. They will see that you removed them.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { deleteError != nil || actionError != nil },
            set: { if !$0 { deleteError = nil; actionError = nil } }
        )) {
            Button("OK") { deleteError = nil; actionError = nil }
        } message: {
            Text(deleteError ?? actionError ?? "")
        }
    }
    
    // MARK: - Actions
    
    private func deleteFriend(_ friend: ConvexFriend) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let _: Bool = try await convexService.client.mutation(
                    "friends:deleteFriend",
                    with: [
                        "clerkId": clerkId,
                        "friendId": friend.id
                    ]
                )
                friendToDelete = nil
            } catch {
                deleteError = error.localizedDescription
                friendToDelete = nil
            }
        }
    }
    
    private func acceptInvitation(_ invite: ReceivedInvitation) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                struct AcceptResult: Codable { let success: Bool }
                let _: AcceptResult = try await convexService.client.mutation(
                    "invitations:acceptInvitationByFriend",
                    with: [
                        "clerkId": clerkId,
                        "friendId": invite.friendId
                    ]
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    
    private func declineInvitation(_ invite: ReceivedInvitation) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                struct RejectResult: Codable { let success: Bool }
                let _: RejectResult = try await convexService.client.mutation(
                    "invitations:rejectInvitation",
                    with: [
                        "clerkId": clerkId,
                        "friendId": invite.friendId
                    ]
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    
    private func resendInvite(_ friend: ConvexFriend) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let _: ResendInvitationResponse = try await convexService.client.mutation(
                    "invitations:resendInvitation",
                    with: [
                        "clerkId": clerkId,
                        "friendId": friend.id
                    ]
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    
    private func resendInvitation(_ invitation: EnrichedInvitation) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let _: ResendInvitationResponse = try await convexService.client.mutation(
                    "invitations:resendInvitation",
                    with: [
                        "clerkId": clerkId,
                        "friendId": invitation.friendId
                    ]
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    
    private func cancelInvitation(_ invitation: EnrichedInvitation) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let _: Bool = try await convexService.client.mutation(
                    "invitations:cancelInvitation",
                    with: [
                        "clerkId": clerkId,
                        "invitationId": invitation.id
                    ]
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

// MARK: - Received Invitation Row

struct ReceivedInvitationRow: View {
    let invitation: ReceivedInvitation
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarUrl = invitation.senderAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsAvatar(for: invitation.senderName)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                initialsAvatar(for: invitation.senderName)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.senderName)
                    .font(.body.weight(.medium))
                if let email = invitation.senderEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Wants to connect with you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    onDecline()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Button {
                    onAccept()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func initialsAvatar(for name: String) -> some View {
        let components = name.split(separator: " ")
        let initials: String
        if components.count >= 2 {
            initials = "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            initials = String(name.prefix(2)).uppercased()
        }
        return Text(initials)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let friend: ConvexFriend
    var onResendInvite: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: friend, size: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.name)
                        .font(.body)
                    
                    statusBadge
                }
                
                if let email = friend.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            trailingAction
        }
        .padding(.vertical, 4)
        .opacity(friend.inviteStatus == "removed_by_me" ? 0.5 : 1.0)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        let status = friend.inviteStatus ?? "none"
        switch status {
        case "invite_sent":
            badge("Invite Sent", color: .orange)
        case "rejected":
            badge("Declined", color: .red)
        case "removed_by_them":
            badge("Removed You", color: .red)
        case "removed_by_me":
            badge("Removed", color: .secondary)
        case "invite_received":
            badge("Pending", color: .blue)
        case "accepted":
            EmptyView()
        default:
            if friend.isDummy {
                badge("Not on app", color: .secondary)
            }
        }
    }
    
    @ViewBuilder
    private var trailingAction: some View {
        let status = friend.inviteStatus ?? "none"
        if status == "rejected" || status == "removed_by_them" {
            Button {
                onResendInvite?()
            } label: {
                Text("Re-invite")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if status == "invite_sent" {
            Button {
                onResendInvite?()
            } label: {
                Text("Resend")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
    
}

struct SentInvitationRow: View {
    let invitation: EnrichedInvitation
    let onResend: () -> Void
    var onCancel: (() -> Void)?
    
    private var title: String {
        invitation.friend?.name ?? invitation.recipientEmail ?? "Invite"
    }
    
    private var subtitle: String {
        if let email = invitation.recipientEmail, !email.isEmpty {
            return email
        }
        return "Expires \(invitation.expiresAtDate.formatted(date: .abbreviated, time: .omitted))"
    }
    
    private var badgeText: String {
        switch invitation.status {
        case "pending":
            return "Pending"
        case "rejected":
            return "Declined"
        case "expired":
            return "Expired"
        case "cancelled":
            return "Cancelled"
        default:
            return invitation.status.capitalized
        }
    }
    
    private var badgeColor: Color {
        switch invitation.status {
        case "pending":
            return .orange
        case "rejected", "expired", "cancelled":
            return .secondary
        default:
            return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: invitation.friend ?? ConvexFriend(
                _id: invitation.friendId,
                ownerId: invitation.senderId,
                name: title,
                email: invitation.recipientEmail,
                isDummy: true,
                isSelf: false,
                inviteStatus: "invite_sent",
                createdAt: invitation.createdAt
            ), size: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body)
                    Text(badgeText)
                        .font(.caption2)
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if let onCancel {
                    Button("Cancel", role: .destructive, action: onCancel)
                        .font(.caption.weight(.medium))
                }
                
                Button(invitation.status == "pending" ? "Resend" : "Invite Again", action: onResend)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ContactsListView(viewModel: ProfileViewModel())
    }
}
