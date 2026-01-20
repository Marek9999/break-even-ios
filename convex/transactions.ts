import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

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
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    // Get the payer to determine initial settlement status
    const payer = await ctx.db.get(args.paidById);
    if (!payer) {
      throw new Error("Payer not found");
    }

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
      status: "pending",
      receiptFileId: args.receiptFileId,
      items: args.items,
      exchangeRates: args.exchangeRates,
      date: args.date,
      createdAt: Date.now(),
    });

    // Create splits for each participant
    for (const split of args.splits) {
      // If the split is for the payer, mark it as settled
      const isSettled = split.friendId === args.paidById;

      await ctx.db.insert("splits", {
        transactionId,
        friendId: split.friendId,
        amount: split.amount,
        percentage: split.percentage,
        isSettled,
        settledAt: isSettled ? Date.now() : undefined,
        settledById: isSettled ? user._id : undefined,
        createdAt: Date.now(),
      });
    }

    // Update transaction status
    await updateTransactionStatus(ctx, transactionId);

    return transactionId;
  },
});

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
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    // Parse the paidById
    const paidById = args.paidById as Id<"friends">;

    // Get the payer to determine initial settlement status
    const payer = await ctx.db.get(paidById);
    if (!payer) {
      throw new Error("Payer not found");
    }

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

    // Create the transaction
    const transactionId = await ctx.db.insert("transactions", {
      createdById: user._id,
      paidById,
      title: args.title,
      emoji: args.emoji,
      totalAmount,
      currency: args.currency,
      splitMethod: args.splitMethod,
      status: "pending",
      receiptFileId: args.receiptFileId
        ? (args.receiptFileId as Id<"_storage">)
        : undefined,
      items: convertedItems,
      exchangeRates,
      date,
      createdAt: Date.now(),
    });

    // Create splits for each participant
    for (const split of splits) {
      const friendId = split.friendId as Id<"friends">;
      // If the split is for the payer, mark it as settled
      const isSettled = friendId === paidById;

      await ctx.db.insert("splits", {
        transactionId,
        friendId,
        amount: split.amount,
        percentage: split.percentage ?? undefined,
        isSettled,
        settledAt: isSettled ? Date.now() : undefined,
        settledById: isSettled ? user._id : undefined,
        createdAt: Date.now(),
      });
    }

    // Update transaction status
    await updateTransactionStatus(ctx, transactionId);

    return transactionId;
  },
});

/**
 * Helper to update transaction status based on splits
 */
async function updateTransactionStatus(
  ctx: any,
  transactionId: Id<"transactions">
) {
  const splits = await ctx.db
    .query("splits")
    .withIndex("by_transaction", (q: any) => q.eq("transactionId", transactionId))
    .collect();

  const allSettled = splits.every((s: any) => s.isSettled);
  const anySettled = splits.some((s: any) => s.isSettled);

  let status = "pending";
  if (allSettled) {
    status = "settled";
  } else if (anySettled) {
    status = "partial";
  }

  await ctx.db.patch(transactionId, { status });
}

/**
 * List all transactions for a user
 */
export const listTransactions = query({
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

    const transactions = await ctx.db
      .query("transactions")
      .withIndex("by_creator", (q) => q.eq("createdById", user._id))
      .order("desc")
      .collect();

    // Enrich transactions with splits and payer info
    const enrichedTransactions = await Promise.all(
      transactions.map(async (transaction) => {
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

        return {
          ...transaction,
          payer,
          splits: enrichedSplits,
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
    const transaction = await ctx.db.get(args.transactionId);
    if (!transaction) {
      return null;
    }

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

    return {
      ...transaction,
      payer,
      splits: enrichedSplits,
      receiptUrl,
    };
  },
});

/**
 * Get transactions involving a specific friend
 */
export const getTransactionsWithFriend = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      return [];
    }

    // Get self friend
    const selfFriend = await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();

    if (!selfFriend) {
      return [];
    }

    // Get all splits for this friend
    const friendSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    // Get unique transaction IDs
    const transactionIds = [...new Set(friendSplits.map((s) => s.transactionId))];

    // Fetch transactions and filter to only include those created by this user
    const transactions = [];
    for (const txId of transactionIds) {
      const tx = await ctx.db.get(txId);
      if (tx && tx.createdById === user._id) {
        const payer = await ctx.db.get(tx.paidById);
        const splits = await ctx.db
          .query("splits")
          .withIndex("by_transaction", (q) => q.eq("transactionId", txId))
          .collect();

        const enrichedSplits = await Promise.all(
          splits.map(async (split) => {
            const friend = await ctx.db.get(split.friendId);
            return { ...split, friend };
          })
        );

        // Calculate if this transaction involves both user and friend
        const involvesUser = splits.some((s) => s.friendId === selfFriend._id);
        const involvesFriend = splits.some((s) => s.friendId === args.friendId);

        if (involvesUser && involvesFriend) {
          transactions.push({
            ...tx,
            payer,
            splits: enrichedSplits,
          });
        }
      }
    }

    // Sort by date descending
    transactions.sort((a, b) => b.date - a.date);

    return transactions;
  },
});

/**
 * Settle a single split
 */
export const settleSplit = mutation({
  args: {
    clerkId: v.string(),
    splitId: v.id("splits"),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    const split = await ctx.db.get(args.splitId);
    if (!split) {
      throw new Error("Split not found");
    }

    if (split.isSettled) {
      return split.transactionId;
    }

    await ctx.db.patch(args.splitId, {
      isSettled: true,
      settledAt: Date.now(),
      settledById: user._id,
    });

    // Update transaction status
    await updateTransactionStatus(ctx, split.transactionId);

    return split.transactionId;
  },
});

/**
 * Settle all splits with a specific friend
 */
export const settleAllWithFriend = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    // Get all unsettled splits for this friend
    const unsettledSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend_settled", (q) =>
        q.eq("friendId", args.friendId).eq("isSettled", false)
      )
      .collect();

    const transactionIds = new Set<Id<"transactions">>();

    for (const split of unsettledSplits) {
      await ctx.db.patch(split._id, {
        isSettled: true,
        settledAt: Date.now(),
        settledById: user._id,
      });
      transactionIds.add(split.transactionId);
    }

    // Also settle user's splits in transactions where this friend paid
    const selfFriend = await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();

    if (selfFriend) {
      const userSplits = await ctx.db
        .query("splits")
        .withIndex("by_friend_settled", (q) =>
          q.eq("friendId", selfFriend._id).eq("isSettled", false)
        )
        .collect();

      for (const split of userSplits) {
        const transaction = await ctx.db.get(split.transactionId);
        if (transaction && transaction.paidById === args.friendId) {
          await ctx.db.patch(split._id, {
            isSettled: true,
            settledAt: Date.now(),
            settledById: user._id,
          });
          transactionIds.add(split.transactionId);
        }
      }
    }

    // Update status for all affected transactions
    for (const txId of transactionIds) {
      await updateTransactionStatus(ctx, txId);
    }

    return unsettledSplits.length;
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
 * Get balance summary with a specific friend
 * Balances are converted to user's default currency using stored exchange rates
 */
export const getBalanceWithFriend = query({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      return { friendOwesUser: 0, userOwesFriend: 0, netBalance: 0, userCurrency: "USD", balancesByCurrency: {} };
    }

    const userCurrency = user.defaultCurrency;

    // Get self friend
    const selfFriend = await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();

    if (!selfFriend) {
      return { friendOwesUser: 0, userOwesFriend: 0, netBalance: 0, userCurrency, balancesByCurrency: {} };
    }

    // Track balances by original currency
    const balancesByCurrency: Record<string, { friendOwes: number; userOwes: number }> = {};

    // Get all unsettled splits for this friend (what friend owes)
    const friendSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend_settled", (q) =>
        q.eq("friendId", args.friendId).eq("isSettled", false)
      )
      .collect();

    let friendOwesUserConverted = 0;
    for (const split of friendSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;

      // Only count if user paid
      const payer = await ctx.db.get(transaction.paidById);
      if (payer && payer.isSelf) {
        const txCurrency = transaction.currency;
        
        // Track by original currency
        if (!balancesByCurrency[txCurrency]) {
          balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
        }
        balancesByCurrency[txCurrency].friendOwes += split.amount;
        
        // Convert to user's currency
        if (transaction.exchangeRates) {
          friendOwesUserConverted += convertAmountHelper(
            split.amount,
            txCurrency,
            userCurrency,
            transaction.exchangeRates.rates
          );
        } else {
          friendOwesUserConverted += split.amount;
        }
      }
    }

    // Get user's unsettled splits where friend paid (what user owes)
    const userSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend_settled", (q) =>
        q.eq("friendId", selfFriend._id).eq("isSettled", false)
      )
      .collect();

    let userOwesFriendConverted = 0;
    for (const split of userSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;

      // Only count if friend paid
      if (transaction.paidById === args.friendId) {
        const txCurrency = transaction.currency;
        
        // Track by original currency
        if (!balancesByCurrency[txCurrency]) {
          balancesByCurrency[txCurrency] = { friendOwes: 0, userOwes: 0 };
        }
        balancesByCurrency[txCurrency].userOwes += split.amount;
        
        // Convert to user's currency
        if (transaction.exchangeRates) {
          userOwesFriendConverted += convertAmountHelper(
            split.amount,
            txCurrency,
            userCurrency,
            transaction.exchangeRates.rates
          );
        } else {
          userOwesFriendConverted += split.amount;
        }
      }
    }

    return {
      friendOwesUser: friendOwesUserConverted,
      userOwesFriend: userOwesFriendConverted,
      netBalance: friendOwesUserConverted - userOwesFriendConverted,
      userCurrency,
      balancesByCurrency,
    };
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
    // Delete all splits
    const splits = await ctx.db
      .query("splits")
      .withIndex("by_transaction", (q) => q.eq("transactionId", args.transactionId))
      .collect();

    for (const split of splits) {
      await ctx.db.delete(split._id);
    }

    // Delete transaction
    await ctx.db.delete(args.transactionId);

    return true;
  },
});
