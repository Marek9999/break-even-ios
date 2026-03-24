import { mutation } from "./_generated/server";

/**
 * One-time migration: backfill inviteStatus on all friends rows
 * and create transactionParticipants for existing linked transactions.
 *
 * Run via Convex dashboard: mutations > migrations:backfillInviteSystemV1
 */
export const backfillInviteSystemV1 = mutation({
  args: {},
  handler: async (ctx) => {
    // --- Phase 1: Backfill inviteStatus on friends ---
    const allFriends = await ctx.db.query("friends").collect();
    let friendsPatched = 0;

    for (const friend of allFriends) {
      if ((friend as any).inviteStatus) continue; // already migrated

      let inviteStatus = "none";

      if (friend.isSelf) {
        inviteStatus = "none";
      } else if (!friend.isDummy && friend.linkedUserId) {
        inviteStatus = "accepted";
      } else if (friend.isDummy) {
        const pendingInvite = await ctx.db
          .query("invitations")
          .withIndex("by_friend", (q) => q.eq("friendId", friend._id))
          .filter((q) => q.eq(q.field("status"), "pending"))
          .first();
        inviteStatus = pendingInvite ? "invite_sent" : "invite_sent";
      }

      await ctx.db.patch(friend._id, { inviteStatus });
      friendsPatched++;
    }

    // --- Phase 2: Backfill transactionParticipants ---
    const allTransactions = await ctx.db.query("transactions").collect();
    let participantsCreated = 0;

    for (const tx of allTransactions) {
      const existingParticipants = await ctx.db
        .query("transactionParticipants")
        .withIndex("by_transaction", (q) => q.eq("transactionId", tx._id))
        .collect();

      if (existingParticipants.length > 0) continue; // already migrated

      // Add creator as participant
      await ctx.db.insert("transactionParticipants", {
        transactionId: tx._id,
        userId: tx.createdById,
        role: "creator",
        addedAt: tx.createdAt,
      });
      participantsCreated++;

      // Add all linked+accepted split participants
      const splits = await ctx.db
        .query("splits")
        .withIndex("by_transaction", (q) => q.eq("transactionId", tx._id))
        .collect();

      const addedUserIds = new Set<string>([tx.createdById]);

      for (const split of splits) {
        const friend = await ctx.db.get(split.friendId);
        if (!friend || !friend.linkedUserId) continue;
        if (addedUserIds.has(friend.linkedUserId)) continue;

        const friendStatus = (friend as any).inviteStatus;
        if (friendStatus === "accepted") {
          await ctx.db.insert("transactionParticipants", {
            transactionId: tx._id,
            userId: friend.linkedUserId,
            role: "participant",
            addedAt: Date.now(),
          });
          addedUserIds.add(friend.linkedUserId);
          participantsCreated++;
        }
      }
    }

    return {
      friendsPatched,
      participantsCreated,
      totalFriends: allFriends.length,
      totalTransactions: allTransactions.length,
    };
  },
});
