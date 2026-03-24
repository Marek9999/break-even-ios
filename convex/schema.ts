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
    username: v.optional(v.string()),
    usernameChangedAt: v.optional(v.number()),
    createdAt: v.number(),
  })
    .index("by_clerkId", ["clerkId"])
    .index("by_email", ["email"])
    .index("by_username", ["username"]),

  // Friends - can be dummy or linked to real users
  friends: defineTable({
    ownerId: v.id("users"), // Who owns this friend entry
    linkedUserId: v.optional(v.id("users")), // If friend is a real user
    name: v.string(),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    avatarEmoji: v.optional(v.string()),
    avatarColor: v.optional(v.string()),
    isDummy: v.boolean(), // True if not linked to real user
    isSelf: v.boolean(), // True if this represents the owner themselves
    inviteStatus: v.string(), // "none" | "invite_sent" | "invite_received" | "accepted" | "rejected" | "removed_by_me" | "removed_by_them"
    createdAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_linkedUser", ["linkedUserId"])
    .index("by_owner_linkedUser", ["ownerId", "linkedUserId"])
    .index("by_owner_email", ["ownerId", "email"])
    .index("by_owner_isSelf", ["ownerId", "isSelf"])
    .index("by_owner_inviteStatus", ["ownerId", "inviteStatus"]),

  // Cached exchange rates (refreshed only when creating splits if stale)
  exchangeRates: defineTable({
    baseCurrency: v.string(), // "USD" - all rates relative to USD
    rates: v.object({
      USD: v.float64(),
      EUR: v.float64(),
      GBP: v.float64(),
      CAD: v.float64(),
      AUD: v.float64(),
      INR: v.float64(),
      JPY: v.float64(),
    }),
    fetchedAt: v.number(), // Timestamp when rates were fetched
  }).index("by_base_fetchedAt", ["baseCurrency", "fetchedAt"]),

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
    // Exchange rates snapshot at time of transaction creation (for currency conversion)
    exchangeRates: v.optional(
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
    ),
    date: v.number(),
    createdAt: v.number(),
    lastEditedBy: v.optional(v.id("users")),
    lastEditedAt: v.optional(v.number()),
    editHistory: v.optional(
      v.array(
        v.object({
          editedBy: v.id("users"),
          editedAt: v.number(),
        })
      )
    ),
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
    createdAt: v.number(),
  })
    .index("by_transaction", ["transactionId"])
    .index("by_friend", ["friendId"]),

  // Settlement records - tracks payment history between users
  settlements: defineTable({
    createdById: v.id("users"), // Who recorded this settlement
    friendId: v.id("friends"), // The friend involved in settlement
    amount: v.float64(), // Amount settled (always positive)
    currency: v.string(), // Currency of settlement
    direction: v.string(), // "to_friend" (user pays) or "from_friend" (friend pays user)
    note: v.optional(v.string()), // Optional note/memo
    balanceBeforeSettlement: v.optional(v.float64()), // Total owed before this settlement (for display "X out of Y")
    // Exchange rates snapshot for currency conversion display
    exchangeRates: v.optional(
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
    ),
    settledAt: v.number(), // When settlement happened
    createdAt: v.number(), // When record was created
  })
    .index("by_creator", ["createdById"])
    .index("by_friend", ["friendId"])
    .index("by_settledAt", ["settledAt"]),

  // Friend invitations
  invitations: defineTable({
    senderId: v.id("users"),
    friendId: v.id("friends"), // The dummy friend this invitation is for
    recipientEmail: v.optional(v.string()),
    recipientPhone: v.optional(v.string()),
    status: v.string(), // "pending", "accepted", "rejected", "expired", "cancelled"
    token: v.string(), // Unique invite token for deep link
    expiresAt: v.number(),
    createdAt: v.number(),
  })
    .index("by_sender", ["senderId"])
    .index("by_sender_status", ["senderId", "status"])
    .index("by_token", ["token"])
    .index("by_recipient_email", ["recipientEmail"])
    .index("by_recipient_email_status", ["recipientEmail", "status"])
    .index("by_recipient_phone", ["recipientPhone"])
    .index("by_friend", ["friendId"])
    .index("by_friend_status", ["friendId", "status"]),

  // Junction table: which users can see/edit which transactions
  transactionParticipants: defineTable({
    transactionId: v.id("transactions"),
    userId: v.id("users"),
    role: v.string(), // "creator" | "participant"
    addedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_transaction", ["transactionId"])
    .index("by_user_transaction", ["userId", "transactionId"]),
});
