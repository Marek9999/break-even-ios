import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import {
  normalizeEmail,
  requireAuthenticatedUser,
  requireOwner,
} from "./lib/auth";
import { insertActivity } from "./activities";

function generateToken(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

async function generateUniqueToken(ctx: any): Promise<string> {
  let token = generateToken();
  let existing = await ctx.db
    .query("invitations")
    .withIndex("by_token", (q: any) => q.eq("token", token))
    .unique();
  while (existing) {
    token = generateToken();
    existing = await ctx.db
      .query("invitations")
      .withIndex("by_token", (q: any) => q.eq("token", token))
      .unique();
  }
  return token;
}

async function getReciprocalFriend(
  ctx: any,
  ownerId: Id<"users">,
  linkedUserId: Id<"users">
): Promise<Doc<"friends"> | null> {
  return await ctx.db
    .query("friends")
    .withIndex("by_owner_linkedUser", (q: any) =>
      q.eq("ownerId", ownerId).eq("linkedUserId", linkedUserId)
    )
    .unique();
}

function requireInvitationRecipient(
  invitation: Doc<"invitations">,
  user: Doc<"users">,
  friend: Doc<"friends">
) {
  const normalizedRecipientEmail = normalizeEmail(invitation.recipientEmail);
  const normalizedUserEmail = normalizeEmail(user.email);

  if (normalizedRecipientEmail && normalizedRecipientEmail !== normalizedUserEmail) {
    throw new Error("This invitation was sent to a different email address");
  }

  if (!normalizedRecipientEmail && friend.linkedUserId && friend.linkedUserId !== user._id) {
    throw new Error("This invitation was sent to a different user");
  }
}

/**
 * Create a friend invitation.
 * - Creates a reciprocal friend row on the recipient's side (if they're on the app)
 *   with inviteStatus "invite_received"
 * - Detects mutual invites and auto-accepts both sides
 */
export const createInvitation = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    recipientEmail: v.optional(v.string()),
    recipientPhone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }
    requireOwner(friend.ownerId, user._id);

    // Check for existing pending invitation for this friend
    const existingInvitation = await ctx.db
      .query("invitations")
      .withIndex("by_friend_status", (q) =>
        q.eq("friendId", args.friendId).eq("status", "pending")
      )
      .unique();

    if (existingInvitation) {
      return {
        invitationId: existingInvitation._id,
        token: existingInvitation.token,
        isExisting: true,
        autoAccepted: false,
      };
    }

    // Ensure friend's inviteStatus is set to invite_sent
    await ctx.db.patch(args.friendId, { inviteStatus: "invite_sent" });

    const recipientEmail = normalizeEmail(args.recipientEmail) ?? normalizeEmail(friend.email);

    // If the friend has a linkedUserId (user is on the app), handle in-app flow
    if (friend.linkedUserId) {
      const recipientUser = await ctx.db.get(friend.linkedUserId);
      if (recipientUser) {
        // Check for mutual invite: did the recipient already invite the sender?
        const reciprocalFriend = await getReciprocalFriend(
          ctx,
          friend.linkedUserId,
          user._id
        );

        if (reciprocalFriend && reciprocalFriend.inviteStatus === "invite_sent") {
          // Mutual invite detected — auto-accept both sides
          await ctx.db.patch(args.friendId, {
            isDummy: false,
            inviteStatus: "accepted",
          });
          await ctx.db.patch(reciprocalFriend._id, {
            inviteStatus: "accepted",
          });

          // Accept any pending invitation from the other side
          const theirInvitation = await ctx.db
            .query("invitations")
            .withIndex("by_friend_status", (q) =>
              q.eq("friendId", reciprocalFriend._id).eq("status", "pending")
            )
            .first();

          if (theirInvitation) {
            await ctx.db.patch(theirInvitation._id, { status: "accepted" });
          }

          // Create our invitation record as accepted
          const token = await generateUniqueToken(ctx);
          const invitationId = await ctx.db.insert("invitations", {
            senderId: user._id,
            friendId: args.friendId,
            recipientEmail,
            recipientPhone: args.recipientPhone || friend.phone,
            status: "accepted",
            token,
            expiresAt: Date.now() + 7 * 24 * 60 * 60 * 1000,
            createdAt: Date.now(),
          });

          // Backfill transactionParticipants for both sides
          await backfillParticipants(ctx, args.friendId, friend.linkedUserId);
          await backfillParticipants(ctx, reciprocalFriend._id, user._id);

          // Backfill settlements for both directions
          await backfillSettlements(
            ctx,
            args.friendId,
            user._id,
            reciprocalFriend._id,
            friend.linkedUserId!
          );
          await backfillSettlements(
            ctx,
            reciprocalFriend._id,
            friend.linkedUserId!,
            args.friendId,
            user._id
          );

          // Activity: mutual auto-accept — notify both sides
          await insertActivity(ctx, {
            userId: friend.linkedUserId!,
            actorId: user._id,
            actorName: user.name,
            type: "invitation_accepted",
            message: `You and ${user.name} are now friends`,
            friendId: args.friendId,
            invitationId,
          });
          await insertActivity(ctx, {
            userId: user._id,
            actorId: friend.linkedUserId!,
            actorName: recipientUser.name,
            type: "invitation_accepted",
            message: `You and ${recipientUser.name} are now friends`,
            friendId: reciprocalFriend._id,
          });

          return { invitationId, token, isExisting: false, autoAccepted: true };
        }

        // Not a mutual invite — create reciprocal friend row with invite_received
        if (!reciprocalFriend) {
          await ctx.db.insert("friends", {
            ownerId: friend.linkedUserId,
            linkedUserId: user._id,
            name: user.name,
            email: user.email,
            phone: user.phone,
            avatarUrl: user.avatarUrl,
            isDummy: false,
            isSelf: false,
            inviteStatus: "invite_received",
            createdAt: Date.now(),
          });
        } else if (
          reciprocalFriend.inviteStatus === "removed_by_me" ||
          reciprocalFriend.inviteStatus === "rejected" ||
          reciprocalFriend.inviteStatus === "removed_by_them"
        ) {
          // Re-activate the reciprocal row
          await ctx.db.patch(reciprocalFriend._id, {
            inviteStatus: "invite_received",
          });
        }
      }
    }

    // Generate unique token and create the invitation
    const token = await generateUniqueToken(ctx);
    const expiresAt = Date.now() + 7 * 24 * 60 * 60 * 1000;

    const invitationId = await ctx.db.insert("invitations", {
      senderId: user._id,
      friendId: args.friendId,
      recipientEmail,
      recipientPhone: args.recipientPhone || friend.phone,
      status: "pending",
      token,
      expiresAt,
      createdAt: Date.now(),
    });

    // Activity: notify recipient if they're on the app
    if (friend.linkedUserId) {
      await insertActivity(ctx, {
        userId: friend.linkedUserId,
        actorId: user._id,
        actorName: user.name,
        type: "invitation_received",
        message: `${user.name} sent you a friend request`,
        friendId: args.friendId,
        invitationId,
      });
    }

    return { invitationId, token, isExisting: false, autoAccepted: false };
  },
});

/**
 * Backfill transactionParticipants for a friend that just got accepted.
 * Finds all splits referencing this friendId and inserts participant rows.
 */
async function backfillParticipants(
  ctx: any,
  friendId: any,
  userId: any
) {
  const splits = await ctx.db
    .query("splits")
    .withIndex("by_friend", (q: any) => q.eq("friendId", friendId))
    .collect();

  const txIds = new Set<string>();
  for (const split of splits) {
    txIds.add(split.transactionId);
  }

  for (const txId of Array.from(txIds)) {
    const existing = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_user_transaction", (q: any) =>
        q.eq("userId", userId).eq("transactionId", txId)
      )
      .unique();

    if (!existing) {
      await ctx.db.insert("transactionParticipants", {
        transactionId: txId,
        userId,
        role: "participant",
        addedAt: Date.now(),
      });
    }
  }
}

/**
 * Backfill reciprocal settlements when a friend invite is accepted.
 * Mirrors settlements that the sender created against their friend row
 * onto the acceptor's reciprocal friend row with flipped direction.
 */
async function backfillSettlements(
  ctx: any,
  senderFriendId: any,
  senderUserId: any,
  reciprocalFriendId: any,
  acceptorUserId: any
) {
  const existingSettlements = await ctx.db
    .query("settlements")
    .withIndex("by_friend", (q: any) => q.eq("friendId", senderFriendId))
    .collect();

  for (const settlement of existingSettlements) {
    if (settlement.createdById.toString() !== senderUserId.toString()) continue;

    const flippedDirection =
      settlement.direction === "to_friend" ? "from_friend" : "to_friend";
    await ctx.db.insert("settlements", {
      createdById: acceptorUserId,
      friendId: reciprocalFriendId,
      amount: settlement.amount,
      currency: settlement.currency,
      direction: flippedDirection,
      note: settlement.note,
      balanceBeforeSettlement: settlement.balanceBeforeSettlement,
      exchangeRates: settlement.exchangeRates,
      settledAt: settlement.settledAt,
      createdAt: settlement.createdAt,
    });
  }
}

/**
 * Get invitation by token
 */
export const getInvitationByToken = query({
  args: {
    token: v.string(),
  },
  handler: async (ctx, args) => {
    const invitation = await ctx.db
      .query("invitations")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .unique();

    if (!invitation) {
      return null;
    }

    const sender = await ctx.db.get(invitation.senderId);
    const friend = await ctx.db.get(invitation.friendId);

    return {
      ...invitation,
      sender,
      friend,
      isExpired: invitation.status === "expired",
    };
  },
});

/**
 * Accept an invitation. Links the dummy friend, creates reciprocal row,
 * handles mutual invites, and backfills transactionParticipants.
 */
export const acceptInvitation = mutation({
  args: {
    token: v.string(),
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const invitation = await ctx.db
      .query("invitations")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .unique();

    if (!invitation) {
      throw new Error("Invitation not found");
    }

    if (invitation.status !== "pending") {
      throw new Error("Invitation is no longer pending");
    }

    if (invitation.expiresAt < Date.now()) {
      await ctx.db.patch(invitation._id, { status: "expired" });
      throw new Error("Invitation has expired");
    }

    const dummyFriend = await ctx.db.get(invitation.friendId);
    if (!dummyFriend) {
      throw new Error("Friend not found");
    }
    requireInvitationRecipient(invitation, user, dummyFriend);

    // Link the dummy friend to the real user
    await ctx.db.patch(invitation.friendId, {
      linkedUserId: user._id,
      isDummy: false,
      inviteStatus: "accepted",
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
    });

    // Mark invitation as accepted
    await ctx.db.patch(invitation._id, { status: "accepted" });

    // Create or update reciprocal friend for the acceptor
    let reciprocalFriendId: any = null;
    const sender = await ctx.db.get(invitation.senderId);
    if (sender) {
      const existingReciprocal = await ctx.db
        .query("friends")
        .withIndex("by_owner_linkedUser", (q) =>
          q.eq("ownerId", user._id).eq("linkedUserId", sender._id)
        )
        .unique();

      if (!existingReciprocal) {
        reciprocalFriendId = await ctx.db.insert("friends", {
          ownerId: user._id,
          linkedUserId: sender._id,
          name: sender.name,
          email: sender.email,
          phone: sender.phone,
          avatarUrl: sender.avatarUrl,
          isDummy: false,
          isSelf: false,
          inviteStatus: "accepted",
          createdAt: Date.now(),
        });
      } else {
        reciprocalFriendId = existingReciprocal._id;
        await ctx.db.patch(existingReciprocal._id, { inviteStatus: "accepted" });
      }

      // Handle mutual invite: if the acceptor also had a pending invite to the sender
      const acceptorFriendForSender = await ctx.db
        .query("friends")
        .withIndex("by_owner_linkedUser", (q) =>
          q.eq("ownerId", user._id).eq("linkedUserId", sender._id)
        )
        .unique();

      if (acceptorFriendForSender) {
        const mutualInvitation = await ctx.db
          .query("invitations")
          .withIndex("by_friend", (q) =>
            q.eq("friendId", acceptorFriendForSender._id)
          )
          .filter((q) => q.eq(q.field("status"), "pending"))
          .first();

        if (mutualInvitation) {
          await ctx.db.patch(mutualInvitation._id, { status: "accepted" });
          await ctx.db.patch(acceptorFriendForSender._id, {
            inviteStatus: "accepted",
          });
        }
      }
    }

    // Backfill transactionParticipants for the sender's splits involving this friend
    await backfillParticipants(ctx, invitation.friendId, user._id);

    // Backfill settlements the sender recorded before the acceptor joined
    if (reciprocalFriendId) {
      await backfillSettlements(
        ctx,
        invitation.friendId,
        invitation.senderId,
        reciprocalFriendId,
        user._id
      );
    }

    // Activity: notify the original sender that their invite was accepted
    await insertActivity(ctx, {
      userId: invitation.senderId,
      actorId: user._id,
      actorName: user.name,
      type: "invitation_accepted",
      message: `${user.name} accepted your friend request`,
      friendId: invitation.friendId,
      invitationId: invitation._id,
    });

    return { success: true, friendId: invitation.friendId };
  },
});

/**
 * Accept an invitation by friend ID (for in-app accept flow).
 * The recipient sees "invite_received" on their friend row and can accept from the UI.
 */
export const acceptInvitationByFriend = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    // This is the recipient's friend row (inviteStatus === "invite_received")
    const myFriendRow = await ctx.db.get(args.friendId);
    if (!myFriendRow) {
      throw new Error("Friend not found");
    }
    requireOwner(myFriendRow.ownerId, user._id);

    if (myFriendRow.inviteStatus !== "invite_received") {
      throw new Error("No pending invite for this friend");
    }

    if (!myFriendRow.linkedUserId) {
      throw new Error("Friend is not linked to a user");
    }

    // Update my side to accepted
    await ctx.db.patch(args.friendId, { inviteStatus: "accepted" });

    // Find and update the sender's friend row for me
    const senderFriendRow = await ctx.db
      .query("friends")
      .withIndex("by_owner_linkedUser", (q) =>
        q.eq("ownerId", myFriendRow.linkedUserId!).eq("linkedUserId", user._id)
      )
      .unique();

    if (senderFriendRow) {
      await ctx.db.patch(senderFriendRow._id, {
        isDummy: false,
        inviteStatus: "accepted",
        name: user.name,
        email: user.email,
        phone: user.phone,
        avatarUrl: user.avatarUrl,
      });

      // Mark the invitation as accepted
      const invitation = await ctx.db
        .query("invitations")
        .withIndex("by_friend_status", (q) =>
          q.eq("friendId", senderFriendRow._id).eq("status", "pending")
        )
        .first();

      if (invitation) {
        await ctx.db.patch(invitation._id, { status: "accepted" });
      }

      // Backfill transactionParticipants for splits the sender made with me
      await backfillParticipants(ctx, senderFriendRow._id, user._id);

      // Backfill settlements the sender recorded before I accepted
      await backfillSettlements(
        ctx,
        senderFriendRow._id,
        myFriendRow.linkedUserId!,
        args.friendId,
        user._id
      );
    }

    // Also check if I had a pending invite to them (mutual) and auto-accept
    const myInviteToThem = await ctx.db
      .query("invitations")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .first();

    if (myInviteToThem) {
      await ctx.db.patch(myInviteToThem._id, { status: "accepted" });
    }

    // Backfill participants for any splits I made involving the sender
    if (senderFriendRow) {
      await backfillParticipants(ctx, args.friendId, myFriendRow.linkedUserId!);

      // Backfill settlements I recorded before the sender accepted
      await backfillSettlements(
        ctx,
        args.friendId,
        user._id,
        senderFriendRow._id,
        myFriendRow.linkedUserId!
      );
    }

    // Activity: notify the sender that their invite was accepted
    if (myFriendRow.linkedUserId) {
      await insertActivity(ctx, {
        userId: myFriendRow.linkedUserId,
        actorId: user._id,
        actorName: user.name,
        type: "invitation_accepted",
        message: `${user.name} accepted your friend request`,
        friendId: senderFriendRow?._id,
      });
    }

    return { success: true };
  },
});

/**
 * Reject an invitation from the recipient's side.
 */
export const rejectInvitation = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    // This is my friend row with invite_received
    const myFriendRow = await ctx.db.get(args.friendId);
    if (!myFriendRow) {
      throw new Error("Friend not found");
    }
    requireOwner(myFriendRow.ownerId, user._id);

    if (myFriendRow.inviteStatus !== "invite_received") {
      throw new Error("No pending invite to reject");
    }

    // Mark my side as rejected
    await ctx.db.patch(args.friendId, { inviteStatus: "rejected" });

    // Find and update the sender's friend row
    if (myFriendRow.linkedUserId) {
      const senderFriendRow = await ctx.db
        .query("friends")
        .withIndex("by_owner_linkedUser", (q) =>
          q.eq("ownerId", myFriendRow.linkedUserId!).eq("linkedUserId", user._id)
        )
        .unique();

      if (senderFriendRow) {
        await ctx.db.patch(senderFriendRow._id, { inviteStatus: "rejected" });

        // Mark the invitation as rejected
        const invitation = await ctx.db
          .query("invitations")
          .withIndex("by_friend_status", (q) =>
            q.eq("friendId", senderFriendRow._id).eq("status", "pending")
          )
          .first();

        if (invitation) {
          await ctx.db.patch(invitation._id, { status: "rejected" });
        }
      }

      // Activity: notify the sender that their invite was rejected
      await insertActivity(ctx, {
        userId: myFriendRow.linkedUserId,
        actorId: user._id,
        actorName: user.name,
        type: "invitation_rejected",
        message: `${user.name} declined your friend request`,
        friendId: args.friendId,
      });
    }

    return { success: true };
  },
});

/**
 * Cancel a pending invitation (from sender's side)
 */
export const cancelInvitation = mutation({
  args: {
    clerkId: v.string(),
    invitationId: v.id("invitations"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);
    const invitation = await ctx.db.get(args.invitationId);
    if (!invitation) {
      throw new Error("Invitation not found");
    }
    requireOwner(invitation.senderId, user._id);

    if (invitation.status !== "pending") {
      throw new Error("Can only cancel pending invitations");
    }

    await ctx.db.patch(args.invitationId, { status: "cancelled" });

    // Activity: notify recipient if they're on the app
    const friend = await ctx.db.get(invitation.friendId);
    if (friend && friend.linkedUserId) {
      await insertActivity(ctx, {
        userId: friend.linkedUserId,
        actorId: user._id,
        actorName: user.name,
        type: "invitation_cancelled",
        message: `${user.name} withdrew their friend request`,
        friendId: invitation.friendId,
        invitationId: args.invitationId,
      });
    }

    return true;
  },
});

/**
 * List invitations sent by the current user
 */
export const listSentInvitations = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const invitations = await ctx.db
      .query("invitations")
      .withIndex("by_sender", (q) => q.eq("senderId", user._id))
      .collect();

    const enrichedInvitations = await Promise.all(
      invitations.map(async (invitation) => {
        const friend = await ctx.db.get(invitation.friendId);
        return {
          ...invitation,
          friend,
          isExpired: invitation.status === "expired",
        };
      })
    );

    return enrichedInvitations;
  },
});

/**
 * List received invitations for the current user.
 * Looks for friend rows with inviteStatus "invite_received".
 */
export const listReceivedInvitations = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const receivedFriends = await ctx.db
      .query("friends")
      .withIndex("by_owner_inviteStatus", (q) =>
        q.eq("ownerId", user._id).eq("inviteStatus", "invite_received")
      )
      .collect();

    const enriched = await Promise.all(
      receivedFriends.map(async (friend) => {
        let senderName: string | undefined;
        let senderAvatarUrl: string | undefined;
        let invitationId: string | undefined;

        if (friend.linkedUserId) {
          const sender = await ctx.db.get(friend.linkedUserId);
          if (sender) {
            senderName = sender.name;
            senderAvatarUrl = sender.avatarUrl;
          }

          // Find the corresponding invitation record
          const senderFriendRow = await ctx.db
            .query("friends")
            .withIndex("by_owner_linkedUser", (q) =>
              q.eq("ownerId", friend.linkedUserId!).eq("linkedUserId", user._id)
            )
            .unique();

          if (senderFriendRow) {
            const invitation = await ctx.db
              .query("invitations")
              .withIndex("by_friend_status", (q) =>
                q.eq("friendId", senderFriendRow._id).eq("status", "pending")
              )
              .first();

            if (invitation) {
              invitationId = invitation._id;
            }
          }
        }

        return {
          friendId: friend._id,
          senderName: senderName || friend.name,
          senderAvatarUrl: senderAvatarUrl || friend.avatarUrl,
          senderEmail: friend.email,
          invitationId,
          createdAt: friend.createdAt,
        };
      })
    );

    return enriched;
  },
});

/**
 * Resend an invitation (generates new token and extends expiry)
 */
export const resendInvitation = mutation({
  args: {
    friendId: v.id("friends"),
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }
    requireOwner(friend.ownerId, user._id);

    // Find existing invitation for this friend
    const invitationStatuses = ["pending", "rejected", "expired", "cancelled"] as const;
    let existingInvitation: Doc<"invitations"> | null = null;
    for (const status of invitationStatuses) {
      existingInvitation = await ctx.db
        .query("invitations")
        .withIndex("by_friend_status", (q) =>
          q.eq("friendId", args.friendId).eq("status", status)
        )
        .first();
      if (existingInvitation) {
        break;
      }
    }

    const token = await generateUniqueToken(ctx);
    const expiresAt = Date.now() + 7 * 24 * 60 * 60 * 1000;

    if (existingInvitation) {
      await ctx.db.patch(existingInvitation._id, {
        recipientEmail: normalizeEmail(friend.email),
        token,
        expiresAt,
        status: "pending",
      });

      // Reset friend status to invite_sent
      await ctx.db.patch(args.friendId, { inviteStatus: "invite_sent" });

      // Re-activate reciprocal row if it exists
      if (friend.linkedUserId) {
        const reciprocal = await getReciprocalFriend(
          ctx,
          friend.linkedUserId,
          user._id
        );

        if (reciprocal) {
          await ctx.db.patch(reciprocal._id, { inviteStatus: "invite_received" });
        }
      }

      return { invitationId: existingInvitation._id, token };
    }

    // No existing invitation — create a new one
    const invitationId = await ctx.db.insert("invitations", {
      senderId: user._id,
      friendId: args.friendId,
      recipientEmail: normalizeEmail(friend.email),
      recipientPhone: friend.phone,
      status: "pending",
      token,
      expiresAt,
      createdAt: Date.now(),
    });

    await ctx.db.patch(args.friendId, { inviteStatus: "invite_sent" });

    // Create reciprocal row if needed
    if (friend.linkedUserId) {
      const reciprocal = await getReciprocalFriend(
        ctx,
        friend.linkedUserId,
        user._id
      );

      if (!reciprocal) {
        await ctx.db.insert("friends", {
          ownerId: friend.linkedUserId,
          linkedUserId: user._id,
          name: user.name,
          email: user.email,
          phone: user.phone,
          avatarUrl: user.avatarUrl,
          isDummy: false,
          isSelf: false,
          inviteStatus: "invite_received",
          createdAt: Date.now(),
        });
      } else {
        await ctx.db.patch(reciprocal._id, { inviteStatus: "invite_received" });
      }
    }

    return { invitationId, token };
  },
});
