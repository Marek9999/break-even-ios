import { v } from "convex/values";
import { internalMutation, internalQuery, mutation } from "./_generated/server";

/**
 * Generate a URL for uploading a receipt image
 */
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new Error("Not authenticated");
    }

    return await ctx.storage.generateUploadUrl();
  },
});

/**
 * Get the URL for a stored file. Receipt URLs used by the app are returned
 * through authenticated transaction-detail queries after access checks.
 */
export const getFileUrl = internalQuery({
  args: {
    storageId: v.id("_storage"),
  },
  handler: async (ctx, args) => {
    return await ctx.storage.getUrl(args.storageId);
  },
});

/**
 * Delete a stored file
 */
export const deleteFile = internalMutation({
  args: {
    storageId: v.id("_storage"),
  },
  handler: async (ctx, args) => {
    await ctx.storage.delete(args.storageId);
    return true;
  },
});

/**
 * Store a file reference and return its ID
 * This is called after uploading to the generated URL
 */
export const saveFileReference = internalMutation({
  args: {
    storageId: v.id("_storage"),
    transactionId: v.optional(v.id("transactions")),
  },
  handler: async (ctx, args) => {
    // If transaction ID provided, update the transaction
    if (args.transactionId) {
      await ctx.db.patch(args.transactionId, {
        receiptFileId: args.storageId,
      });
    }

    return args.storageId;
  },
});
