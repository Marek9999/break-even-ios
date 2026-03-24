//
//  break_even_iosTests.swift
//  break-even-iosTests
//
//  Created by Rudra Das on 2025-12-27.
//

import Testing
@testable import break_even_ios

struct break_even_iosTests {

    @Test func selectableFriendStatusesMatchSplitRules() async throws {
        let accepted = makeFriend(status: "accepted")
        let inviteSent = makeFriend(status: "invite_sent")
        let offApp = makeFriend(status: "none")
        let removed = makeFriend(status: "removed_by_me")
        let removedByThem = makeFriend(status: "removed_by_them")
        let rejected = makeFriend(status: "rejected")
        let received = makeFriend(status: "invite_received")
        let selfFriend = makeFriend(status: "accepted", isSelf: true)
        
        #expect(accepted.isSelectableForNewSplit)
        #expect(inviteSent.isSelectableForNewSplit)
        #expect(offApp.isSelectableForNewSplit)
        #expect(!removed.isSelectableForNewSplit)
        #expect(!removedByThem.isSelectableForNewSplit)
        #expect(!rejected.isSelectableForNewSplit)
        #expect(!received.isSelectableForNewSplit)
        #expect(!selfFriend.isSelectableForNewSplit)
    }
    
    @Test func enrichedInvitationExpiresFromTimestamp() async throws {
        let now = Date().timeIntervalSince1970 * 1000
        let pendingExpired = makeInvitation(
            status: "pending",
            expiresAt: now - 60_000,
            serverExpired: false
        )
        let pendingFuture = makeInvitation(
            status: "pending",
            expiresAt: now + 60_000,
            serverExpired: false
        )
        let explicitlyExpired = makeInvitation(
            status: "expired",
            expiresAt: now + 60_000,
            serverExpired: false
        )
        
        #expect(pendingExpired.isExpired)
        #expect(!pendingExpired.isPending)
        #expect(!pendingFuture.isExpired)
        #expect(pendingFuture.isPending)
        #expect(explicitlyExpired.isExpired)
        #expect(!explicitlyExpired.isPending)
    }
    
    private func makeFriend(
        status: String,
        isSelf: Bool = false
    ) -> ConvexFriend {
        ConvexFriend(
            _id: UUID().uuidString,
            ownerId: "owner",
            linkedUserId: isSelf ? "owner" : nil,
            name: "Friend",
            email: "friend@example.com",
            isDummy: status == "none",
            isSelf: isSelf,
            inviteStatus: status,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
    }
    
    private func makeInvitation(
        status: String,
        expiresAt: Double,
        serverExpired: Bool
    ) -> EnrichedInvitation {
        EnrichedInvitation(
            _id: UUID().uuidString,
            senderId: "sender",
            friendId: "friend",
            recipientEmail: "friend@example.com",
            recipientPhone: nil,
            status: status,
            token: "token",
            expiresAt: expiresAt,
            createdAt: Date().timeIntervalSince1970 * 1000,
            friend: nil,
            serverExpired: serverExpired
        )
    }

}
