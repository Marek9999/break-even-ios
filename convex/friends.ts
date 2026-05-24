import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import {
  normalizeEmail,
  requireAuthenticatedUser,
  requireOwner,
} from "./lib/auth";
import { insertActivity } from "./activities";
import {
  backfillParticipants,
  backfillSettlements,
  createInvitationForFriend,
} from "./invitations";

/**
 * List all friends for the current user.
 * Includes all statuses so the UI can show badges appropriately.
 */
export const listFriends = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const friends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .collect();

    const linkedUsers = new Map<string, { username?: string }>();
    for (const friend of friends) {
      if (!friend.linkedUserId) continue;
      const linkedUser = await ctx.db.get(friend.linkedUserId);
      if (linkedUser) {
        linkedUsers.set(friend.linkedUserId.toString(), {
          username: linkedUser.username,
        });
      }
    }

    return friends.map((friend) => ({
      ...friend,
      username: friend.linkedUserId
        ? linkedUsers.get(friend.linkedUserId.toString())?.username
        : undefined,
    }));
  },
});

/**
 * Get a single friend by ID
 */
export const getFriendById = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      return null;
    }
    requireOwner(friend.ownerId, user._id);
    return friend;
  },
});

/**
 * Get the "self" friend entry for a user (represents "Me")
 */
export const getSelfFriend = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    return await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();
  },
});

/**
 * Check if an email belongs to an existing app user
 */
export const checkEmailOnApp = query({
  args: {
    clerkId: v.string(),
    email: v.string(),
  },
  handler: async (ctx, args) => {
    await requireAuthenticatedUser(ctx, args.clerkId);
    const normalizedEmail = normalizeEmail(args.email);
    if (!normalizedEmail) {
      return { exists: false, userName: undefined };
    }

    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", normalizedEmail))
      .unique();

    if (existingUser) {
      return { exists: true, userName: existingUser.name };
    }
    return { exists: false, userName: undefined };
  },
});

/**
 * Create a placeholder ("dummy") friend.
 *
 * Always creates a fresh placeholder row — no username/email auto-linking,
 * no dedup. Duplicate placeholders are explicitly allowed (two friends named
 * "Bob" can coexist; each can be linked independently later).
 *
 * `email`/`phone`/`linkedUsername` are kept as optional arguments for
 * backwards compatibility with existing callers, but `linkedUsername` is
 * ignored — the placeholder never silently becomes "almost linked". Use
 * `linkPlaceholderToUser` (manual) or `mergePlaceholderIntoInvite` to link.
 */
export const createDummyFriend = mutation({
  args: {
    clerkId: v.string(),
    name: v.string(),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
    linkedUsername: v.optional(v.string()),
    avatarEmoji: v.optional(v.string()),
    avatarColor: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const trimmedName = args.name.trim();
    if (!trimmedName) {
      throw new Error("Name is required");
    }

    const normalizedEmail = normalizeEmail(args.email);
    if (normalizedEmail && normalizedEmail === normalizeEmail(user.email)) {
      throw new Error("Cannot add yourself as a friend");
    }

    const friendId = await ctx.db.insert("friends", {
      ownerId: user._id,
      name: trimmedName,
      email: normalizedEmail,
      phone: args.phone,
      avatarEmoji: args.avatarEmoji,
      avatarColor: args.avatarColor,
      isDummy: true,
      isSelf: false,
      inviteStatus: "none",
      createdAt: Date.now(),
    });

    return { friendId, userExistsOnApp: false, isExisting: false };
  },
});

/**
 * Backfill `transactionParticipants` for every transaction that references the
 * given friend row (as payer or as a split target). Inserts a participant row
 * for `userId` if one doesn't already exist. Used when a placeholder gets
 * linked or merged into a real user, so the new linked user retroactively sees
 * past splits in their feed/history queries.
 */
async function backfillTransactionParticipantsForFriend(
  ctx: any,
  friendId: Id<"friends">,
  userId: Id<"users">
) {
  const txIds = new Set<string>();

  const splits = await ctx.db
    .query("splits")
    .withIndex("by_friend", (q: any) => q.eq("friendId", friendId))
    .collect();
  for (const split of splits) {
    txIds.add(split.transactionId.toString());
  }

  const paidTransactions = await ctx.db
    .query("transactions")
    .withIndex("by_paidBy", (q: any) => q.eq("paidById", friendId))
    .collect();
  for (const tx of paidTransactions) {
    txIds.add(tx._id.toString());
  }

  for (const txIdStr of txIds) {
    const txId = txIdStr as Id<"transactions">;
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
 * Link an existing placeholder friend to a real user (Scenario A).
 *
 * The placeholder's `_id` is preserved (it's referenced by past
 * `transactions.paidById`, `splits.friendId`, and `items.assignedToIds`),
 * so all past splits keep working without any rewriting.
 *
 * After linking, the standard invitation flow runs (creates the invitation,
 * the recipient-side reciprocal row, handles mutual auto-accept, etc.). On
 * mutual auto-accept, past splits are backfilled into the new linked user's
 * participant view.
 *
 * If the caller already has a different friend row linked to this user, the
 * mutation returns `{ conflict: "already_linked", existingFriendId }` so the
 * UI can offer to open the existing contact instead.
 */
export const linkPlaceholderToUser = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    targetUserId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    if (args.targetUserId === user._id) {
      throw new Error("Cannot link to yourself");
    }

    const placeholder = await ctx.db.get(args.friendId);
    if (!placeholder) {
      throw new Error("Friend not found");
    }
    requireOwner(placeholder.ownerId, user._id);

    if (placeholder.isSelf) {
      throw new Error("Cannot link the self friend row");
    }
    if (!placeholder.isDummy || placeholder.linkedUserId) {
      throw new Error("Friend is already linked to a user");
    }

    const targetUser = await ctx.db.get(args.targetUserId);
    if (!targetUser) {
      throw new Error("User not found");
    }

    // Soft conflict: another contact already linked to this user.
    const existingLinked = await ctx.db
      .query("friends")
      .withIndex("by_owner_linkedUser", (q) =>
        q.eq("ownerId", user._id).eq("linkedUserId", args.targetUserId)
      )
      .unique();

    if (existingLinked && existingLinked._id !== args.friendId) {
      return {
        conflict: "already_linked" as const,
        existingFriendId: existingLinked._id,
        friendId: args.friendId,
        invitationId: undefined,
        token: undefined,
        autoAccepted: false,
      };
    }

    // Promote the placeholder into a linked friend.
    await ctx.db.patch(args.friendId, {
      linkedUserId: args.targetUserId,
      isDummy: false,
      name: targetUser.name,
      email: targetUser.email,
      phone: targetUser.phone,
      avatarUrl: targetUser.avatarUrl,
    });

    const result = await createInvitationForFriend(ctx, user, args.friendId, {});

    if (result.autoAccepted) {
      await backfillTransactionParticipantsForFriend(
        ctx,
        args.friendId,
        args.targetUserId
      );
    }

    return {
      conflict: null,
      friendId: args.friendId,
      invitationId: result.invitationId,
      token: result.token,
      autoAccepted: result.autoAccepted,
    };
  },
});

/**
 * Merge a placeholder into an incoming invite (Scenario B).
 *
 * Use case: I have a placeholder for Bob from before; Bob signs up and sends
 * me an invite. From the received-invite UI I pick "Merge with existing
 * contact", choose the placeholder, and the two collapse into one accepted
 * friend row.
 *
 * The placeholder is the "winner" — its `_id` is preserved so past
 * `transactions`/`splits`/`items.assignedToIds` keep referencing the same
 * friend row. The incoming `invite_received` row is deleted, the sender's
 * reciprocal row flips to "accepted", the invitation is marked accepted,
 * and past splits are backfilled into the sender's participant view.
 */
export const mergePlaceholderIntoInvite = mutation({
  args: {
    clerkId: v.string(),
    placeholderFriendId: v.id("friends"),
    receivedFriendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    if (args.placeholderFriendId === args.receivedFriendId) {
      throw new Error("Placeholder and received invite must be different rows");
    }

    const placeholder = await ctx.db.get(args.placeholderFriendId);
    if (!placeholder) {
      throw new Error("Placeholder friend not found");
    }
    requireOwner(placeholder.ownerId, user._id);

    if (placeholder.isSelf) {
      throw new Error("Cannot merge the self friend row");
    }
    if (!placeholder.isDummy || placeholder.linkedUserId) {
      throw new Error("Selected contact is not a placeholder");
    }

    const received = await ctx.db.get(args.receivedFriendId);
    if (!received) {
      throw new Error("Received invite not found");
    }
    requireOwner(received.ownerId, user._id);

    if (received.inviteStatus !== "invite_received" || !received.linkedUserId) {
      throw new Error("Selected row is not a pending received invite");
    }

    const senderUserId = received.linkedUserId;
    const senderUser = await ctx.db.get(senderUserId);
    if (!senderUser) {
      throw new Error("Sender user not found");
    }

    // Promote the placeholder, copying the sender's identity onto it.
    await ctx.db.patch(args.placeholderFriendId, {
      linkedUserId: senderUserId,
      isDummy: false,
      inviteStatus: "accepted",
      name: senderUser.name,
      email: senderUser.email,
      phone: senderUser.phone,
      avatarUrl: senderUser.avatarUrl,
    });

    // Update the sender's friend row pointing at me to "accepted" with my
    // current profile, mirroring what acceptInvitationByFriend does.
    const senderFriendRow = await ctx.db
      .query("friends")
      .withIndex("by_owner_linkedUser", (q) =>
        q.eq("ownerId", senderUserId).eq("linkedUserId", user._id)
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

      const invitation = await ctx.db
        .query("invitations")
        .withIndex("by_friend_status", (q) =>
          q.eq("friendId", senderFriendRow._id).eq("status", "pending")
        )
        .first();

      if (invitation) {
        await ctx.db.patch(invitation._id, { status: "accepted" });
      }

      // Backfill participants and settlements on the sender's side so they see
      // any splits I made while they were a placeholder for me (rare but
      // possible if they had previously been linked, removed, and re-invited).
      await backfillParticipants(ctx, senderFriendRow._id, user._id);
      await backfillSettlements(
        ctx,
        senderFriendRow._id,
        senderUserId,
        args.placeholderFriendId,
        user._id
      );
    }

    // Backfill participants and settlements for the placeholder so the sender
    // retroactively sees past splits I made with this placeholder.
    await backfillTransactionParticipantsForFriend(
      ctx,
      args.placeholderFriendId,
      senderUserId
    );
    if (senderFriendRow) {
      await backfillSettlements(
        ctx,
        args.placeholderFriendId,
        user._id,
        senderFriendRow._id,
        senderUserId
      );
    }

    // Remove the duplicate received row — the placeholder now represents this person.
    await ctx.db.delete(args.receivedFriendId);

    await insertActivity(ctx, {
      userId: senderUserId,
      actorId: user._id,
      actorName: user.name,
      type: "invitation_accepted",
      message: `${user.name} accepted your friend request`,
      friendId: senderFriendRow?._id,
    });

    return { success: true, friendId: args.placeholderFriendId };
  },
});

/**
 * Update a friend's info
 */
export const updateFriend = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }
    requireOwner(friend.ownerId, user._id);

    // Only allow editing dummy friends
    if (!friend.isDummy) {
      throw new Error("Cannot edit linked friends");
    }

    const updates: Partial<{
      name: string;
      email: string;
      phone: string;
    }> = {};

    if (args.name !== undefined) updates.name = args.name;
    if (args.email !== undefined) updates.email = normalizeEmail(args.email);
    if (args.phone !== undefined) updates.phone = args.phone;

    await ctx.db.patch(args.friendId, updates);

    return args.friendId;
  },
});

/**
 * Soft-delete a friend. Sets inviteStatus to "removed_by_me" on my side
 * and "removed_by_them" on the reciprocal side. Cancels pending invitations.
 * Does NOT delete data — past splits/settlements remain intact.
 */
export const deleteFriend = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }
    requireOwner(friend.ownerId, user._id);

    if (friend.isSelf) {
      throw new Error("Cannot delete self");
    }

    // Soft-delete: mark as removed on my side
    await ctx.db.patch(args.friendId, { inviteStatus: "removed_by_me" });

    // Update the reciprocal friend row if it exists
    if (friend.linkedUserId) {
      const reciprocal = await ctx.db
        .query("friends")
        .withIndex("by_owner_linkedUser", (q) =>
          q.eq("ownerId", friend.linkedUserId!).eq("linkedUserId", friend.ownerId)
        )
        .unique();

      if (reciprocal) {
        await ctx.db.patch(reciprocal._id, { inviteStatus: "removed_by_them" });
      }
    }

    // Activity: notify the other user they were removed
    if (friend.linkedUserId) {
      await insertActivity(ctx, {
        userId: friend.linkedUserId,
        actorId: user._id,
        actorName: user.name,
        type: "friend_removed",
        message: `${user.name} removed you from their friends`,
        friendId: args.friendId,
      });
    }

    // Cancel any pending invitations for this friend
    const invitations = await ctx.db
      .query("invitations")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .collect();

    for (const invitation of invitations) {
      await ctx.db.patch(invitation._id, { status: "cancelled" });
    }

    return true;
  },
});

/**
 * Merge a dummy friend with a real user
 * Called when a user accepts an invitation
 */
export const mergeFriendWithUser = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const currentUser = await requireAuthenticatedUser(ctx, args.clerkId);
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }
    requireOwner(friend.ownerId, currentUser._id);

    if (!friend.isDummy) {
      throw new Error("Friend is already linked to a user");
    }

    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Update the friend to link to the real user
    await ctx.db.patch(args.friendId, {
      linkedUserId: args.userId,
      isDummy: false,
      inviteStatus: "accepted",
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
    });

    // Create a reciprocal friend entry for the new user
    const owner = await ctx.db.get(friend.ownerId);
    let reciprocalFriendId: Id<"friends"> | undefined;

    if (owner) {
      const existingReciprocal = await ctx.db
        .query("friends")
        .withIndex("by_owner", (q) => q.eq("ownerId", args.userId))
        .filter((q) => q.eq(q.field("linkedUserId"), owner._id))
        .unique();

      if (!existingReciprocal) {
        reciprocalFriendId = await ctx.db.insert("friends", {
          ownerId: args.userId,
          linkedUserId: owner._id,
          name: owner.name,
          email: owner.email,
          phone: owner.phone,
          avatarUrl: owner.avatarUrl,
          isDummy: false,
          isSelf: false,
          inviteStatus: "accepted",
          createdAt: Date.now(),
        });
      } else {
        await ctx.db.patch(existingReciprocal._id, { inviteStatus: "accepted" });
        reciprocalFriendId = existingReciprocal._id;
      }
    }

    // Backfill transactionParticipants for existing transactions involving this friend
    const splitsForFriend = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    for (const split of splitsForFriend) {
      const existingParticipant = await ctx.db
        .query("transactionParticipants")
        .withIndex("by_user_transaction", (q) =>
          q.eq("userId", args.userId).eq("transactionId", split.transactionId)
        )
        .unique();

      if (!existingParticipant) {
        await ctx.db.insert("transactionParticipants", {
          transactionId: split.transactionId,
          userId: args.userId,
          role: "participant",
          addedAt: Date.now(),
        });
      }
    }

    // Also check transactions where this friend was the payer
    const paidTransactions = await ctx.db
      .query("transactions")
      .withIndex("by_paidBy", (q) => q.eq("paidById", args.friendId))
      .collect();

    for (const tx of paidTransactions) {
      const existingParticipant = await ctx.db
        .query("transactionParticipants")
        .withIndex("by_user_transaction", (q) =>
          q.eq("userId", args.userId).eq("transactionId", tx._id)
        )
        .unique();

      if (!existingParticipant) {
        await ctx.db.insert("transactionParticipants", {
          transactionId: tx._id,
          userId: args.userId,
          role: "participant",
          addedAt: Date.now(),
        });
      }
    }

    // Backfill reciprocal settlements for existing settlements with this friend
    if (reciprocalFriendId) {
      const existingSettlements = await ctx.db
        .query("settlements")
        .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
        .collect();

      for (const settlement of existingSettlements) {
        // Only mirror settlements created by the owner (the other user's settlements)
        if (settlement.createdById.toString() !== friend.ownerId.toString()) continue;

        const flippedDirection = settlement.direction === "to_friend" ? "from_friend" : "to_friend";
        await ctx.db.insert("settlements", {
          createdById: args.userId,
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

    return args.friendId;
  },
});

/**
 * Helper function to convert amount using stored exchange rates
 * All rates are relative to USD
 */
function convertAmount(
  amount: number,
  fromCurrency: string,
  toCurrency: string,
  rates: { USD: number; EUR: number; GBP: number; CAD: number; AUD: number; INR: number; JPY: number }
): number {
  if (fromCurrency === toCurrency) {
    return amount;
  }

  const fromRate = rates[fromCurrency as keyof typeof rates];
  const toRate = rates[toCurrency as keyof typeof rates];

  if (!fromRate || !toRate) {
    // Unknown currency, return original amount
    return amount;
  }

  // Convert: amount in fromCurrency -> USD -> toCurrency
  const amountInUSD = amount / fromRate;
  const convertedAmount = amountInUSD * toRate;

  return convertedAmount;
}

/**
 * Resolve a friend entry to its underlying user ID.
 * Self-friends map to their ownerId; linked friends map to linkedUserId.
 * Dummy (unlinked) friends return undefined.
 */
function resolveToUserId(
  friend: { isSelf: boolean; ownerId: Id<"users">; linkedUserId?: Id<"users"> }
): Id<"users"> | undefined {
  if (friend.isSelf) return friend.ownerId;
  return friend.linkedUserId;
}

/**
 * Get friends who have pending balances with the user.
 *
 * Uses transactionParticipants to discover both own and shared transactions,
 * so balances update for BOTH the creator and the other participant.
 */
export const getFriendsWithBalances = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const userCurrency = user.defaultCurrency;

    const friends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .collect();

    // Build lookup: linkedUserId → current user's friend entry
    const friendByLinkedUserId = new Map<string, (typeof friends)[0]>();
    for (const f of friends) {
      if (f.linkedUserId && !f.isSelf) {
        friendByLinkedUserId.set(f.linkedUserId.toString(), f);
      }
    }

    // Ad-hoc friends: users involved in splits who aren't in our friend list.
    // Keyed by "user:<userId>" to avoid collisions with friend._id keys.
    const adHocFriendMap = new Map<string, {
      _id: string;
      name: string;
      email?: string;
      avatarUrl?: string;
      linkedUserId: string;
    }>();

    async function getOrCreateAdHocFriend(userId: Id<"users">): Promise<string> {
      const key = "user:" + userId.toString();
      if (!adHocFriendMap.has(key)) {
        const userRecord = await ctx.db.get(userId);
        if (userRecord) {
          adHocFriendMap.set(key, {
            _id: key,
            name: userRecord.name,
            email: userRecord.email,
            avatarUrl: userRecord.avatarUrl,
            linkedUserId: userId.toString(),
          });
        }
      }
      return key;
    }

    // Accumulator per friend._id (or ad-hoc "user:<id>" key)
    type BalanceEntry = {
      friendOwesUserConverted: number;
      userOwesFriendConverted: number;
      balancesByCurrency: Record<string, { friendOwes: number; userOwes: number }>;
      settlementsFromFriend: number;
      settlementsToFriend: number;
    };
    const balanceMap = new Map<string, BalanceEntry>();

    function getEntry(friendId: string): BalanceEntry {
      let entry = balanceMap.get(friendId);
      if (!entry) {
        entry = {
          friendOwesUserConverted: 0,
          userOwesFriendConverted: 0,
          balancesByCurrency: {},
          settlementsFromFriend: 0,
          settlementsToFriend: 0,
        };
        balanceMap.set(friendId, entry);
      }
      return entry;
    }

    // --- Collect ALL transactions involving this user ---

    const ownTransactions = await ctx.db
      .query("transactions")
      .withIndex("by_creator", (q) => q.eq("createdById", user._id))
      .collect();

    const participantRows = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();

    const ownTxIds = new Set(ownTransactions.map((t) => t._id));
    const sharedTransactions = [];
    for (const p of participantRows) {
      if (ownTxIds.has(p.transactionId)) continue;
      const tx = await ctx.db.get(p.transactionId);
      if (tx) sharedTransactions.push(tx);
    }

    const allTransactions = [...ownTransactions, ...sharedTransactions];

    // --- Process each transaction ---

    for (const tx of allTransactions) {
      const txCurrency = tx.currency;
      const rates = tx.exchangeRates?.rates;

      const payer = await ctx.db.get(tx.paidById);
      if (!payer) continue;

      const payerUserId = resolveToUserId(payer);
      const currentUserPaid =
        payerUserId !== undefined && payerUserId.toString() === user._id.toString();

      const splits = await ctx.db
        .query("splits")
        .withIndex("by_transaction", (q) => q.eq("transactionId", tx._id))
        .collect();

      for (const split of splits) {
        const splitTarget = await ctx.db.get(split.friendId);
        if (!splitTarget) continue;

        const splitUserId = resolveToUserId(splitTarget);

        const splitIsCurrentUser =
          splitUserId !== undefined && splitUserId.toString() === user._id.toString();

        if (currentUserPaid && !splitIsCurrentUser) {
          // Current user paid → the split target owes the current user
          let balanceKey: string | undefined;
          if (splitTarget.ownerId.toString() === user._id.toString()) {
            if (!splitTarget.isSelf) balanceKey = splitTarget._id.toString();
          } else if (splitUserId) {
            const localFriend = friendByLinkedUserId.get(splitUserId.toString());
            if (localFriend) {
              balanceKey = localFriend._id.toString();
            } else {
              balanceKey = await getOrCreateAdHocFriend(splitUserId);
            }
          }

          if (balanceKey) {
            const entry = getEntry(balanceKey);
            if (!entry.balancesByCurrency[txCurrency]) {
              entry.balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
            }
            entry.balancesByCurrency[txCurrency].friendOwes += split.amount;

            if (rates) {
              entry.friendOwesUserConverted += convertAmount(
                split.amount, txCurrency, userCurrency, rates
              );
            } else {
              entry.friendOwesUserConverted += split.amount;
            }
          }
        } else if (!currentUserPaid && splitIsCurrentUser) {
          // Someone else paid → current user owes the payer
          let balanceKey: string | undefined;
          if (payer.ownerId.toString() === user._id.toString()) {
            if (!payer.isSelf) balanceKey = payer._id.toString();
          } else if (payerUserId) {
            const localFriend = friendByLinkedUserId.get(payerUserId.toString());
            if (localFriend) {
              balanceKey = localFriend._id.toString();
            } else {
              balanceKey = await getOrCreateAdHocFriend(payerUserId);
            }
          }

          if (balanceKey) {
            const entry = getEntry(balanceKey);
            if (!entry.balancesByCurrency[txCurrency]) {
              entry.balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
            }
            entry.balancesByCurrency[txCurrency].userOwes += split.amount;

            if (rates) {
              entry.userOwesFriendConverted += convertAmount(
                split.amount, txCurrency, userCurrency, rates
              );
            } else {
              entry.userOwesFriendConverted += split.amount;
            }
          }
        }
      }
    }

    // --- Process settlements (own-side only; each user records their own) ---

    for (const friend of friends) {
      if (friend.isSelf) continue;

      const settlements = await ctx.db
        .query("settlements")
        .withIndex("by_friend", (q) => q.eq("friendId", friend._id))
        .collect();

      for (const settlement of settlements) {
        if (settlement.createdById.toString() !== user._id.toString()) continue;

        let convertedAmount = settlement.amount;
        if (settlement.currency !== userCurrency && settlement.exchangeRates) {
          convertedAmount = convertAmount(
            settlement.amount,
            settlement.currency,
            userCurrency,
            settlement.exchangeRates.rates
          );
        }

        const entry = getEntry(friend._id.toString());
        if (settlement.direction === "from_friend") {
          entry.settlementsFromFriend += convertedAmount;
        } else if (settlement.direction === "to_friend") {
          entry.settlementsToFriend += convertedAmount;
        }
      }
    }

    // --- Build result ---

    const friendsWithBalances = [];

    for (const friend of friends) {
      if (friend.isSelf) continue;

      const entry = balanceMap.get(friend._id.toString());
      if (!entry) continue;

      const netBalance =
        entry.friendOwesUserConverted -
        entry.settlementsFromFriend -
        entry.userOwesFriendConverted +
        entry.settlementsToFriend;

      if (Math.abs(netBalance) > 0.01) {
        friendsWithBalances.push({
          friend,
          friendOwesUser: entry.friendOwesUserConverted - entry.settlementsFromFriend,
          userOwesFriend: entry.userOwesFriendConverted - entry.settlementsToFriend,
          netBalance,
          isOwedToUser: netBalance > 0,
          balancesByCurrency: entry.balancesByCurrency,
        });
      }
    }

    // Include ad-hoc participants (users in splits who aren't in our friend list)
    for (const [key, adHocFriend] of adHocFriendMap) {
      const entry = balanceMap.get(key);
      if (!entry) continue;

      const netBalance =
        entry.friendOwesUserConverted -
        entry.userOwesFriendConverted;

      if (Math.abs(netBalance) > 0.01) {
        friendsWithBalances.push({
          friend: {
            _id: adHocFriend._id,
            _creationTime: 0,
            ownerId: user._id,
            linkedUserId: adHocFriend.linkedUserId,
            name: adHocFriend.name,
            email: adHocFriend.email,
            avatarUrl: adHocFriend.avatarUrl,
            isDummy: false,
            isSelf: false,
            inviteStatus: "none",
            createdAt: 0,
          },
          friendOwesUser: entry.friendOwesUserConverted,
          userOwesFriend: entry.userOwesFriendConverted,
          netBalance,
          isOwedToUser: netBalance > 0,
          balancesByCurrency: entry.balancesByCurrency,
        });
      }
    }

    return {
      balances: friendsWithBalances,
      userCurrency,
    };
  },
});
