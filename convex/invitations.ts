import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

/**
 * Generate a unique invitation token
 */
function generateToken(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

/**
 * Create a friend invitation
 */
export const createInvitation = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    recipientEmail: v.optional(v.string()),
    recipientPhone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    const friend = await ctx.db.get(args.friendId);
    if (!friend) {
      throw new Error("Friend not found");
    }

    if (!friend.isDummy) {
      throw new Error("Cannot invite a user who is already linked");
    }

    // Check for existing pending invitation
    const existingInvitation = await ctx.db
      .query("invitations")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .unique();

    if (existingInvitation) {
      // Return existing invitation token
      return {
        invitationId: existingInvitation._id,
        token: existingInvitation.token,
        isExisting: true,
      };
    }

    // Generate unique token
    let token = generateToken();
    // Ensure token is unique
    let existingToken = await ctx.db
      .query("invitations")
      .withIndex("by_token", (q) => q.eq("token", token))
      .unique();
    while (existingToken) {
      token = generateToken();
      existingToken = await ctx.db
        .query("invitations")
        .withIndex("by_token", (q) => q.eq("token", token))
        .unique();
    }

    // Create invitation (expires in 7 days)
    const expiresAt = Date.now() + 7 * 24 * 60 * 60 * 1000;

    const invitationId = await ctx.db.insert("invitations", {
      senderId: user._id,
      friendId: args.friendId,
      recipientEmail: args.recipientEmail || friend.email,
      recipientPhone: args.recipientPhone || friend.phone,
      status: "pending",
      token,
      expiresAt,
      createdAt: Date.now(),
    });

    return {
      invitationId,
      token,
      isExisting: false,
    };
  },
});

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

    // Get sender info
    const sender = await ctx.db.get(invitation.senderId);
    const friend = await ctx.db.get(invitation.friendId);

    return {
      ...invitation,
      sender,
      friend,
      isExpired: invitation.expiresAt < Date.now(),
    };
  },
});

/**
 * Accept an invitation
 */
export const acceptInvitation = mutation({
  args: {
    token: v.string(),
    clerkId: v.string(),
  },
  handler: async (ctx, args) => {
    // Get the accepting user
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    // Get the invitation
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

    // Get the dummy friend
    const dummyFriend = await ctx.db.get(invitation.friendId);
    if (!dummyFriend) {
      throw new Error("Friend not found");
    }

    // Link the dummy friend to the real user
    await ctx.db.patch(invitation.friendId, {
      linkedUserId: user._id,
      isDummy: false,
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
    });

    // Mark invitation as accepted
    await ctx.db.patch(invitation._id, {
      status: "accepted",
    });

    // Create a reciprocal friend entry for the accepting user
    const sender = await ctx.db.get(invitation.senderId);
    if (sender) {
      // Check if friend entry already exists
      const existingFriend = await ctx.db
        .query("friends")
        .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
        .filter((q) => q.eq(q.field("linkedUserId"), sender._id))
        .unique();

      if (!existingFriend) {
        await ctx.db.insert("friends", {
          ownerId: user._id,
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

    return {
      success: true,
      friendId: invitation.friendId,
    };
  },
});

/**
 * Cancel an invitation
 */
export const cancelInvitation = mutation({
  args: {
    invitationId: v.id("invitations"),
  },
  handler: async (ctx, args) => {
    const invitation = await ctx.db.get(args.invitationId);
    if (!invitation) {
      throw new Error("Invitation not found");
    }

    if (invitation.status !== "pending") {
      throw new Error("Can only cancel pending invitations");
    }

    await ctx.db.patch(args.invitationId, {
      status: "cancelled",
    });

    return true;
  },
});

/**
 * List all pending invitations sent by a user
 */
export const listSentInvitations = query({
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

    const invitations = await ctx.db
      .query("invitations")
      .withIndex("by_sender", (q) => q.eq("senderId", user._id))
      .collect();

    // Enrich with friend info
    const enrichedInvitations = await Promise.all(
      invitations.map(async (invitation) => {
        const friend = await ctx.db.get(invitation.friendId);
        return {
          ...invitation,
          friend,
          isExpired: invitation.expiresAt < Date.now(),
        };
      })
    );

    return enrichedInvitations;
  },
});

/**
 * Resend an invitation (generates new token and extends expiry)
 */
export const resendInvitation = mutation({
  args: {
    invitationId: v.id("invitations"),
  },
  handler: async (ctx, args) => {
    const invitation = await ctx.db.get(args.invitationId);
    if (!invitation) {
      throw new Error("Invitation not found");
    }

    if (invitation.status === "accepted") {
      throw new Error("Invitation has already been accepted");
    }

    // Generate new token
    let token = generateToken();
    let existingToken = await ctx.db
      .query("invitations")
      .withIndex("by_token", (q) => q.eq("token", token))
      .unique();
    while (existingToken) {
      token = generateToken();
      existingToken = await ctx.db
        .query("invitations")
        .withIndex("by_token", (q) => q.eq("token", token))
        .unique();
    }

    // Extend expiry to 7 days from now
    const expiresAt = Date.now() + 7 * 24 * 60 * 60 * 1000;

    await ctx.db.patch(args.invitationId, {
      token,
      expiresAt,
      status: "pending",
    });

    return {
      invitationId: args.invitationId,
      token,
    };
  },
});
