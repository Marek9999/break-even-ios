import { v } from "convex/values";
import { mutation, query, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { getAuthenticatedUser } from "./lib/auth";

type ActivityInsertArgs = {
  userId: Id<"users">;
  actorId: Id<"users">;
  actorName: string;
  type: string;
  message: string;
  transactionId?: Id<"transactions">;
  friendId?: Id<"friends">;
  settlementId?: Id<"settlements">;
  invitationId?: Id<"invitations">;
  metadata?: string;
};

async function scheduleActivityPush(
  ctx: any,
  activityId: Id<"activities">,
  args: ActivityInsertArgs
) {
  await ctx.scheduler.runAfter(
    0,
    (internal as any).pushNotifications.sendActivityPush,
    {
      userId: args.userId,
      activityId,
      activityType: args.type,
      message: args.message,
      transactionId: args.transactionId,
      friendId: args.friendId,
      settlementId: args.settlementId,
      invitationId: args.invitationId,
    }
  );
}

/**
 * Internal helper to create an activity for a user.
 * Called from other mutations (invitations, friends, transactions).
 */
export const createActivity = internalMutation({
  args: {
    userId: v.id("users"),
    actorId: v.id("users"),
    actorName: v.string(),
    type: v.string(),
    message: v.string(),
    transactionId: v.optional(v.id("transactions")),
    friendId: v.optional(v.id("friends")),
    settlementId: v.optional(v.id("settlements")),
    invitationId: v.optional(v.id("invitations")),
    metadata: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Never create self-notifications
    if (args.userId === args.actorId) return;

    const activityId = await ctx.db.insert("activities", {
      userId: args.userId,
      actorId: args.actorId,
      actorName: args.actorName,
      type: args.type,
      message: args.message,
      transactionId: args.transactionId,
      friendId: args.friendId,
      settlementId: args.settlementId,
      invitationId: args.invitationId,
      metadata: args.metadata,
      isRead: false,
      createdAt: Date.now(),
    });

    await scheduleActivityPush(ctx, activityId, args);
  },
});

/**
 * Inline helper for creating activities within the same mutation context.
 * Avoids the overhead of scheduling an internal mutation.
 */
export async function insertActivity(
  ctx: any,
  args: ActivityInsertArgs
) {
  // Never create self-notifications
  if (args.userId === args.actorId) return;

  const activityId = await ctx.db.insert("activities", {
    userId: args.userId,
    actorId: args.actorId,
    actorName: args.actorName,
    type: args.type,
    message: args.message,
    transactionId: args.transactionId,
    friendId: args.friendId,
    settlementId: args.settlementId,
    invitationId: args.invitationId,
    metadata: args.metadata,
    isRead: false,
    createdAt: Date.now(),
  });

  await scheduleActivityPush(ctx, activityId, args);
}

/**
 * List activities for the current user.
 */
export const listActivities = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    const activities = await ctx.db
      .query("activities")
      .withIndex("by_user_createdAt", (q) => q.eq("userId", user._id))
      .order("desc")
      .collect();

    return activities;
  },
});

/**
 * Get the count of unread activities for the current user.
 */
export const getUnreadCount = query({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    const unread = await ctx.db
      .query("activities")
      .withIndex("by_user_isRead", (q) =>
        q.eq("userId", user._id).eq("isRead", false)
      )
      .collect();

    return unread.length;
  },
});

/**
 * Mark all unread activities as read for the current user.
 */
export const markAllAsRead = mutation({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getAuthenticatedUser(ctx, args.clerkId);

    const unread = await ctx.db
      .query("activities")
      .withIndex("by_user_isRead", (q) =>
        q.eq("userId", user._id).eq("isRead", false)
      )
      .collect();

    for (const activity of unread) {
      await ctx.db.patch(activity._id, { isRead: true });
    }

    return unread.length;
  },
});
