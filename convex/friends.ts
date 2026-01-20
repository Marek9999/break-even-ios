import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

/**
 * List all friends for the current user
 */
export const listFriends = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      return [];
    }

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
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.friendId);
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
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      return null;
    }

    return await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();
  },
});

/**
 * Create a dummy friend (not linked to a real user yet)
 */
export const createDummyFriend = mutation({
  args: {
    clerkId: v.string(),
    name: v.string(),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    // Check if a friend with this email already exists
    if (args.email) {
      const existingByEmail = await ctx.db
        .query("friends")
        .withIndex("by_owner_email", (q) =>
          q.eq("ownerId", user._id).eq("email", args.email)
        )
        .unique();

      if (existingByEmail) {
        return existingByEmail._id;
      }

      // Check if there's an existing user with this email
      const existingUser = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", args.email))
        .unique();

      if (existingUser) {
        // Create a linked friend instead of dummy
        const friendId = await ctx.db.insert("friends", {
          ownerId: user._id,
          linkedUserId: existingUser._id,
          name: existingUser.name,
          email: existingUser.email,
          phone: existingUser.phone,
          avatarUrl: existingUser.avatarUrl,
          isDummy: false,
          isSelf: false,
          createdAt: Date.now(),
        });

        // Create reciprocal friend entry for the other user
        const reciprocalExists = await ctx.db
          .query("friends")
          .withIndex("by_owner", (q) => q.eq("ownerId", existingUser._id))
          .filter((q) => q.eq(q.field("linkedUserId"), user._id))
          .unique();

        if (!reciprocalExists) {
          await ctx.db.insert("friends", {
            ownerId: existingUser._id,
            linkedUserId: user._id,
            name: user.name,
            email: user.email,
            phone: user.phone,
            avatarUrl: user.avatarUrl,
            isDummy: false,
            isSelf: false,
            createdAt: Date.now(),
          });
        }

        return friendId;
      }
    }

    // Create dummy friend
    const friendId = await ctx.db.insert("friends", {
      ownerId: user._id,
      linkedUserId: undefined,
      name: args.name,
      email: args.email,
      phone: args.phone,
      avatarUrl: undefined,
      isDummy: true,
      isSelf: false,
      createdAt: Date.now(),
    });

    return friendId;
  },
});

/**
 * Update a friend's info
 */
export const updateFriend = mutation({
  args: {
    friendId: v.id("friends"),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }

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
    if (args.email !== undefined) updates.email = args.email;
    if (args.phone !== undefined) updates.phone = args.phone;

    await ctx.db.patch(args.friendId, updates);

    return args.friendId;
  },
});

/**
 * Delete a friend
 */
export const deleteFriend = mutation({
  args: {
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }

    // Don't allow deleting self
    if (friend.isSelf) {
      throw new Error("Cannot delete self");
    }

    // Check if there are any unsettled splits with this friend
    const unsettledSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend_settled", (q) =>
        q.eq("friendId", args.friendId).eq("isSettled", false)
      )
      .collect();

    if (unsettledSplits.length > 0) {
      throw new Error("Cannot delete friend with unsettled splits");
    }

    // Delete all pending invitations for this friend
    const invitations = await ctx.db
      .query("invitations")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    for (const invitation of invitations) {
      await ctx.db.delete(invitation._id);
    }

    // Delete all settled splits for this friend
    const settledSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    for (const split of settledSplits) {
      await ctx.db.delete(split._id);
    }

    // Delete the friend
    await ctx.db.delete(args.friendId);

    return true;
  },
});

/**
 * Merge a dummy friend with a real user
 * Called when a user accepts an invitation
 */
export const mergeFriendWithUser = mutation({
  args: {
    friendId: v.id("friends"),
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }

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
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
    });

    // Create a reciprocal friend entry for the new user
    const owner = await ctx.db.get(friend.ownerId);
    if (owner) {
      const existingReciprocal = await ctx.db
        .query("friends")
        .withIndex("by_owner", (q) => q.eq("ownerId", args.userId))
        .filter((q) => q.eq(q.field("linkedUserId"), owner._id))
        .unique();

      if (!existingReciprocal) {
        await ctx.db.insert("friends", {
          ownerId: args.userId,
          linkedUserId: owner._id,
          name: owner.name,
          email: owner.email,
          phone: owner.phone,
          avatarUrl: owner.avatarUrl,
          isDummy: false,
          isSelf: false,
          createdAt: Date.now(),
        });
      }
    }

    return args.friendId;
  },
});

/**
 * Get friends who have pending balances with the user
 */
export const getFriendsWithBalances = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      return [];
    }

    // Get all friends
    const friends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .collect();

    // Get self friend ID
    const selfFriend = friends.find((f) => f.isSelf);

    const friendsWithBalances = [];

    for (const friend of friends) {
      if (friend.isSelf) continue;

      // Get all unsettled splits for this friend
      const friendSplits = await ctx.db
        .query("splits")
        .withIndex("by_friend_settled", (q) =>
          q.eq("friendId", friend._id).eq("isSettled", false)
        )
        .collect();

      // Calculate what friend owes user (friend has unsettled split, user paid)
      let friendOwesUser = 0;
      // Calculate what user owes friend (user has unsettled split, friend paid)
      let userOwesFriend = 0;

      for (const split of friendSplits) {
        const transaction = await ctx.db.get(split.transactionId);
        if (!transaction) continue;

        // Check who paid
        const payer = await ctx.db.get(transaction.paidById);
        if (!payer) continue;

        if (payer.isSelf) {
          // User paid, friend owes user
          friendOwesUser += split.amount;
        }
      }

      // Get splits where the friend paid but user owes
      if (selfFriend) {
        const userSplits = await ctx.db
          .query("splits")
          .withIndex("by_friend_settled", (q) =>
            q.eq("friendId", selfFriend._id).eq("isSettled", false)
          )
          .collect();

        for (const split of userSplits) {
          const transaction = await ctx.db.get(split.transactionId);
          if (!transaction) continue;

          // Check if this friend paid
          if (transaction.paidById === friend._id) {
            userOwesFriend += split.amount;
          }
        }
      }

      const netBalance = friendOwesUser - userOwesFriend;

      if (netBalance !== 0) {
        friendsWithBalances.push({
          friend,
          friendOwesUser,
          userOwesFriend,
          netBalance,
          isOwedToUser: netBalance > 0,
        });
      }
    }

    return friendsWithBalances;
  },
});
