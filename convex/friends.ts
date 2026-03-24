import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import {
  normalizeEmail,
  requireAuthenticatedUser,
  requireOwner,
} from "./lib/auth";

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

    return friends;
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
 * Create a friend entry. Does NOT auto-link or create reciprocal rows.
 * If the email matches an existing user, stores the linkedUserId reference
 * but keeps isDummy true until the invite is accepted.
 * Returns the friendId and whether the user exists on the app.
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
    const normalizedEmail = normalizeEmail(args.email);

    // Block self-invite by email
    if (normalizedEmail && normalizedEmail === normalizeEmail(user.email)) {
      throw new Error("Cannot add yourself as a friend");
    }

    // Block self-invite by username
    if (
      args.linkedUsername &&
      user.username &&
      args.linkedUsername.toLowerCase() === user.username.toLowerCase()
    ) {
      throw new Error("Cannot add yourself as a friend");
    }

    // If a username was provided, resolve it to a user first
    let resolvedUser: {
      _id: Id<"users">;
      name: string;
      email: string;
      phone?: string;
      avatarUrl?: string;
    } | null = null;

    if (args.linkedUsername) {
      const foundUser = await ctx.db
        .query("users")
        .withIndex("by_username", (q) =>
          q.eq("username", args.linkedUsername!.toLowerCase().trim())
        )
        .unique();

      if (!foundUser) {
        // Username not found — fall through to create a dummy friend
      } else {
        // Check if we already have a friend row linked to this user
        const existingByLinkedUser = await ctx.db
          .query("friends")
          .withIndex("by_owner_linkedUser", (q) =>
            q.eq("ownerId", user._id).eq("linkedUserId", foundUser._id)
          )
          .unique();

        if (existingByLinkedUser) {
          if (
            existingByLinkedUser.inviteStatus === "removed_by_me" ||
            existingByLinkedUser.inviteStatus === "rejected"
          ) {
            await ctx.db.patch(existingByLinkedUser._id, {
              inviteStatus: "invite_sent",
            });
          }
          return {
            friendId: existingByLinkedUser._id,
            userExistsOnApp: true,
            isExisting: true,
          };
        }

        resolvedUser = foundUser;
      }
    }

    // Check if a friend with this email already exists for this owner
    if (normalizedEmail) {
      const existingByEmail = await ctx.db
        .query("friends")
        .withIndex("by_owner_email", (q) =>
          q.eq("ownerId", user._id).eq("email", normalizedEmail)
        )
        .unique();

      if (existingByEmail) {
        if (existingByEmail.inviteStatus === "removed_by_me" || existingByEmail.inviteStatus === "rejected") {
          await ctx.db.patch(existingByEmail._id, { inviteStatus: "invite_sent" });
        }
        const existingAppUser = await ctx.db
          .query("users")
          .withIndex("by_email", (q) => q.eq("email", normalizedEmail))
          .unique();
        return {
          friendId: existingByEmail._id,
          userExistsOnApp: !!existingAppUser,
          isExisting: true,
        };
      }
    }

    // Determine linkedUserId from username resolution or email lookup
    let linkedUserId: Id<"users"> | undefined = resolvedUser?._id;
    let userExistsOnApp = !!resolvedUser;
    let friendName = args.name;
    let friendEmail = normalizedEmail;
    let friendAvatarUrl: string | undefined = undefined;

    if (resolvedUser) {
      friendName = resolvedUser.name;
      friendEmail = resolvedUser.email;
      friendAvatarUrl = resolvedUser.avatarUrl;
    } else if (normalizedEmail) {
      const existingUser = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", normalizedEmail))
        .unique();

      if (existingUser) {
        linkedUserId = existingUser._id;
        userExistsOnApp = true;
      }
    }

    const friendId = await ctx.db.insert("friends", {
      ownerId: user._id,
      linkedUserId,
      name: friendName,
      email: friendEmail,
      phone: args.phone,
      avatarUrl: friendAvatarUrl,
      avatarEmoji: args.avatarEmoji,
      avatarColor: args.avatarColor,
      isDummy: true,
      isSelf: false,
      inviteStatus: linkedUserId ? "invite_sent" : "none",
      createdAt: Date.now(),
    });

    return { friendId, userExistsOnApp, isExisting: false };
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
