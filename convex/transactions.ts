import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Doc, Id } from "./_generated/dataModel";
import { getAuthenticatedUser, isSplitSelectableStatus, requireOwner } from "./lib/auth";
import { insertActivity } from "./activities";

// Exchange rates validator for the supported currencies
const exchangeRatesValidator = v.optional(
  v.object({
    baseCurrency: v.string(),
    rates: v.object({
      USD: v.float64(),
      EUR: v.float64(),
      GBP: v.float64(),
      CAD: v.float64(),
      AUD: v.float64(),
      INR: v.float64(),
      JPY: v.float64(),
    }),
    fetchedAt: v.number(),
  })
);

async function getOwnedFriend(
  ctx: any,
  ownerId: Id<"users">,
  friendId: Id<"friends">
): Promise<Doc<"friends">> {
  const friend = await ctx.db.get(friendId);
  if (!friend) {
    throw new Error("Friend not found");
  }

  requireOwner(friend.ownerId, ownerId);
  return friend;
}

function assertUsableSplitFriend(friend: Doc<"friends">) {
  const status = friend.inviteStatus ?? "none";
  if (!friend.isSelf && !isSplitSelectableStatus(status)) {
    throw new Error("This friend is no longer available for new splits");
  }
}

async function validateOwnedTransactionTargets(
  ctx: any,
  ownerId: Id<"users">,
  paidById: Id<"friends">,
  splitFriendIds: Id<"friends">[],
  itemAssignedIds: Id<"friends">[] = []
) {
  const friendIds = new Set<string>([
    paidById,
    ...splitFriendIds,
    ...itemAssignedIds,
  ].map((id) => id.toString()));

  const friends = new Map<string, Doc<"friends">>();
  for (const friendId of friendIds) {
    const ownedFriend = await getOwnedFriend(ctx, ownerId, friendId as Id<"friends">);
    friends.set(friendId, ownedFriend);
  }

  const payer = friends.get(paidById.toString());
  if (!payer) {
    throw new Error("Payer not found");
  }
  assertUsableSplitFriend(payer);

  for (const friendId of splitFriendIds) {
    const friend = friends.get(friendId.toString());
    if (!friend) {
      throw new Error("Split participant not found");
    }
    assertUsableSplitFriend(friend);
  }

  for (const friendId of itemAssignedIds) {
    const friend = friends.get(friendId.toString());
    if (!friend) {
      throw new Error("Assigned friend not found");
    }
    assertUsableSplitFriend(friend);
  }
}

async function requireTransactionAccess(
  ctx: any,
  userId: Id<"users">,
  transactionId: Id<"transactions">
) {
  const transaction = await ctx.db.get(transactionId);
  if (!transaction) {
    throw new Error("Transaction not found");
  }

  if (transaction.createdById === userId) {
    return transaction;
  }

  const participant = await ctx.db
    .query("transactionParticipants")
    .withIndex("by_user_transaction", (q: any) =>
      q.eq("userId", userId).eq("transactionId", transactionId)
    )
    .unique();

  if (!participant) {
    throw new Error("Not authorized to access this transaction");
  }

  return transaction;
}

async function assertFriendOwnedByUser(
  ctx: any,
  friendId: Id<"friends">,
  ownerId: Id<"users">,
  fieldName: string
) {
  const friend = await ctx.db.get(friendId);
  if (!friend) {
    throw new Error(`${fieldName} friend not found`);
  }

  if (friend.ownerId.toString() !== ownerId.toString()) {
    throw new Error(`${fieldName} must belong to the authenticated user`);
  }

  return friend;
}

async function assertFriendIdsOwnedByUser(
  ctx: any,
  friendIds: Id<"friends">[],
  ownerId: Id<"users">,
  fieldName: string
) {
  for (const friendId of friendIds) {
    await assertFriendOwnedByUser(ctx, friendId, ownerId, fieldName);
  }
}

/**
 * Create a new transaction with splits
 */
export const createTransaction = mutation({
  args: {
    clerkId: v.string(),
    paidById: v.id("friends"),
    title: v.string(),
    emoji: v.string(),
    description: v.optional(v.string()),
    totalAmount: v.float64(),
    currency: v.string(),
    splitMethod: v.string(),
    receiptFileId: v.optional(v.id("_storage")),
    items: v.optional(
      v.array(
        v.object({
          id: v.string(),
          name: v.string(),
          quantity: v.number(),
          unitPrice: v.float64(),
          assignedToIds: v.array(v.id("friends")),
        })
      )
    ),
    date: v.number(),
    splits: v.array(
      v.object({
        friendId: v.id("friends"),
        amount: v.float64(),
        percentage: v.optional(v.float64()),
      })
    ),
    // Exchange rates snapshot at time of transaction creation
    exchangeRates: exchangeRatesValidator,
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);
    await validateOwnedTransactionTargets(
      ctx,
      user._id,
      args.paidById,
      args.splits.map((split) => split.friendId),
      args.items?.flatMap((item) => item.assignedToIds) ?? []
    );

    // Create the transaction
    const transactionId = await ctx.db.insert("transactions", {
      createdById: user._id,
      paidById: args.paidById,
      title: args.title,
      emoji: args.emoji,
      description: args.description,
      totalAmount: args.totalAmount,
      currency: args.currency,
      splitMethod: args.splitMethod,
      receiptFileId: args.receiptFileId,
      items: args.items,
      exchangeRates: args.exchangeRates,
      date: args.date,
      createdAt: Date.now(),
    });

    // Create splits for each participant
    for (const split of args.splits) {
      await ctx.db.insert("splits", {
        transactionId,
        friendId: split.friendId,
        amount: split.amount,
        percentage: split.percentage,
        createdAt: Date.now(),
      });
    }

    // Create transactionParticipants
    await syncTransactionParticipants(ctx, transactionId, user._id, args.splits.map(s => s.friendId));

    // Activity: notify all participants except the creator
    await notifyTransactionParticipants(
      ctx, transactionId, user._id, user.name,
      "split_created",
      `${user.name} created a new split "${args.title}"`,
      JSON.stringify({ title: args.title, emoji: args.emoji, amount: args.totalAmount, currency: args.currency })
    );

    return transactionId;
  },
});

/**
 * Sync transactionParticipants for a transaction.
 * Inserts rows for the creator and any linked+accepted friend participants.
 */
async function syncTransactionParticipants(
  ctx: any,
  transactionId: any,
  creatorUserId: any,
  friendIds: any[]
) {
  const addedUserIds = new Set<string>();

  // Always add the creator
  const existingCreator = await ctx.db
    .query("transactionParticipants")
    .withIndex("by_user_transaction", (q: any) =>
      q.eq("userId", creatorUserId).eq("transactionId", transactionId)
    )
    .unique();

  if (!existingCreator) {
    await ctx.db.insert("transactionParticipants", {
      transactionId,
      userId: creatorUserId,
      role: "creator",
      addedAt: Date.now(),
    });
  }
  addedUserIds.add(creatorUserId);

  // Add linked+accepted participants (resolve self-friends via ownerId)
  for (const friendId of friendIds) {
    const friend = await ctx.db.get(friendId);
    if (!friend) continue;

    const userId = resolveToUserId(friend);
    if (!userId) continue;
    if (addedUserIds.has(userId)) continue;
    if (!friend.isSelf && friend.inviteStatus !== "accepted") continue;

    const existing = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_user_transaction", (q: any) =>
        q.eq("userId", userId).eq("transactionId", transactionId)
      )
      .unique();

    if (!existing) {
      await ctx.db.insert("transactionParticipants", {
        transactionId,
        userId,
        role: "participant",
        addedAt: Date.now(),
      });
    }
    addedUserIds.add(userId);
  }

  // Remove participants no longer in the split (except creator)
  const allParticipants = await ctx.db
    .query("transactionParticipants")
    .withIndex("by_transaction", (q: any) => q.eq("transactionId", transactionId))
    .collect();

  for (const p of allParticipants) {
    if (p.role === "creator") continue;
    if (!addedUserIds.has(p.userId)) {
      await ctx.db.delete(p._id);
    }
  }
}

/**
 * Notify all transaction participants (except the actor) about an event.
 * Uses transactionParticipants table to find real userIds.
 */
async function notifyTransactionParticipants(
  ctx: any,
  transactionId: Id<"transactions">,
  actorId: Id<"users">,
  actorName: string,
  type: string,
  message: string,
  metadata?: string,
  participantUserIds?: Id<"users">[]
) {
  let userIds: Id<"users">[];
  if (participantUserIds) {
    userIds = participantUserIds;
  } else {
    const participants = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_transaction", (q: any) => q.eq("transactionId", transactionId))
      .collect();
    userIds = participants.map((p: any) => p.userId);
  }

  for (const userId of userIds) {
    if (userId.toString() === actorId.toString()) continue;
    await insertActivity(ctx, {
      userId,
      actorId,
      actorName,
      type,
      message,
      transactionId: type === "split_deleted" ? undefined : transactionId,
      metadata,
    });
  }
}

/**
 * Create a new transaction from JSON strings (for iOS compatibility)
 * This accepts splits and items as JSON strings to avoid Swift type casting issues
 */
export const createTransactionFromJson = mutation({
  args: {
    clerkId: v.string(),
    paidById: v.string(), // Friend ID as string
    title: v.string(),
    emoji: v.string(),
    totalAmount: v.string(), // Number as string
    currency: v.string(),
    splitMethod: v.string(),
    date: v.string(), // Number as string
    splitsJson: v.string(), // JSON string of splits array
    itemsJson: v.optional(v.string()), // JSON string of items array
    receiptFileId: v.optional(v.string()), // Storage ID as string
    exchangeRatesJson: v.optional(v.string()), // JSON string of exchange rates
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    // Parse the paidById
    const paidById = args.paidById as Id<"friends">;

    // Parse numeric values
    const totalAmount = parseFloat(args.totalAmount);
    const date = parseFloat(args.date);

    // Parse splits JSON
    interface SplitData {
      friendId: string;
      amount: number;
      percentage?: number | null;
    }
    const splits: SplitData[] = JSON.parse(args.splitsJson);

    // Parse items JSON if present
    interface ItemData {
      id: string;
      name: string;
      quantity: number;
      unitPrice: number;
      assignedToIds: string[];
    }
    let items: ItemData[] | undefined;
    if (args.itemsJson) {
      items = JSON.parse(args.itemsJson);
    }

    // Parse exchange rates JSON if present
    interface ExchangeRatesData {
      baseCurrency: string;
      rates: {
        USD: number;
        EUR: number;
        GBP: number;
        CAD: number;
        AUD: number;
        INR: number;
        JPY: number;
      };
      fetchedAt: number;
    }
    let exchangeRates: ExchangeRatesData | undefined;
    if (args.exchangeRatesJson) {
      exchangeRates = JSON.parse(args.exchangeRatesJson);
    }

    // Convert items to proper format with Id types
    const convertedItems = items?.map((item) => ({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      assignedToIds: item.assignedToIds.map((id) => id as Id<"friends">),
    }));
    await validateOwnedTransactionTargets(
      ctx,
      user._id,
      paidById,
      splits.map((split) => split.friendId as Id<"friends">),
      convertedItems?.flatMap((item) => item.assignedToIds) ?? []
    );

    // Create the transaction
    const transactionId = await ctx.db.insert("transactions", {
      createdById: user._id,
      paidById,
      title: args.title,
      emoji: args.emoji,
      totalAmount,
      currency: args.currency,
      splitMethod: args.splitMethod,
      receiptFileId: args.receiptFileId
        ? (args.receiptFileId as Id<"_storage">)
        : undefined,
      items: convertedItems,
      exchangeRates,
      date,
      createdAt: Date.now(),
    });

    // Create splits for each participant
    const splitFriendIds: Id<"friends">[] = [];
    for (const split of splits) {
      const friendId = split.friendId as Id<"friends">;
      splitFriendIds.push(friendId);

      await ctx.db.insert("splits", {
        transactionId,
        friendId,
        amount: split.amount,
        percentage: split.percentage ?? undefined,
        createdAt: Date.now(),
      });
    }

    // Create transactionParticipants
    await syncTransactionParticipants(ctx, transactionId, user._id, splitFriendIds);

    // Activity: notify all participants except the creator
    await notifyTransactionParticipants(
      ctx, transactionId, user._id, user.name,
      "split_created",
      `${user.name} created a new split "${args.title}"`,
      JSON.stringify({ title: args.title, emoji: args.emoji, amount: totalAmount, currency: args.currency })
    );

    return transactionId;
  },
});

/**
 * List all transactions for a user (own + shared via transactionParticipants)
 */
export const listTransactions = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    // Get own transactions
    const ownTransactions = await ctx.db
      .query("transactions")
      .withIndex("by_creator", (q) => q.eq("createdById", user._id))
      .collect();

    // Get shared transactions via transactionParticipants
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
    allTransactions.sort((a, b) => b.date - a.date);

    // Enrich transactions with splits and payer info
    const enrichedTransactions = await Promise.all(
      allTransactions.map(async (transaction) => {
        const splits = await ctx.db
          .query("splits")
          .withIndex("by_transaction", (q) =>
            q.eq("transactionId", transaction._id)
          )
          .collect();

        const payer = await ctx.db.get(transaction.paidById);

        // Enrich splits with friend info
        const enrichedSplits = await Promise.all(
          splits.map(async (split) => {
            const friend = await ctx.db.get(split.friendId);
            return { ...split, friend };
          })
        );

        // Resolve creator name
        const creator = await ctx.db.get(transaction.createdById);
        const createdByName = creator?.name;

        // Resolve lastEditedBy name
        let lastEditedByName: string | undefined;
        if (transaction.lastEditedBy) {
          const editor = await ctx.db.query("users").filter(q => q.eq(q.field("_id"), transaction.lastEditedBy!)).unique();
          if (editor) lastEditedByName = editor.name;
        }

        return {
          ...transaction,
          payer,
          splits: enrichedSplits,
          createdByName,
          lastEditedByName,
        };
      })
    );

    return enrichedTransactions;
  },
});

/**
 * Get a single transaction with full details
 */
export const getTransactionDetail = query({
  args: {
    transactionId: v.id("transactions"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx);
    const transaction = await requireTransactionAccess(
      ctx,
      user._id,
      args.transactionId
    );

    const splits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q) => q.eq("transactionId", args.transactionId))
      .collect();

    const payer = await ctx.db.get(transaction.paidById);

    // Enrich splits with friend info
    const enrichedSplits = await Promise.all(
      splits.map(async (split) => {
        const friend = await ctx.db.get(split.friendId);
        return { ...split, friend };
      })
    );

    // Get receipt URL if exists
    let receiptUrl: string | null = null;
    if (transaction.receiptFileId) {
      receiptUrl = await ctx.storage.getUrl(transaction.receiptFileId);
    }

    // Resolve creator name
    const creator = (await ctx.db.get(transaction.createdById)) as Doc<"users"> | null;
    const createdByName = creator?.name;

    // Resolve lastEditedBy name (backward compat)
    let lastEditedByName: string | undefined;
    if (transaction.lastEditedBy) {
      const editor = (await ctx.db.get(transaction.lastEditedBy)) as Doc<"users"> | null;
      if (editor) lastEditedByName = editor.name;
    }

    // Enrich full edit history with user names
    const enrichedEditHistory = await Promise.all(
      (transaction.editHistory ?? []).map(async (entry: { editedBy: Id<"users">; editedAt: number }) => {
        const editor = (await ctx.db.get(entry.editedBy)) as Doc<"users"> | null;
        return {
          editedByName: editor?.name ?? "Unknown",
          editedAt: entry.editedAt,
        };
      })
    );

    return {
      ...transaction,
      payer,
      splits: enrichedSplits,
      receiptUrl,
      createdByName,
      lastEditedByName,
      enrichedEditHistory,
    };
  },
});

/**
 * Get transactions involving a specific friend.
 * Includes shared transactions created by either user via transactionParticipants.
 */
export const getTransactionsWithFriend = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    const friend = await ctx.db.get(args.friendId);
    const friendUserId = friend ? resolveToUserId(friend) : undefined;

    return await collectTransactionsWithFriend(ctx, user._id, friendUserId, args.friendId);
  },
});



/**
 * Settle a specific amount with a friend
 * Creates a settlement record without modifying splits.
 * Uses transactionParticipants for accurate cross-user balance calculation.
 */
export const settleAmount = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    amount: v.string(),
    currency: v.string(),
    direction: v.string(),
    note: v.optional(v.string()),
    exchangeRatesJson: v.optional(v.string()),
    settledAt: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    await assertFriendOwnedByUser(ctx, args.friendId, user._id, "friendId");

    const amount = parseFloat(args.amount);
    if (isNaN(amount) || amount <= 0) {
      throw new Error("Invalid amount");
    }

    let exchangeRates = undefined;
    if (args.exchangeRatesJson) {
      exchangeRates = JSON.parse(args.exchangeRatesJson);
    }

    const friend = await ctx.db.get(args.friendId);
    const friendUserId = friend ? resolveToUserId(friend) : undefined;

    const balance = await computeBalanceWithFriend(
      ctx, user._id, friendUserId, args.currency, args.friendId, exchangeRates
    );

    const netBalance =
      balance.friendOwesUser - balance.settlementsFromFriend
      - balance.userOwesFriend + balance.settlementsToFriend;
    const balanceBeforeSettlement = Math.abs(netBalance);

    const settlementExchangeRates = exchangeRates || balance.firstTxWithRates?.exchangeRates;
    const settlementTime = args.settledAt ? parseFloat(args.settledAt) : Date.now();

    const settlementId = await ctx.db.insert("settlements", {
      createdById: user._id,
      friendId: args.friendId,
      amount,
      currency: args.currency,
      direction: args.direction,
      note: args.note,
      balanceBeforeSettlement,
      exchangeRates: settlementExchangeRates,
      settledAt: settlementTime,
      createdAt: Date.now(),
    });

    // Create reciprocal settlement for the other user so their balance updates too.
    // Only sync if both sides have accepted status — removed/rejected/pending friends
    // should not receive settlement mirrors.
    if (friend && friend.linkedUserId) {
      const reciprocalFriend = await ctx.db
        .query("friends")
        .withIndex("by_owner", (q) => q.eq("ownerId", friend.linkedUserId!))
        .filter((q) => q.eq(q.field("linkedUserId"), user._id))
        .unique();

      if (
        reciprocalFriend &&
        friend.inviteStatus === "accepted" &&
        reciprocalFriend.inviteStatus === "accepted"
      ) {
        const flippedDirection = args.direction === "to_friend" ? "from_friend" : "to_friend";
        await ctx.db.insert("settlements", {
          createdById: friend.linkedUserId!,
          friendId: reciprocalFriend._id,
          amount,
          currency: args.currency,
          direction: flippedDirection,
          note: args.note,
          balanceBeforeSettlement,
          exchangeRates: settlementExchangeRates,
          settledAt: settlementTime,
          createdAt: Date.now(),
        });

        // Activity: notify the other user about the settlement
        const directionLabel = args.direction === "to_friend" ? "paid" : "received from";
        await insertActivity(ctx, {
          userId: friend.linkedUserId!,
          actorId: user._id,
          actorName: user.name,
          type: "settlement_recorded",
          message: `${user.name} ${directionLabel} ${friend.name}: ${amount.toFixed(2)} ${args.currency}`,
          settlementId,
          friendId: reciprocalFriend._id,
          metadata: JSON.stringify({ amount, currency: args.currency, direction: args.direction }),
        });
      }
    }

    return {
      settlementId,
      settledAmount: amount,
    };
  },
});


/**
 * Get settlement history with a specific friend
 */
export const getSettlementHistory = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    await assertFriendOwnedByUser(ctx, args.friendId, user._id, "friendId");

    const settlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .order("desc")
      .collect();

    // Filter to only settlements created by this user
    return settlements.filter((s) => s.createdById === user._id);
  },
});

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
 * Collect all transactions where both the current user and a specific friend
 * are involved, using transactionParticipants to discover shared transactions.
 * Returns de-duplicated, enriched transactions sorted by date descending.
 */
async function collectTransactionsWithFriend(
  ctx: any,
  userId: Id<"users">,
  friendUserId: Id<"users"> | undefined,
  friendId?: Id<"friends">
) {
  // Own transactions
  const ownTransactions = await ctx.db
    .query("transactions")
    .withIndex("by_creator", (q: any) => q.eq("createdById", userId))
    .collect();

  // Shared transactions via transactionParticipants
  const participantRows = await ctx.db
    .query("transactionParticipants")
    .withIndex("by_user", (q: any) => q.eq("userId", userId))
    .collect();

  const ownTxIds = new Set(ownTransactions.map((t: any) => t._id.toString()));
  const sharedTransactions: any[] = [];
  for (const p of participantRows) {
    if (ownTxIds.has(p.transactionId.toString())) continue;
    const tx = await ctx.db.get(p.transactionId);
    if (tx) sharedTransactions.push(tx);
  }

  const allTransactions = [...ownTransactions, ...sharedTransactions];

  // Filter to transactions involving the target friend
  const result: any[] = [];
  const seenTxIds = new Set<string>();

  for (const tx of allTransactions) {
    if (seenTxIds.has(tx._id.toString())) continue;

    const splits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q: any) => q.eq("transactionId", tx._id))
      .collect();

    let involvesUser = false;
    let involvesFriend = false;

    for (const split of splits) {
      const target = await ctx.db.get(split.friendId);
      if (!target) continue;
      const targetUserId = resolveToUserId(target);
      if (targetUserId?.toString() === userId.toString()) involvesUser = true;
      if (friendUserId && targetUserId?.toString() === friendUserId.toString()) involvesFriend = true;
      if (!friendUserId && friendId && split.friendId.toString() === friendId.toString()) involvesFriend = true;
    }

    const payer = await ctx.db.get(tx.paidById);
    if (payer) {
      const payerUserId = resolveToUserId(payer);
      if (payerUserId?.toString() === userId.toString()) involvesUser = true;
      if (friendUserId && payerUserId?.toString() === friendUserId.toString()) involvesFriend = true;
      if (!friendUserId && friendId && tx.paidById.toString() === friendId.toString()) involvesFriend = true;
    }

    if (involvesUser && involvesFriend) {
      const enrichedSplits = await Promise.all(
        splits.map(async (split: any) => {
          const friend = await ctx.db.get(split.friendId);
          return { ...split, friend };
        })
      );

      const creator = await ctx.db.get(tx.createdById);
      const createdByName = creator?.name;

      let lastEditedByName: string | undefined;
      if (tx.lastEditedBy) {
        const editor = await ctx.db.query("users").filter((q: any) => q.eq(q.field("_id"), tx.lastEditedBy)).unique();
        if (editor) lastEditedByName = editor.name;
      }

      seenTxIds.add(tx._id.toString());
      result.push({
        ...tx,
        payer,
        splits: enrichedSplits,
        createdByName,
        lastEditedByName,
      });
    }
  }

  result.sort((a: any, b: any) => b.date - a.date);
  return result;
}

/**
 * Compute the balance between the current user and a specific friend,
 * including shared transactions via transactionParticipants.
 * Returns friendOwesUser, userOwesFriend, settlements, and the first tx with rates.
 */
async function computeBalanceWithFriend(
  ctx: any,
  userId: Id<"users">,
  friendUserId: Id<"users"> | undefined,
  targetCurrency: string,
  friendId: Id<"friends">,
  fallbackRates?: any
) {
  // Get all transactions involving both users
  const ownTransactions = await ctx.db
    .query("transactions")
    .withIndex("by_creator", (q: any) => q.eq("createdById", userId))
    .collect();

  const participantRows = await ctx.db
    .query("transactionParticipants")
    .withIndex("by_user", (q: any) => q.eq("userId", userId))
    .collect();

  const ownTxIds = new Set(ownTransactions.map((t: any) => t._id.toString()));
  const sharedTransactions: any[] = [];
  for (const p of participantRows) {
    if (ownTxIds.has(p.transactionId.toString())) continue;
    const tx = await ctx.db.get(p.transactionId);
    if (tx) sharedTransactions.push(tx);
  }

  const allTransactions = [...ownTransactions, ...sharedTransactions];

  let friendOwesUser = 0;
  let userOwesFriend = 0;
  let firstTxWithRates: any = null;
  const balancesByCurrency: Record<string, { friendOwes: number; userOwes: number }> = {};

  for (const tx of allTransactions) {
    const txCurrency = tx.currency;
    const rates = tx.exchangeRates?.rates || fallbackRates?.rates;

    const payer = await ctx.db.get(tx.paidById);
    if (!payer) continue;

    const payerUserId = resolveToUserId(payer);
    const currentUserPaid = payerUserId?.toString() === userId.toString();

    if (!firstTxWithRates && tx.exchangeRates) {
      firstTxWithRates = tx;
    }

    const splits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q: any) => q.eq("transactionId", tx._id))
      .collect();

    for (const split of splits) {
      const target = await ctx.db.get(split.friendId);
      if (!target) continue;

      const targetUserId = resolveToUserId(target);
      const splitIsCurrentUser = targetUserId?.toString() === userId.toString();
      const splitIsFriend = (friendUserId && targetUserId?.toString() === friendUserId.toString())
        || (!friendUserId && split.friendId.toString() === friendId.toString());
      const payerIsFriend = (friendUserId && payerUserId?.toString() === friendUserId.toString())
        || (!friendUserId && tx.paidById.toString() === friendId.toString());

      if (currentUserPaid && splitIsFriend) {
        if (!balancesByCurrency[txCurrency]) {
          balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
        }
        balancesByCurrency[txCurrency].friendOwes += split.amount;

        if (rates && txCurrency !== targetCurrency) {
          friendOwesUser += convertAmountHelper(split.amount, txCurrency, targetCurrency, rates);
        } else {
          friendOwesUser += split.amount;
        }
      } else if (!currentUserPaid && splitIsCurrentUser && payerIsFriend) {
        if (!balancesByCurrency[txCurrency]) {
          balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
        }
        balancesByCurrency[txCurrency].userOwes += split.amount;

        if (rates && txCurrency !== targetCurrency) {
          userOwesFriend += convertAmountHelper(split.amount, txCurrency, targetCurrency, rates);
        } else {
          userOwesFriend += split.amount;
        }
      }
    }
  }

  // Process settlements (own-side only)
  const settlements = await ctx.db
    .query("settlements")
    .withIndex("by_friend", (q: any) => q.eq("friendId", friendId))
    .collect();

  let settlementsFromFriend = 0;
  let settlementsToFriend = 0;

  for (const s of settlements) {
    if (s.createdById.toString() !== userId.toString()) continue;

    let convertedAmount = s.amount;
    if (s.currency !== targetCurrency && s.exchangeRates?.rates) {
      convertedAmount = convertAmountHelper(s.amount, s.currency, targetCurrency, s.exchangeRates.rates);
    }

    if (s.direction === "from_friend") {
      settlementsFromFriend += convertedAmount;
    } else if (s.direction === "to_friend") {
      settlementsToFriend += convertedAmount;
    }
  }

  return {
    friendOwesUser,
    userOwesFriend,
    settlementsFromFriend,
    settlementsToFriend,
    balancesByCurrency,
    firstTxWithRates,
  };
}

/**
 * Get activity (transactions + settlements) with a specific friend
 * Used for the PersonDetailSheet to show a combined chronological feed.
 * Includes shared transactions created by either user via transactionParticipants.
 */
export const getActivityWithFriend = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    await assertFriendOwnedByUser(ctx, args.friendId, user._id, "friendId");

    const userCurrency = user.defaultCurrency;

    // Resolve the friend to a user ID for cross-user transaction lookup
    const friend = await ctx.db.get(args.friendId);
    const friendUserId = friend ? resolveToUserId(friend) : undefined;

    const rawTransactions = await collectTransactionsWithFriend(ctx, user._id, friendUserId, args.friendId);

    const transactions = rawTransactions.map((tx: any) => {
      const payerUserId = tx.payer ? resolveToUserId(tx.payer) : undefined;
      const viewerPaid = payerUserId?.toString() === user._id.toString();
      const friendPaid = (friendUserId && payerUserId?.toString() === friendUserId.toString())
        || (!friendUserId && tx.paidById.toString() === args.friendId.toString());

      let friendSplitAmount: number | null = null;
      let viewerSplitAmount: number | null = null;

      for (const split of tx.splits) {
        const target = split.friend;
        if (!target) continue;
        const targetUserId = resolveToUserId(target);
        if (targetUserId?.toString() === user._id.toString()) {
          viewerSplitAmount = split.amount;
        }
        if ((friendUserId && targetUserId?.toString() === friendUserId.toString())
          || (!friendUserId && split.friendId.toString() === args.friendId.toString())) {
          friendSplitAmount = split.amount;
        }
      }

      return {
        ...tx,
        viewerPaid: viewerPaid ?? false,
        friendPaid: friendPaid ?? false,
        friendSplitAmount,
        viewerSplitAmount,
      };
    });

    // Get settlements with this friend (created by this user)
    const settlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    const filteredSettlements = settlements
      .filter((s) => s.createdById.toString() === user._id.toString())
      .map((s) => {
        let convertedAmount = s.amount;
        let convertedBalanceBefore = s.balanceBeforeSettlement ?? null;
        
        if (s.currency !== userCurrency && s.exchangeRates) {
          convertedAmount = convertAmountHelper(
            s.amount,
            s.currency,
            userCurrency,
            s.exchangeRates.rates
          );
          if (s.balanceBeforeSettlement !== undefined) {
            convertedBalanceBefore = convertAmountHelper(
              s.balanceBeforeSettlement,
              s.currency,
              userCurrency,
              s.exchangeRates.rates
            );
          }
        }
        return {
          ...s,
          convertedAmount,
          convertedCurrency: userCurrency,
          convertedBalanceBefore,
        };
      });

    return {
      transactions,
      settlements: filteredSettlements,
      userCurrency,
    };
  },
});

/**
 * Helper function to convert amount using stored exchange rates
 * All rates are relative to USD
 */
function convertAmountHelper(
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
    return amount;
  }

  const amountInUSD = amount / fromRate;
  return amountInUSD * toRate;
}

/**
 * Get balance summary with a specific friend.
 * Uses transactionParticipants for cross-user transaction discovery.
 */
export const getBalanceWithFriend = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    await assertFriendOwnedByUser(ctx, args.friendId, user._id, "friendId");

    const userCurrency = user.defaultCurrency;

    const friend = await ctx.db.get(args.friendId);
    const friendUserId = friend ? resolveToUserId(friend) : undefined;

    const balance = await computeBalanceWithFriend(
      ctx, user._id, friendUserId, userCurrency, args.friendId
    );

    const effectiveFriendOwes = balance.friendOwesUser - balance.settlementsFromFriend;
    const effectiveUserOwes = balance.userOwesFriend - balance.settlementsToFriend;

    return {
      friendOwesUser: effectiveFriendOwes,
      userOwesFriend: effectiveUserOwes,
      netBalance: effectiveFriendOwes - effectiveUserOwes,
      userCurrency,
      balancesByCurrency: balance.balancesByCurrency,
    };
  },
});

/**
 * Update an existing transaction and replace its splits (for iOS compatibility)
 * Uses the same JSON-string approach as createTransactionFromJson
 */
export const updateTransactionFromJson = mutation({
  args: {
    transactionId: v.id("transactions"),
    clerkId: v.string(),
    paidById: v.string(),
    title: v.string(),
    emoji: v.string(),
    totalAmount: v.string(),
    currency: v.string(),
    splitMethod: v.string(),
    date: v.string(),
    splitsJson: v.string(),
    itemsJson: v.optional(v.string()),
    receiptFileId: v.optional(v.string()),
    exchangeRatesJson: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    const existing = await ctx.db.get(args.transactionId);
    if (!existing) {
      throw new Error("Transaction not found");
    }

    // Allow edit if user is creator or a participant
    if (existing.createdById !== user._id) {
      const participant = await ctx.db
        .query("transactionParticipants")
        .withIndex("by_user_transaction", (q) =>
          q.eq("userId", user._id).eq("transactionId", args.transactionId)
        )
        .unique();
      if (!participant) {
        throw new Error("Not authorized to edit this transaction");
      }
    }

    const existingSplits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q) =>
        q.eq("transactionId", args.transactionId)
      )
      .collect();

    const creatorParticipantIds = new Set(
      existingSplits.map((split) => split.friendId.toString())
    );

    const totalAmount = parseFloat(args.totalAmount);
    const date = parseFloat(args.date);

    interface SplitData {
      friendId: string;
      amount: number;
      percentage?: number | null;
    }
    const splits: SplitData[] = JSON.parse(args.splitsJson);

    interface ItemData {
      id: string;
      name: string;
      quantity: number;
      unitPrice: number;
      assignedToIds: string[];
    }
    let items: ItemData[] | undefined;
    if (args.itemsJson) {
      items = JSON.parse(args.itemsJson);
    }

    interface ExchangeRatesData {
      baseCurrency: string;
      rates: {
        USD: number;
        EUR: number;
        GBP: number;
        CAD: number;
        AUD: number;
        INR: number;
        JPY: number;
      };
      fetchedAt: number;
    }
    let exchangeRates: ExchangeRatesData | undefined;
    if (args.exchangeRatesJson) {
      exchangeRates = JSON.parse(args.exchangeRatesJson);
    }

    // When a non-creator edits, remap friend IDs from the editor's space to the creator's space
    const isEditorTheCreator = user._id === existing.createdById;
    const remapFriendId = async (
      editorFriendId: Id<"friends">,
      fieldName: string
    ): Promise<Id<"friends">> => {
      if (isEditorTheCreator) {
        await assertFriendOwnedByUser(
          ctx,
          editorFriendId,
          existing.createdById,
          fieldName
        );
        return editorFriendId;
      }

      if (creatorParticipantIds.has(editorFriendId.toString())) {
        return editorFriendId;
      }

      const editorFriend = await ctx.db.get(editorFriendId);
      if (!editorFriend) {
        throw new Error(`${fieldName} friend not found`);
      }

      if (editorFriend.ownerId.toString() !== user._id.toString()) {
        throw new Error(`${fieldName} must reference an existing split participant`);
      }

      const targetUserId = resolveToUserId(editorFriend);
      if (!targetUserId) {
        throw new Error(`${fieldName} must reference an existing split participant`);
      }

      // If the target user IS the creator, find the creator's self-friend
      if (targetUserId.toString() === existing.createdById.toString()) {
        const creatorSelf = await ctx.db
          .query("friends")
          .withIndex("by_owner_isSelf", (q) =>
            q.eq("ownerId", existing.createdById).eq("isSelf", true)
          )
          .unique();
        if (creatorSelf && creatorParticipantIds.has(creatorSelf._id.toString())) {
          return creatorSelf._id;
        }
      }

      // Otherwise find the creator's friend entry that links to this user
      const creatorFriend = await ctx.db
        .query("friends")
        .withIndex("by_owner_linkedUser", (q) =>
          q.eq("ownerId", existing.createdById).eq("linkedUserId", targetUserId)
        )
        .unique();
      if (creatorFriend && creatorParticipantIds.has(creatorFriend._id.toString())) {
        return creatorFriend._id;
      }

      throw new Error(`${fieldName} must reference an existing split participant`);
    };

    const paidById = await remapFriendId(
      args.paidById as Id<"friends">,
      "paidById"
    );

    const convertedItems = items ? await Promise.all(items.map(async (item) => ({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      assignedToIds: await Promise.all(
        item.assignedToIds.map((id) =>
          remapFriendId(id as Id<"friends">, "item assignment")
        )
      ),
    }))) : undefined;

    const remappedSplits = await Promise.all(
      splits.map(async (split) => ({
        ...split,
        friendId: await remapFriendId(
          split.friendId as Id<"friends">,
          "split participant"
        ),
      }))
    );

    if (!isEditorTheCreator) {
      const remappedParticipantIds = new Set(
        remappedSplits.map((split) => split.friendId.toString())
      );

      if (
        remappedParticipantIds.size !== creatorParticipantIds.size ||
        Array.from(creatorParticipantIds).some(
          (friendId) => !remappedParticipantIds.has(friendId)
        )
      ) {
        throw new Error("Non-creators cannot add or remove split participants");
      }

      if (!creatorParticipantIds.has(paidById.toString())) {
        throw new Error("Non-creators can only choose a payer from the existing split participants");
      }
    }

    // Update the transaction document with edit tracking
    const editEntry = { editedBy: user._id, editedAt: Date.now() };
    const previousHistory = existing.editHistory ?? [];

    await ctx.db.patch(args.transactionId, {
      paidById,
      title: args.title,
      emoji: args.emoji,
      totalAmount,
      currency: args.currency,
      splitMethod: args.splitMethod,
      receiptFileId: args.receiptFileId
        ? (args.receiptFileId as Id<"_storage">)
        : undefined,
      items: convertedItems,
      exchangeRates,
      date,
      lastEditedBy: user._id,
      lastEditedAt: editEntry.editedAt,
      editHistory: [...previousHistory, editEntry],
    });

    for (const split of existingSplits) {
      await ctx.db.delete(split._id);
    }

    // Create new splits (remapped to creator's friend space)
    const splitFriendIds: Id<"friends">[] = [];
    for (const split of remappedSplits) {
      splitFriendIds.push(split.friendId);
      await ctx.db.insert("splits", {
        transactionId: args.transactionId,
        friendId: split.friendId,
        amount: split.amount,
        percentage: split.percentage ?? undefined,
        createdAt: Date.now(),
      });
    }

    // Capture old participants before re-sync (for activity notifications)
    const oldParticipants = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_transaction", (q: any) => q.eq("transactionId", args.transactionId))
      .collect();
    const oldParticipantUserIds = new Set(oldParticipants.map((p: any) => p.userId.toString()));

    // Re-sync transactionParticipants
    await syncTransactionParticipants(ctx, args.transactionId, existing.createdById, splitFriendIds);

    // Get new participants after sync
    const newParticipants = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_transaction", (q: any) => q.eq("transactionId", args.transactionId))
      .collect();
    const newParticipantUserIds = new Set(newParticipants.map((p: any) => p.userId.toString()));

    // Union of old + new participants to notify everyone affected
    const allAffectedUserIds = new Set([...oldParticipantUserIds, ...newParticipantUserIds]);
    const allAffected = Array.from(allAffectedUserIds).map((id) => id as Id<"users">);

    await notifyTransactionParticipants(
      ctx, args.transactionId, user._id, user.name,
      "split_edited",
      `${user.name} edited the split "${args.title}"`,
      JSON.stringify({ title: args.title, emoji: args.emoji, amount: totalAmount, currency: args.currency }),
      allAffected
    );

    return args.transactionId;
  },
});

/**
 * Delete a transaction and all its splits
 */
export const deleteTransaction = mutation({
  args: {
    transactionId: v.id("transactions"),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx);
    const transaction = await ctx.db.get(args.transactionId);
    if (!transaction) {
      throw new Error("Transaction not found");
    }
    requireOwner(transaction.createdById, user._id, "Only the split creator can delete this transaction");

    // Capture participants and metadata BEFORE deletion for activity notifications
    const participants = await ctx.db
      .query("transactionParticipants")
      .withIndex("by_transaction", (q) => q.eq("transactionId", args.transactionId))
      .collect();
    const participantUserIds = participants.map((p) => p.userId as Id<"users">);
    const txTitle = transaction.title;
    const txEmoji = transaction.emoji;

    // Delete all splits
    const splits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q) => q.eq("transactionId", args.transactionId))
      .collect();

    for (const split of splits) {
      await ctx.db.delete(split._id);
    }

    // Delete transactionParticipants
    for (const p of participants) {
      await ctx.db.delete(p._id);
    }

    // Delete transaction
    await ctx.db.delete(args.transactionId);

    // Activity: notify all former participants except the deleter
    await notifyTransactionParticipants(
      ctx, args.transactionId, user._id, user.name,
      "split_deleted",
      `${user.name} deleted the split "${txTitle}"`,
      JSON.stringify({ title: txTitle, emoji: txEmoji }),
      participantUserIds
    );

    return true;
  },
});
