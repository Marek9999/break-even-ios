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
      receiptFileId: args.receiptFileId,
      items: args.items,
      exchangeRates: args.exchangeRates,
      date: args.date,
      createdAt: Date.now(),
    });

    // Create splits for each participant
    for (const split of args.splits) {
      await ctx.db.insert("splits", {
        transactionId,
        friendId: split.friendId,
        amount: split.amount,
        percentage: split.percentage,
        createdAt: Date.now(),
      });
    }

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

      await ctx.db.insert("splits", {
        transactionId,
        friendId,
        amount: split.amount,
        percentage: split.percentage ?? undefined,
        createdAt: Date.now(),
      });
    }

    return transactionId;
  },
});


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
 * Settle a specific amount with a friend
 * Creates a settlement record without modifying splits
 */
export const settleAmount = mutation({
  args: {
    clerkId: v.string(),
    friendId: v.id("friends"),
    amount: v.string(), // Amount as string for iOS compatibility
    currency: v.string(),
    direction: v.string(), // "to_friend" (user pays) or "from_friend" (friend pays user)
    note: v.optional(v.string()),
    exchangeRatesJson: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!user) {
      throw new Error("User not found");
    }

    const amount = parseFloat(args.amount);
    if (isNaN(amount) || amount <= 0) {
      throw new Error("Invalid amount");
    }

    // Get self friend
    const selfFriend = await ctx.db
      .query("friends")
      .withIndex("by_owner_isSelf", (q) =>
        q.eq("ownerId", user._id).eq("isSelf", true)
      )
      .unique();

    if (!selfFriend) {
      throw new Error("Self friend not found");
    }

    // Parse exchange rates if provided by client
    let exchangeRates = undefined;
    if (args.exchangeRatesJson) {
      exchangeRates = JSON.parse(args.exchangeRatesJson);
    }

    // Calculate net balance before settlement for "X out of Y" display
    // Get all splits for this friend (what friend owes from transactions where user paid)
    const friendSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    let friendOwesUser = 0;
    let firstTxWithRates: any = null;

    for (const split of friendSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;

      const payer = await ctx.db.get(transaction.paidById);
      if (!payer || !payer.isSelf) continue;

      // Save first transaction with exchange rates for later use
      if (!firstTxWithRates && transaction.exchangeRates) {
        firstTxWithRates = transaction;
      }

      // Convert to user's currency
      const rates = transaction.exchangeRates?.rates || exchangeRates?.rates;
      if (transaction.currency !== args.currency && rates) {
        friendOwesUser += convertAmountHelper(split.amount, transaction.currency, args.currency, rates);
      } else {
        friendOwesUser += split.amount;
      }
    }

    // Get splits where user owes (user's splits where friend paid)
    const userSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", selfFriend._id))
      .collect();

    let userOwesFriend = 0;

    for (const split of userSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;
      if (transaction.paidById !== args.friendId) continue;

      // Save first transaction with exchange rates for later use
      if (!firstTxWithRates && transaction.exchangeRates) {
        firstTxWithRates = transaction;
      }

      // Convert to user's currency
      const rates = transaction.exchangeRates?.rates || exchangeRates?.rates;
      if (transaction.currency !== args.currency && rates) {
        userOwesFriend += convertAmountHelper(split.amount, transaction.currency, args.currency, rates);
      } else {
        userOwesFriend += split.amount;
      }
    }

    // Get existing settlements to calculate net balance
    const existingSettlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    let settlementsFromFriend = 0;
    let settlementsToFriend = 0;

    for (const s of existingSettlements) {
      if (s.createdById !== user._id) continue;

      let convertedAmount = s.amount;
      if (s.currency !== args.currency && s.exchangeRates?.rates) {
        convertedAmount = convertAmountHelper(s.amount, s.currency, args.currency, s.exchangeRates.rates);
      }

      if (s.direction === "from_friend") {
        settlementsFromFriend += convertedAmount;
      } else if (s.direction === "to_friend") {
        settlementsToFriend += convertedAmount;
      }
    }

    // Net balance before this settlement
    const netBalance = friendOwesUser - settlementsFromFriend - userOwesFriend + settlementsToFriend;
    const balanceBeforeSettlement = Math.abs(netBalance);

    // Use transaction's exchange rates if client didn't provide them
    const settlementExchangeRates = exchangeRates || firstTxWithRates?.exchangeRates;

    // Create settlement record
    const settlementId = await ctx.db.insert("settlements", {
      createdById: user._id,
      friendId: args.friendId,
      amount,
      currency: args.currency,
      direction: args.direction,
      note: args.note,
      balanceBeforeSettlement,
      exchangeRates: settlementExchangeRates,
      settledAt: Date.now(),
      createdAt: Date.now(),
    });

    return {
      settlementId,
      settledAmount: amount,
    };
  },
});


/**
 * Get settlement history with a specific friend
 */
export const getSettlementHistory = query({
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

    const settlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .order("desc")
      .collect();

    // Filter to only settlements created by this user
    return settlements.filter((s) => s.createdById === user._id);
  },
});

/**
 * Get activity (transactions + settlements) with a specific friend
 * Used for the PersonDetailSheet to show a combined chronological feed
 */
export const getActivityWithFriend = query({
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
      return { transactions: [], settlements: [], userCurrency: "USD" };
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
      return { transactions: [], settlements: [], userCurrency };
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

    // Get settlements with this friend (created by this user)
    const settlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    // Filter to only settlements created by this user and convert amounts to user currency
    const filteredSettlements = settlements
      .filter((s) => s.createdById === user._id)
      .map((s) => {
        // Convert settlement amount to user's currency if needed
        let convertedAmount = s.amount;
        let convertedBalanceBefore = s.balanceBeforeSettlement ?? null;
        
        if (s.currency !== userCurrency && s.exchangeRates) {
          convertedAmount = convertAmountHelper(
            s.amount,
            s.currency,
            userCurrency,
            s.exchangeRates.rates
          );
          // Also convert balanceBeforeSettlement if present
          if (s.balanceBeforeSettlement !== undefined) {
            convertedBalanceBefore = convertAmountHelper(
              s.balanceBeforeSettlement,
              s.currency,
              userCurrency,
              s.exchangeRates.rates
            );
          }
        }
        return {
          ...s,
          convertedAmount,
          convertedCurrency: userCurrency,
          convertedBalanceBefore,
        };
      });

    return {
      transactions,
      settlements: filteredSettlements,
      userCurrency,
    };
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
 * Balance = (friend's splits where user paid) - (settlements FROM friend) 
 *         - (user's splits where friend paid) + (settlements TO friend)
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

    // Get all splits for this friend (what friend owes)
    const friendSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    let friendOwesUserConverted = 0;
    for (const split of friendSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;

      // Only count if user paid
      const payer = await ctx.db.get(transaction.paidById);
      if (payer && payer.isSelf) {
        const txCurrency = transaction.currency;
        
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

    // Get user's splits where friend paid (what user owes)
    const userSplits = await ctx.db
      .query("splits")
      .withIndex("by_friend", (q) => q.eq("friendId", selfFriend._id))
      .collect();

    let userOwesFriendConverted = 0;
    for (const split of userSplits) {
      const transaction = await ctx.db.get(split.transactionId);
      if (!transaction) continue;

      // Only count if friend paid
      if (transaction.paidById === args.friendId) {
        const txCurrency = transaction.currency;
        
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

    // Get all settlements with this friend
    const settlements = await ctx.db
      .query("settlements")
      .withIndex("by_friend", (q) => q.eq("friendId", args.friendId))
      .collect();

    let settlementsFromFriendConverted = 0;
    let settlementsToFriendConverted = 0;

    for (const settlement of settlements) {
      if (settlement.createdById !== user._id) continue;

      let convertedAmount = settlement.amount;
      if (settlement.currency !== userCurrency && settlement.exchangeRates?.rates) {
        convertedAmount = convertAmountHelper(
          settlement.amount,
          settlement.currency,
          userCurrency,
          settlement.exchangeRates.rates
        );
      }

      if (settlement.direction === "from_friend") {
        settlementsFromFriendConverted += convertedAmount;
      } else if (settlement.direction === "to_friend") {
        settlementsToFriendConverted += convertedAmount;
      }
    }

    // Calculate final amounts after settlements
    const effectiveFriendOwes = friendOwesUserConverted - settlementsFromFriendConverted;
    const effectiveUserOwes = userOwesFriendConverted - settlementsToFriendConverted;

    return {
      friendOwesUser: effectiveFriendOwes,
      userOwesFriend: effectiveUserOwes,
      netBalance: effectiveFriendOwes - effectiveUserOwes,
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
