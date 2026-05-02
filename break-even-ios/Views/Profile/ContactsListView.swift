//
//  ContactsListView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

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

    // Link / merge sheets
    @State private var placeholderToLink: ConvexFriend?
    @State private var inviteToMerge: ReceivedInvitation?

    // Confirmation dialogs after a candidate is picked.
    @State private var pendingLink: PendingLink?
    @State private var pendingMerge: PendingMerge?
    
    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

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
        friends.filter {
            ($0.inviteStatus ?? "none") != "removed_by_me" &&
            ($0.inviteStatus ?? "none") != "rejected"
        }
    }

    private var removedFriends: [ConvexFriend] {
        friends.filter { ($0.inviteStatus ?? "none") == "removed_by_me" }
    }

    private var rejectedFriends: [ConvexFriend] {
        friends.filter { ($0.inviteStatus ?? "none") == "rejected" }
    }

    private var placeholderFriends: [ConvexFriend] {
        friends.filter { $0.isDummy && !$0.isSelf && $0.linkedUserId == nil }
    }

    private var filteredFriends: [ConvexFriend] {
        if searchText.isEmpty { return activeFriends }
        return activeFriends.filter { matchesSearch($0) }
    }

    private var filteredRemoved: [ConvexFriend] {
        if searchText.isEmpty { return removedFriends }
        return removedFriends.filter { matchesSearch($0) }
    }

    private var filteredRejected: [ConvexFriend] {
        if searchText.isEmpty { return rejectedFriends }
        return rejectedFriends.filter { matchesSearch($0) }
    }
    
    private var listRowBackground: Color {
        Color.historyListBackground
    }

    private func matchesSearch(_ friend: ConvexFriend) -> Bool {
        friend.name.localizedCaseInsensitiveContains(searchText) ||
        (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    var body: some View {
        listContent
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("My People")
            .toolbar { toolbarContent }
            .modifier(ContactsSheetsModifier(
                showAddContact: $showAddContact,
                placeholderToLink: $placeholderToLink,
                inviteToMerge: $inviteToMerge,
                pendingLink: $pendingLink,
                pendingMerge: $pendingMerge,
                friends: friends,
                placeholderFriends: placeholderFriends
            ))
            .modifier(ContactsAlertsModifier(
                showDeleteAlert: $showDeleteAlert,
                friendToDelete: $friendToDelete,
                deleteError: $deleteError,
                actionError: $actionError,
                pendingLink: $pendingLink,
                pendingMerge: $pendingMerge,
                onDelete: { friend in deleteFriend(friend) },
                onConfirmLink: { link in performLink(link) },
                onConfirmMerge: { merge in performMerge(merge) }
            ))
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            receivedInvitationsSection
            sentInvitationsSection
            mainListSection
            removedSection
            rejectedSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.homeSectionBackground)
        .containerBackground(Color.homeSectionBackground, for: .navigation)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddContact = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - List sections

    @ViewBuilder
    private var receivedInvitationsSection: some View {
        if !receivedInvitations.isEmpty && searchText.isEmpty {
            Section {
                ForEach(receivedInvitations) { invite in
                    ReceivedInvitationRow(
                        invitation: invite,
                        canMerge: !placeholderFriends.isEmpty,
                        onAccept: { acceptInvitation(invite) },
                        onDecline: { declineInvitation(invite) },
                        onMerge: { inviteToMerge = invite }
                    )
                }
            } header: {
                Label("Pending Invitations", systemImage: "envelope.badge")
            }
            .listRowBackground(listRowBackground)
        }
    }

    @ViewBuilder
    private var sentInvitationsSection: some View {
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
            .listRowBackground(listRowBackground)
        }
    }

    private var isCompletelyEmpty: Bool {
        filteredFriends.isEmpty &&
        receivedInvitations.isEmpty &&
        sentInvitations.isEmpty &&
        filteredRemoved.isEmpty &&
        filteredRejected.isEmpty
    }

    @ViewBuilder
    private var mainListSection: some View {
        if isCompletelyEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No People" : "No Results",
                systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Add people to split expenses with them." : "No people match \"\(searchText)\"")
            )
            .listRowBackground(Color.clear)
        } else if !filteredFriends.isEmpty {
            Section {
                ForEach(filteredFriends, id: \.id) { friend in
                    activeFriendRow(friend)
                }
            }
            .listRowBackground(listRowBackground)
        }
    }

    @ViewBuilder
    private func activeFriendRow(_ friend: ConvexFriend) -> some View {
        let isPlaceholder = friend.isDummy && friend.linkedUserId == nil
        let linkAction: (() -> Void)? = isPlaceholder ? { placeholderToLink = friend } : nil

        ContactRow(
            friend: friend,
            onResendInvite: { resendInvite(friend) },
            onLinkToUser: linkAction
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if isPlaceholder {
                Button {
                    placeholderToLink = friend
                } label: {
                    Label("Link", systemImage: "link")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private var removedSection: some View {
        if !filteredRemoved.isEmpty {
            Section {
                ForEach(filteredRemoved, id: \.id) { friend in
                    ContactRow(
                        friend: friend,
                        onResendInvite: { resendInvite(friend) },
                        onLinkToUser: nil
                    )
                }
            } header: {
                Text("Removed")
            }
            .listRowBackground(listRowBackground)
        }
    }

    @ViewBuilder
    private var rejectedSection: some View {
        if !filteredRejected.isEmpty {
            Section {
                ForEach(filteredRejected, id: \.id) { friend in
                    rejectedFriendRow(friend)
                }
            } header: {
                Text("Rejected")
            } footer: {
                Text("Invitations you declined. Swipe to remove them from your contacts.")
            }
            .listRowBackground(listRowBackground)
        }
    }

    @ViewBuilder
    private func rejectedFriendRow(_ friend: ConvexFriend) -> some View {
        ContactRow(
            friend: friend,
            onResendInvite: { resendInvite(friend) },
            onLinkToUser: nil
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                friendToDelete = friend
                showDeleteAlert = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Pending action models

    struct PendingLink {
        let placeholder: ConvexFriend
        let profile: PublicUserProfile
    }

    struct PendingMerge {
        let invite: ReceivedInvitation
        let placeholder: ConvexFriend
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

    private func performLink(_ link: PendingLink) {
        guard let clerkId = clerk.user?.id else { return }
        let placeholder = link.placeholder
        let profile = link.profile
        pendingLink = nil
        Task {
            do {
                let response: LinkPlaceholderResponse = try await convexService.client.mutation(
                    "friends:linkPlaceholderToUser",
                    with: [
                        "clerkId": clerkId,
                        "friendId": placeholder.id,
                        "targetUserId": profile._id
                    ]
                )

                await MainActor.run {
                    if response.conflict == "already_linked" {
                        actionError = "You're already connected to \(profile.name) under another contact."
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func performMerge(_ merge: PendingMerge) {
        guard let clerkId = clerk.user?.id else { return }
        let invite = merge.invite
        let placeholder = merge.placeholder
        pendingMerge = nil
        Task {
            do {
                let _: MergePlaceholderResponse = try await convexService.client.mutation(
                    "friends:mergePlaceholderIntoInvite",
                    with: [
                        "clerkId": clerkId,
                        "placeholderFriendId": placeholder.id,
                        "receivedFriendId": invite.friendId
                    ]
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - View Modifiers
//
// The contacts view's body has enough sheets, alerts, and confirmation dialogs
// that SwiftUI's type-checker times out when they're all stacked inline. We
// split them into two modifiers — one for sheets, one for alerts and dialogs —
// so each modifier's body type stays small enough to type-check quickly.

private struct ContactsSheetsModifier: ViewModifier {
    @Binding var showAddContact: Bool
    @Binding var placeholderToLink: ConvexFriend?
    @Binding var inviteToMerge: ReceivedInvitation?
    @Binding var pendingLink: ContactsListView.PendingLink?
    @Binding var pendingMerge: ContactsListView.PendingMerge?

    let friends: [ConvexFriend]
    let placeholderFriends: [ConvexFriend]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddContact) {
                AddPersonSheet(existingFriends: friends)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCompactAdaptation(.sheet)
            }
            .sheet(item: $placeholderToLink) { friend in
                LinkPlaceholderSheet(
                    placeholder: friend,
                    existingFriends: friends,
                    onPick: { profile in
                        placeholderToLink = nil
                        pendingLink = ContactsListView.PendingLink(placeholder: friend, profile: profile)
                    }
                )
            }
            .sheet(item: $inviteToMerge) { invite in
                MergePlaceholderPickerSheet(
                    invite: invite,
                    placeholders: placeholderFriends,
                    onPick: { placeholder in
                        inviteToMerge = nil
                        pendingMerge = ContactsListView.PendingMerge(invite: invite, placeholder: placeholder)
                    }
                )
            }
    }
}

private struct ContactsAlertsModifier: ViewModifier {
    @Binding var showDeleteAlert: Bool
    @Binding var friendToDelete: ConvexFriend?
    @Binding var deleteError: String?
    @Binding var actionError: String?
    @Binding var pendingLink: ContactsListView.PendingLink?
    @Binding var pendingMerge: ContactsListView.PendingMerge?

    let onDelete: (ConvexFriend) -> Void
    let onConfirmLink: (ContactsListView.PendingLink) -> Void
    let onConfirmMerge: (ContactsListView.PendingMerge) -> Void

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil || actionError != nil },
            set: { if !$0 { deleteError = nil; actionError = nil } }
        )
    }

    private var linkPresented: Binding<Bool> {
        Binding(
            get: { pendingLink != nil },
            set: { if !$0 { pendingLink = nil } }
        )
    }

    private var mergePresented: Binding<Bool> {
        Binding(
            get: { pendingMerge != nil },
            set: { if !$0 { pendingMerge = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("Remove Person", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { friendToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let friend = friendToDelete {
                        onDelete(friend)
                    }
                }
            } message: {
                if let friend = friendToDelete {
                    Text("Remove \(friend.name)? Past splits will be preserved. They will see that you removed them.")
                }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK") { deleteError = nil; actionError = nil }
            } message: {
                Text(deleteError ?? actionError ?? "")
            }
            .confirmationDialog(
                linkDialogTitle,
                isPresented: linkPresented,
                presenting: pendingLink
            ) { link in
                Button("Send Invite") { onConfirmLink(link) }
                Button("Cancel", role: .cancel) { pendingLink = nil }
            } message: { link in
                Text("All past splits with \(link.placeholder.name) will transfer to \(link.profile.name) once they accept.")
            }
            .confirmationDialog(
                mergeDialogTitle,
                isPresented: mergePresented,
                presenting: pendingMerge
            ) { merge in
                Button("Merge") { onConfirmMerge(merge) }
                Button("Cancel", role: .cancel) { pendingMerge = nil }
            } message: { merge in
                Text("\(merge.placeholder.name) will become \(merge.invite.senderName) and all past splits will transfer.")
            }
    }

    private var linkDialogTitle: String {
        let name = pendingLink?.placeholder.name ?? "placeholder"
        let username = pendingLink?.profile.username ?? ""
        return "Link \(name) to @\(username)?"
    }

    private var mergeDialogTitle: String {
        let name = pendingMerge?.placeholder.name ?? "placeholder"
        let sender = pendingMerge?.invite.senderName ?? ""
        return "Merge \(name) with \(sender)?"
    }
}

// MARK: - Received Invitation Row

struct ReceivedInvitationRow: View {
    let invitation: ReceivedInvitation
    let canMerge: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onMerge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
        .contextMenu {
            if canMerge {
                Button {
                    onMerge()
                } label: {
                    Label("Merge with existing contact", systemImage: "arrow.triangle.merge")
                }
            }
            Button {
                onAccept()
            } label: {
                Label("Accept", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                onDecline()
            } label: {
                Label("Decline", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canMerge {
                Button {
                    onMerge()
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .tint(.purple)
            }
        }
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
    var onLinkToUser: (() -> Void)?

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
        .opacity((friend.inviteStatus ?? "none") == "removed_by_me" ? 0.5 : 1.0)
        .contextMenu {
            if let onLinkToUser {
                Button {
                    onLinkToUser()
                } label: {
                    Label("Link to user", systemImage: "link")
                }
            }
        }
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
                badge("Placeholder", color: Color(hex: "#FFA726"))
            }
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        let status = friend.inviteStatus ?? "none"
        if friend.isDummy && friend.linkedUserId == nil, let onLinkToUser {
            Button {
                onLinkToUser()
            } label: {
                Text("Link")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if status == "removed_by_them" {
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

// MARK: - Sent Invitation Row

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

// MARK: - Link Placeholder Sheet

/// Search-by-username sheet that promotes a placeholder into a real linked
/// friend. Shown after the user picks "Link to user" on a placeholder row.
private struct LinkPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.convexService) private var convexService

    let placeholder: ConvexFriend
    let existingFriends: [ConvexFriend]
    let onPick: (PublicUserProfile) -> Void

    @State private var username = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var state: AddPersonSheet.SearchState = .idle

    private var trimmed: String {
        username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FriendAvatar(friend: placeholder, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(placeholder.name)
                                .font(.body.weight(.medium))
                            Text("Placeholder contact")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Linking")
                } footer: {
                    Text("Find your friend on BreakEven by their username. When they accept, all past splits with this placeholder will transfer to them.")
                }

                Section {
                    HStack(spacing: 4) {
                        Text("@")
                            .foregroundStyle(.secondary)
                            .font(.body.monospaced())

                        TextField("username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.body.monospaced())
                            .onChange(of: username) { _, newValue in
                                username = newValue.lowercased().filter {
                                    $0.isLetter || $0.isNumber || $0 == "_"
                                }
                                if username.count > 20 {
                                    username = String(username.prefix(20))
                                }
                                debounceSearch()
                            }

                        switch state {
                        case .searching:
                            ProgressView().controlSize(.small)
                        case .found:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .alreadyInContacts:
                            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.blue)
                        case .notFound:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                        case .idle:
                            EmptyView()
                        }
                    }
                } header: {
                    Text("Find user")
                }

                resultSection
            }
            .navigationTitle("Link Placeholder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch state {
        case .found(let profile):
            Section {
                HStack(spacing: 12) {
                    if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.accentColor)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(profile.name.prefix(2).uppercased())
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(.body.weight(.medium))
                        if let display = profile.displayUsername {
                            Text(display).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Button {
                    onPick(profile)
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Link & Send Invite").fontWeight(.semibold)
                        Spacer()
                    }
                }
            }

        case .alreadyInContacts(_, let profile):
            Section {
                Label("@\(profile.username ?? trimmed) is already in your contacts under another row.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        case .notFound:
            Section {
                Label("No one with that username yet.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .idle, .searching:
            EmptyView()
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        guard trimmed.count >= 3 else {
            state = .idle
            return
        }
        state = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let subscription = convexService.client.subscribe(
                to: "users:getUserByUsername",
                with: ["username": trimmed],
                yielding: PublicUserProfile?.self
            )
            .replaceError(with: nil)
            .values

            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let profile = result {
                        if let existing = existingFriends.first(where: {
                            $0.linkedUserId == profile._id && !$0.isSelf && $0.id != placeholder.id
                        }) {
                            state = .alreadyInContacts(existing, profile)
                        } else {
                            state = .found(profile)
                        }
                    } else {
                        state = .notFound
                    }
                }
                break
            }
        }
    }
}

// MARK: - Merge Placeholder Picker Sheet

/// List of placeholders the user can merge an incoming invite into.
private struct MergePlaceholderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let invite: ReceivedInvitation
    let placeholders: [ConvexFriend]
    let onPick: (ConvexFriend) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if let avatarUrl = invite.senderAvatarUrl, let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.accentColor)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(invite.senderName.prefix(2).uppercased())
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.senderName).font(.body.weight(.medium))
                            Text("Wants to connect with you")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Pick the placeholder that represents this person. They'll merge into one contact, and all past splits with the placeholder will transfer to \(invite.senderName).")
                }

                if placeholders.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No placeholders to merge",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Create a placeholder first, then come back to merge.")
                        )
                    }
                } else {
                    Section {
                        ForEach(placeholders, id: \.id) { friend in
                            Button {
                                onPick(friend)
                            } label: {
                                HStack(spacing: 12) {
                                    FriendAvatar(friend: friend, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("Placeholder")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("Your placeholders")
                    }
                }
            }
            .navigationTitle("Merge Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContactsListView(viewModel: ProfileViewModel())
    }
}
