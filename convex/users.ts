import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

/**
 * Get or create a user based on Clerk authentication
 * Called when a user signs in to sync their Clerk profile with Convex
 */
export const getOrCreateUser = mutation({
  args: {
    clerkId: v.string(),
    email: v.string(),
    name: v.string(),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    defaultCurrency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check if user already exists
    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (existingUser) {
      // Update user info if changed
      await ctx.db.patch(existingUser._id, {
        email: args.email,
        name: args.name,
        phone: args.phone,
        avatarUrl: args.avatarUrl,
      });

      return existingUser._id;
    }

    // Create new user
    const userId = await ctx.db.insert("users", {
      clerkId: args.clerkId,
      email: args.email,
      name: args.name,
      phone: args.phone,
      avatarUrl: args.avatarUrl,
      defaultCurrency: args.defaultCurrency || "USD",
      createdAt: Date.now(),
    });

    // Create a "self" friend entry for this user (represents "Me" in splits)
    await ctx.db.insert("friends", {
      ownerId: userId,
      linkedUserId: userId,
      name: args.name,
      email: args.email,
      phone: args.phone,
      avatarUrl: args.avatarUrl,
      isDummy: false,
      isSelf: true,
      createdAt: Date.now(),
    });

    // Check for pending invitations for this email
    const pendingInvitations = await ctx.db
      .query("invitations")
      .withIndex("by_recipient_email", (q) => q.eq("recipientEmail", args.email))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .collect();

    // Process each pending invitation
    for (const invitation of pendingInvitations) {
      // Get the sender's friend entry for this invitation
      const dummyFriend = await ctx.db.get(invitation.friendId);
      if (dummyFriend) {
        // Link the dummy friend to the real user
        await ctx.db.patch(dummyFriend._id, {
          linkedUserId: userId,
          isDummy: false,
          avatarUrl: args.avatarUrl,
        });

        // Mark invitation as accepted
        await ctx.db.patch(invitation._id, {
          status: "accepted",
        });

        // Create a reciprocal friend entry for the new user
        const sender = await ctx.db.get(invitation.senderId);
        if (sender) {
          // Check if friend entry already exists
          const existingFriend = await ctx.db
            .query("friends")
            .withIndex("by_owner", (q) => q.eq("ownerId", userId))
            .filter((q) => q.eq(q.field("linkedUserId"), sender._id))
            .unique();

          if (!existingFriend) {
            await ctx.db.insert("friends", {
              ownerId: userId,
              linkedUserId: sender._id,
              name: sender.name,
              email: sender.email,
              phone: sender.phone,
              avatarUrl: sender.avatarUrl,
              isDummy: false,
              isSelf: false,
              createdAt: Date.now(),
            });
          }
        }
      }
    }

    return userId;
  },
});

/**
 * Get current user by Clerk ID
 */
export const getCurrentUser = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    return user;
  },
});

/**
 * Get user by ID
 */
export const getUserById = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.userId);
  },
});

/**
 * Update user profile
 */
export const updateProfile = mutation({
  args: {
    clerkId: v.string(),
    name: v.optional(v.string()),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    defaultCurrency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    const updates: Partial<{
      name: string;
      phone: string;
      avatarUrl: string;
      defaultCurrency: string;
    }> = {};

    if (args.name !== undefined) updates.name = args.name;
    if (args.phone !== undefined) updates.phone = args.phone;
    if (args.avatarUrl !== undefined) updates.avatarUrl = args.avatarUrl;
    if (args.defaultCurrency !== undefined)
      updates.defaultCurrency = args.defaultCurrency;

    await ctx.db.patch(user._id, updates);

    // Also update the "self" friend entry
    const selfFriend = await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();

    if (selfFriend) {
      const friendUpdates: Partial<{
        name: string;
        phone: string;
        avatarUrl: string;
      }> = {};
      if (args.name !== undefined) friendUpdates.name = args.name;
      if (args.phone !== undefined) friendUpdates.phone = args.phone;
      if (args.avatarUrl !== undefined) friendUpdates.avatarUrl = args.avatarUrl;
      await ctx.db.patch(selfFriend._id, friendUpdates);
    }

    return user._id;
  },
});

/**
 * Get user by email (for finding existing users when inviting)
 */
export const getUserByEmail = query({
  args: {
    email: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .unique();
  },
});

/**
 * List all users (for development/debugging only)
 */
export const listAllUsers = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("users").collect();
  },
});
