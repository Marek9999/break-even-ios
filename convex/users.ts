import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import {
  normalizeEmail,
  requireAuthenticatedUser,
  requireIdentity,
} from "./lib/auth";

/**
 * Propagate profile changes to all friend records that reference this user.
 * Uses the by_linkedUser index for efficient lookup. Only patches records
 * where values actually changed to avoid unnecessary writes.
 */
async function propagateProfileToLinkedFriends(
  ctx: any,
  userId: Id<"users">,
  updates: { name?: string; avatarUrl?: string | undefined; email?: string; phone?: string | undefined }
) {
  const linkedFriends = await ctx.db
    .query("friends")
    .withIndex("by_linkedUser", (q: any) => q.eq("linkedUserId", userId))
    .collect();

  for (const friend of linkedFriends) {
    const patch: Record<string, any> = {};
    if (updates.name !== undefined && friend.name !== updates.name) patch.name = updates.name;
    if ("avatarUrl" in updates && friend.avatarUrl !== updates.avatarUrl) patch.avatarUrl = updates.avatarUrl;
    if (updates.email !== undefined && friend.email !== updates.email) patch.email = updates.email;
    if ("phone" in updates && friend.phone !== updates.phone) patch.phone = updates.phone;
    if (Object.keys(patch).length > 0) {
      await ctx.db.patch(friend._id, patch);
    }
  }
}

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
    await requireIdentity(ctx, args.clerkId);
    const normalizedEmail = normalizeEmail(args.email);
    if (!normalizedEmail) {
      throw new Error("A valid email address is required");
    }

    // Check if user already exists
    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (existingUser) {
      // Treat empty string avatarUrl as removal
      const resolvedAvatarUrl = args.avatarUrl === "" ? undefined : args.avatarUrl;

      // Update user info if changed
      await ctx.db.patch(existingUser._id, {
        email: normalizedEmail,
        name: args.name,
        phone: args.phone,
        avatarUrl: resolvedAvatarUrl,
      });

      // Propagate profile changes to self-friend and all linked friend records
      await propagateProfileToLinkedFriends(ctx, existingUser._id, {
        name: args.name,
        email: normalizedEmail,
        phone: args.phone,
        avatarUrl: resolvedAvatarUrl,
      });

      return existingUser._id;
    }

    // Create new user
    const userId = await ctx.db.insert("users", {
      clerkId: args.clerkId,
      email: normalizedEmail,
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
      email: normalizedEmail,
      phone: args.phone,
      avatarUrl: args.avatarUrl,
      isDummy: false,
      isSelf: true,
      inviteStatus: "none",
      createdAt: Date.now(),
    });

    // Check for pending invitations for this email.
    // Instead of auto-accepting, create friend rows with "invite_received"
    // so the new user sees them in their invitations list.
    const pendingInvitations = await ctx.db
      .query("invitations")
      .withIndex("by_recipient_email_status", (q) =>
        q.eq("recipientEmail", normalizedEmail).eq("status", "pending")
      )
      .collect();

    for (const invitation of pendingInvitations) {
      const dummyFriend = await ctx.db.get(invitation.friendId);
      if (dummyFriend) {
        // Update the sender's friend row to point to the new user
        await ctx.db.patch(dummyFriend._id, {
          linkedUserId: userId,
        });

        // Create a reciprocal friend entry with invite_received status
        const sender = await ctx.db.get(invitation.senderId);
        if (sender) {
          const existingFriend = await ctx.db
            .query("friends")
            .withIndex("by_owner_linkedUser", (q) =>
              q.eq("ownerId", userId).eq("linkedUserId", sender._id)
            )
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
              inviteStatus: "invite_received",
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
    return await requireAuthenticatedUser(ctx, args.clerkId);
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
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

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

    // Propagate profile changes to all friend records that reference this user
    const propagateUpdates: { name?: string; avatarUrl?: string; phone?: string } = {};
    if (args.name !== undefined) propagateUpdates.name = args.name;
    if (args.phone !== undefined) propagateUpdates.phone = args.phone;
    if (args.avatarUrl !== undefined) propagateUpdates.avatarUrl = args.avatarUrl;
    if (Object.keys(propagateUpdates).length > 0) {
      await propagateProfileToLinkedFriends(ctx, user._id, propagateUpdates);
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
 * Set or update a user's username.
 * Validates format (alphanumeric + underscores, 3-20 chars), checks uniqueness,
 * and enforces a 48-hour cooldown between changes.
 */
export const setUsername = mutation({
  args: {
    clerkId: v.string(),
    username: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    const username = args.username.toLowerCase().trim();

    if (username.length < 3 || username.length > 20) {
      throw new Error("Username must be between 3 and 20 characters");
    }

    if (!/^[a-z0-9_]+$/.test(username)) {
      throw new Error(
        "Username can only contain lowercase letters, numbers, and underscores"
      );
    }

    // Enforce 48-hour cooldown (skip if user has never set a username)
    if (user.username && user.usernameChangedAt) {
      const hoursSinceLastChange =
        (Date.now() - user.usernameChangedAt) / (1000 * 60 * 60);
      if (hoursSinceLastChange < 48) {
        const hoursRemaining = Math.ceil(48 - hoursSinceLastChange);
        throw new Error(
          `You can change your username again in ${hoursRemaining} hour${hoursRemaining === 1 ? "" : "s"}`
        );
      }
    }

    // Skip if unchanged
    if (user.username === username) {
      return { success: true, username };
    }

    // Check uniqueness
    const existing = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();

    if (existing && existing._id !== user._id) {
      throw new Error("This username is already taken");
    }

    await ctx.db.patch(user._id, {
      username,
      usernameChangedAt: Date.now(),
    });

    return { success: true, username };
  },
});

/**
 * Check if a username is available (real-time availability for the UI).
 */
export const checkUsernameAvailable = query({
  args: {
    username: v.string(),
  },
  handler: async (ctx, args) => {
    const username = args.username.toLowerCase().trim();

    if (username.length < 3 || username.length > 20) {
      return { available: false, reason: "Must be 3-20 characters" };
    }

    if (!/^[a-z0-9_]+$/.test(username)) {
      return {
        available: false,
        reason: "Only lowercase letters, numbers, and underscores",
      };
    }

    const existing = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();

    if (existing) {
      return { available: false, reason: "Already taken" };
    }

    return { available: true, reason: null };
  },
});

/**
 * Look up a user by username. Returns public profile info only (no email).
 */
export const getUserByUsername = query({
  args: {
    username: v.string(),
  },
  handler: async (ctx, args) => {
    const username = args.username.toLowerCase().trim();

    const user = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();

    if (!user) {
      return null;
    }

    return {
      _id: user._id,
      name: user.name,
      username: user.username,
      avatarUrl: user.avatarUrl,
    };
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
