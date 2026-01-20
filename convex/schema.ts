import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // Users - linked to Clerk authentication
  users: defineTable({
    clerkId: v.string(),
    email: v.string(),
    name: v.string(),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    defaultCurrency: v.string(), // "USD", "EUR", etc.
    createdAt: v.number(),
  })
    .index("by_clerkId", ["clerkId"])
    .index("by_email", ["email"]),

  // Friends - can be dummy or linked to real users
  friends: defineTable({
    ownerId: v.id("users"), // Who owns this friend entry
    linkedUserId: v.optional(v.id("users")), // If friend is a real user
    name: v.string(),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    isDummy: v.boolean(), // True if not linked to real user
    isSelf: v.boolean(), // True if this represents the owner themselves
    createdAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_linkedUser", ["linkedUserId"])
    .index("by_owner_email", ["ownerId", "email"])
    .index("by_owner_isSelf", ["ownerId", "isSelf"]),

  // Transactions (expense splits)
  transactions: defineTable({
    createdById: v.id("users"),
    paidById: v.id("friends"), // Friend ID of who paid
    title: v.string(),
    emoji: v.string(),
    description: v.optional(v.string()),
    totalAmount: v.float64(),
    currency: v.string(),
    splitMethod: v.string(), // "equal", "unequal", "byParts", "byItem"
    status: v.string(), // "pending", "partial", "settled"
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
    createdAt: v.number(),
  })
    .index("by_creator", ["createdById"])
    .index("by_createdAt", ["createdAt"])
    .index("by_paidBy", ["paidById"]),

  // Individual splits within a transaction
  splits: defineTable({
    transactionId: v.id("transactions"),
    friendId: v.id("friends"),
    amount: v.float64(),
    percentage: v.optional(v.float64()),
    isSettled: v.boolean(),
    settledAt: v.optional(v.number()),
    settledById: v.optional(v.id("users")), // Who marked it settled
    createdAt: v.number(),
  })
    .index("by_transaction", ["transactionId"])
    .index("by_friend", ["friendId"])
    .index("by_friend_settled", ["friendId", "isSettled"]),

  // Friend invitations
  invitations: defineTable({
    senderId: v.id("users"),
    friendId: v.id("friends"), // The dummy friend this invitation is for
    recipientEmail: v.optional(v.string()),
    recipientPhone: v.optional(v.string()),
    status: v.string(), // "pending", "accepted", "expired", "cancelled"
    token: v.string(), // Unique invite token for deep link
    expiresAt: v.number(),
    createdAt: v.number(),
  })
    .index("by_sender", ["senderId"])
    .index("by_token", ["token"])
    .index("by_recipient_email", ["recipientEmail"])
    .index("by_recipient_phone", ["recipientPhone"])
    .index("by_friend", ["friendId"]),
});
