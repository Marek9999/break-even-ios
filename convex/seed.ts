import { mutation } from "./_generated/server";
import { v } from "convex/values";

// Standard exchange rates snapshot for seed data (rates relative to USD)
const SEED_EXCHANGE_RATES = {
  baseCurrency: "USD",
  rates: {
    USD: 1.0,
    EUR: 0.92,
    GBP: 0.79,
    CAD: 1.36,
    AUD: 1.53,
    INR: 83.12,
    JPY: 149.50,
  },
  fetchedAt: Date.now(),
};

/**
 * Seed sample data for the currently logged-in user.
 * This creates friends and transactions linked to YOUR account.
 * Run from the app or: npx convex run seed:seedForCurrentUser '{"clerkId": "your_clerk_id"}'
 */
export const seedForCurrentUser = mutation({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, { clerkId }) => {
    const now = Date.now();

    // Find the current user
    const currentUser = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", clerkId))
      .first();

    if (!currentUser) {
      throw new Error("User not found. Please log in first.");
    }

    // Check if user already has friends (besides self)
    const existingFriends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", currentUser._id))
      .collect();

    if (existingFriends.length > 1) {
      return { message: "You already have sample data. Delete friends first to re-seed." };
    }

    // Find or create the "self" friend entry
    let selfFriend = existingFriends.find((f) => f.isSelf);
    if (!selfFriend) {
      const selfId = await ctx.db.insert("friends", {
        ownerId: currentUser._id,
        linkedUserId: currentUser._id,
        name: currentUser.name,
        email: currentUser.email,
        phone: currentUser.phone,
        avatarUrl: currentUser.avatarUrl,
        isDummy: false,
        isSelf: true,
        createdAt: now,
      });
      selfFriend = await ctx.db.get(selfId);
    }

    // ============================================
    // CREATE DUMMY FRIENDS
    // ============================================
    const bobId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Bob Smith",
      email: "bob@example.com",
      phone: "+1987654321",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Bob",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    const charlieId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Charlie Brown",
      email: "charlie@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Charlie",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    const dianaId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Diana Ross",
      email: "diana@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Diana",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    // Eve - Will be a FULLY SETTLED friend (all balances = 0)
    const eveId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Eve Martinez",
      email: "eve@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Eve",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    // Frank - Will have PARTIAL SETTLEMENTS
    const frankId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Frank Wilson",
      email: "frank@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Frank",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    // ============================================
    // CREATE TRANSACTIONS (with exchange rates)
    // ============================================

    // Transaction 1: Dinner in USD (YOU paid, others owe you)
    const tx1Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Dinner at Italian Place",
      emoji: "🍝",
      description: "Team dinner celebration",
      totalAmount: 120.00,
      currency: "USD",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Splits for dinner (3 people, $40 each)
    await ctx.db.insert("splits", {
      transactionId: tx1Id,
      friendId: selfFriend!._id,
      amount: 40.00,
      settledAmount: 40.00,  // Payer's share is fully settled
      isSettled: true,
      settledAt: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx1Id,
      friendId: bobId,
      amount: 40.00,
      settledAmount: 0,  // Not settled at all
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx1Id,
      friendId: charlieId,
      amount: 40.00,
      settledAmount: 0,  // Not settled at all
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Transaction 2: Groceries in EUR (Bob paid, YOU owe Bob) - Tests EUR conversion
    const tx2Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: bobId,
      title: "Weekly Groceries",
      emoji: "🛒",
      totalAmount: 78.00, // €78 EUR
      currency: "EUR",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Splits for groceries (2 people, €39 each)
    await ctx.db.insert("splits", {
      transactionId: tx2Id,
      friendId: selfFriend!._id,
      amount: 39.00, // €39 EUR
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx2Id,
      friendId: bobId,
      amount: 39.00,
      settledAmount: 39.00,  // Payer's share
      isSettled: true,
      settledAt: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Transaction 3: Movie in GBP (Charlie paid, settled) - Tests GBP conversion
    const tx3Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: charlieId,
      title: "Movie Night",
      emoji: "🎬",
      description: "Avengers movie",
      totalAmount: 36.00, // £36 GBP
      currency: "GBP",
      splitMethod: "equal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Splits for movie (3 people, £12 each) - ALL SETTLED
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: selfFriend!._id,
      amount: 12.00, // £12 GBP
      settledAmount: 12.00,
      isSettled: true,
      settledAt: now - 8 * 24 * 60 * 60 * 1000,
      settledById: currentUser._id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: bobId,
      amount: 12.00,
      settledAmount: 12.00,
      isSettled: true,
      settledAt: now - 9 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: charlieId,
      amount: 12.00,
      settledAmount: 12.00,  // Payer's share
      isSettled: true,
      settledAt: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Settlement record for Movie Night - User paid Charlie back £12
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: charlieId,
      amount: 12.00,
      currency: "GBP",
      direction: "to_friend",  // User paid Charlie
      balanceBeforeSettlement: 12.00,  // User owed £12 before paying
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: "[]",
      settledAt: now - 8 * 24 * 60 * 60 * 1000,
      createdAt: now - 8 * 24 * 60 * 60 * 1000,
    });

    // Transaction 4: Rent in USD (YOU paid)
    const tx4Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Monthly Rent",
      emoji: "🏠",
      description: "Apartment rent",
      totalAmount: 1500.00,
      currency: "USD",
      splitMethod: "byParts",
      status: "partial",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 1 * 24 * 60 * 60 * 1000,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    // Splits for rent
    await ctx.db.insert("splits", {
      transactionId: tx4Id,
      friendId: selfFriend!._id,
      amount: 750.00,
      settledAmount: 750.00,  // Payer's share
      percentage: 50,
      isSettled: true,
      settledAt: now - 1 * 24 * 60 * 60 * 1000,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx4Id,
      friendId: dianaId,
      amount: 750.00,
      settledAmount: 0,
      percentage: 50,
      isSettled: false,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    // Transaction 5: Sushi in JPY (YOU paid, Charlie owes) - Tests JPY conversion
    const tx5Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Sushi Dinner",
      emoji: "🍣",
      description: "Japanese restaurant",
      totalAmount: 8970.00, // ¥8970 JPY (~$60 USD)
      currency: "JPY",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 3 * 24 * 60 * 60 * 1000,
      createdAt: now - 3 * 24 * 60 * 60 * 1000,
    });

    // Splits for sushi (2 people, ¥4485 each)
    await ctx.db.insert("splits", {
      transactionId: tx5Id,
      friendId: selfFriend!._id,
      amount: 4485.00,
      settledAmount: 4485.00,  // Payer's share
      isSettled: true,
      settledAt: now - 3 * 24 * 60 * 60 * 1000,
      createdAt: now - 3 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx5Id,
      friendId: charlieId,
      amount: 4485.00, // ~$30 USD
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 3 * 24 * 60 * 60 * 1000,
    });

    // Transaction 6: Coffee in INR (Diana paid, YOU owe) - Tests INR conversion
    const tx6Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: dianaId,
      title: "Coffee Run",
      emoji: "☕",
      description: "Coffee and snacks",
      totalAmount: 830.00, // ₹830 INR (~$10 USD)
      currency: "INR",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 4 * 24 * 60 * 60 * 1000,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });

    // Splits for coffee (2 people, ₹415 each)
    await ctx.db.insert("splits", {
      transactionId: tx6Id,
      friendId: selfFriend!._id,
      amount: 415.00, // ~$5 USD
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx6Id,
      friendId: dianaId,
      amount: 415.00,
      settledAmount: 415.00,  // Payer's share
      isSettled: true,
      settledAt: now - 4 * 24 * 60 * 60 * 1000,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });

    // ============================================
    // FULLY SETTLED FRIEND (Eve) - All transactions settled
    // ============================================

    // Transaction 7: Concert tickets with Eve (YOU paid, Eve settled)
    const tx7Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Concert Tickets",
      emoji: "🎵",
      description: "Taylor Swift concert",
      totalAmount: 300.00,
      currency: "USD",
      splitMethod: "equal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 30 * 24 * 60 * 60 * 1000,
      createdAt: now - 30 * 24 * 60 * 60 * 1000,
    });

    // Splits for concert (2 people, $150 each) - ALL SETTLED
    await ctx.db.insert("splits", {
      transactionId: tx7Id,
      friendId: selfFriend!._id,
      amount: 150.00,
      settledAmount: 150.00,
      isSettled: true,
      settledAt: now - 30 * 24 * 60 * 60 * 1000,
      createdAt: now - 30 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx7Id,
      friendId: eveId,
      amount: 150.00,
      settledAmount: 150.00,  // Eve fully settled
      isSettled: true,
      settledAt: now - 25 * 24 * 60 * 60 * 1000,
      settledById: currentUser._id,
      createdAt: now - 30 * 24 * 60 * 60 * 1000,
    });

    // Transaction 8: Brunch where Eve paid (YOU settled your share)
    const tx8Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: eveId,
      title: "Weekend Brunch",
      emoji: "🥞",
      description: "Brunch at the cafe",
      totalAmount: 80.00,
      currency: "USD",
      splitMethod: "equal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 15 * 24 * 60 * 60 * 1000,
      createdAt: now - 15 * 24 * 60 * 60 * 1000,
    });

    // Splits for brunch - ALL SETTLED
    await ctx.db.insert("splits", {
      transactionId: tx8Id,
      friendId: selfFriend!._id,
      amount: 40.00,
      settledAmount: 40.00,  // You settled your share
      isSettled: true,
      settledAt: now - 14 * 24 * 60 * 60 * 1000,
      settledById: currentUser._id,
      createdAt: now - 15 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx8Id,
      friendId: eveId,
      amount: 40.00,
      settledAmount: 40.00,  // Eve paid
      isSettled: true,
      settledAt: now - 15 * 24 * 60 * 60 * 1000,
      createdAt: now - 15 * 24 * 60 * 60 * 1000,
    });

    // Create settlement record for Eve (brunch settlement)
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: eveId,
      amount: 40.00,
      currency: "USD",
      direction: "to_friend",  // User paid Eve
      balanceBeforeSettlement: 40.00,  // User owed $40 for brunch
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: "[]",  // Simplified for seed
      settledAt: now - 14 * 24 * 60 * 60 * 1000,
      createdAt: now - 14 * 24 * 60 * 60 * 1000,
    });

    // Create settlement record for Eve (concert settlement)
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: eveId,
      amount: 150.00,
      currency: "USD",
      direction: "from_friend",  // Eve paid user
      balanceBeforeSettlement: 150.00,  // Eve owed $150 for concert
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: "[]",
      settledAt: now - 25 * 24 * 60 * 60 * 1000,
      createdAt: now - 25 * 24 * 60 * 60 * 1000,
    });

    // ============================================
    // PARTIAL SETTLEMENTS (Frank)
    // ============================================

    // Transaction 9: Big dinner with Frank (YOU paid, Frank PARTIALLY settled)
    const tx9Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Birthday Dinner",
      emoji: "🎂",
      description: "Frank's birthday celebration",
      totalAmount: 200.00,
      currency: "USD",
      splitMethod: "equal",
      status: "partial",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 7 * 24 * 60 * 60 * 1000,
      createdAt: now - 7 * 24 * 60 * 60 * 1000,
    });

    // Splits for birthday dinner - Frank PARTIALLY settled ($60 of $100)
    await ctx.db.insert("splits", {
      transactionId: tx9Id,
      friendId: selfFriend!._id,
      amount: 100.00,
      settledAmount: 100.00,  // Payer's share
      isSettled: true,
      settledAt: now - 7 * 24 * 60 * 60 * 1000,
      createdAt: now - 7 * 24 * 60 * 60 * 1000,
    });
    const frankSplit1Id = await ctx.db.insert("splits", {
      transactionId: tx9Id,
      friendId: frankId,
      amount: 100.00,
      settledAmount: 60.00,  // PARTIAL: Frank paid $60 of $100
      isSettled: false,  // Not fully settled
      createdAt: now - 7 * 24 * 60 * 60 * 1000,
    });

    // Settlement record for Frank's partial payment
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: frankId,
      amount: 60.00,
      currency: "USD",
      direction: "from_friend",  // Frank paid user
      note: "First partial payment",
      balanceBeforeSettlement: 100.00,  // Frank owed $100 before this payment
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: JSON.stringify([{ splitId: frankSplit1Id, amountApplied: 60.00 }]),
      settledAt: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Transaction 10: Trip expenses with Frank (Frank paid, YOU PARTIALLY settled)
    const tx10Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: frankId,
      title: "Road Trip Gas",
      emoji: "⛽",
      description: "Gas for road trip",
      totalAmount: 80.00,
      currency: "USD",
      splitMethod: "equal",
      status: "partial",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 6 * 24 * 60 * 60 * 1000,
      createdAt: now - 6 * 24 * 60 * 60 * 1000,
    });

    // Splits for gas - YOU PARTIALLY settled ($25 of $40)
    const userSplitFrankId = await ctx.db.insert("splits", {
      transactionId: tx10Id,
      friendId: selfFriend!._id,
      amount: 40.00,
      settledAmount: 25.00,  // PARTIAL: User paid $25 of $40
      isSettled: false,  // Not fully settled
      createdAt: now - 6 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx10Id,
      friendId: frankId,
      amount: 40.00,
      settledAmount: 40.00,  // Frank paid (payer's share)
      isSettled: true,
      settledAt: now - 6 * 24 * 60 * 60 * 1000,
      createdAt: now - 6 * 24 * 60 * 60 * 1000,
    });

    // Settlement record for user's partial payment to Frank
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: frankId,
      amount: 25.00,
      currency: "USD",
      direction: "to_friend",  // User paid Frank
      note: "Partial payment for gas",
      balanceBeforeSettlement: 40.00,  // User owed $40 before this payment
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: JSON.stringify([{ splitId: userSplitFrankId, amountApplied: 25.00 }]),
      settledAt: now - 4 * 24 * 60 * 60 * 1000,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });

    // Transaction 11: Another dinner with Frank in EUR (Partial, multi-currency test)
    const tx11Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Paris Dinner",
      emoji: "🗼",
      description: "Dinner while traveling",
      totalAmount: 92.00, // €92 EUR
      currency: "EUR",
      splitMethod: "equal",
      status: "partial",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 12 * 24 * 60 * 60 * 1000,
      createdAt: now - 12 * 24 * 60 * 60 * 1000,
    });

    // Splits for Paris dinner - Frank PARTIALLY settled (€20 of €46)
    await ctx.db.insert("splits", {
      transactionId: tx11Id,
      friendId: selfFriend!._id,
      amount: 46.00,
      settledAmount: 46.00,  // Payer's share
      isSettled: true,
      settledAt: now - 12 * 24 * 60 * 60 * 1000,
      createdAt: now - 12 * 24 * 60 * 60 * 1000,
    });
    const frankSplit2Id = await ctx.db.insert("splits", {
      transactionId: tx11Id,
      friendId: frankId,
      amount: 46.00,
      settledAmount: 20.00,  // PARTIAL: Frank paid €20 of €46
      isSettled: false,
      createdAt: now - 12 * 24 * 60 * 60 * 1000,
    });

    // Settlement record for Frank's partial payment (EUR)
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: frankId,
      amount: 20.00,
      currency: "EUR",
      direction: "from_friend",
      note: "Partial payment in EUR",
      balanceBeforeSettlement: 46.00,  // Frank owed €46 before this payment
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: JSON.stringify([{ splitId: frankSplit2Id, amountApplied: 20.00 }]),
      settledAt: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // ============================================
    // SETTLE-ALL HISTORY (Grace) - Tests "Show Older" feature
    // ============================================

    // Grace - Has old transactions that were fully settled, then new transactions after
    const graceId = await ctx.db.insert("friends", {
      ownerId: currentUser._id,
      name: "Grace Kim",
      email: "grace@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Grace",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    // OLD Transaction 12: Lunch from 60 days ago (YOU paid, Grace owed - NOW FULLY SETTLED)
    const tx12Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Team Lunch",
      emoji: "🥗",
      description: "Old team lunch",
      totalAmount: 60.00,
      currency: "USD",
      splitMethod: "equal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 60 * 24 * 60 * 60 * 1000,
      createdAt: now - 60 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: tx12Id,
      friendId: selfFriend!._id,
      amount: 30.00,
      settledAmount: 30.00,
      isSettled: true,
      settledAt: now - 60 * 24 * 60 * 60 * 1000,
      createdAt: now - 60 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx12Id,
      friendId: graceId,
      amount: 30.00,
      settledAmount: 30.00,  // Fully settled via settle-all
      isSettled: true,
      settledAt: now - 45 * 24 * 60 * 60 * 1000,  // Settled 45 days ago
      settledById: currentUser._id,
      createdAt: now - 60 * 24 * 60 * 60 * 1000,
    });

    // OLD Transaction 13: Coffee from 55 days ago (Grace paid, YOU owed - NOW FULLY SETTLED)
    const tx13Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: graceId,
      title: "Coffee Run",
      emoji: "☕",
      description: "Morning coffee",
      totalAmount: 20.00,
      currency: "USD",
      splitMethod: "equal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 55 * 24 * 60 * 60 * 1000,
      createdAt: now - 55 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: tx13Id,
      friendId: selfFriend!._id,
      amount: 10.00,
      settledAmount: 10.00,  // Fully settled via settle-all
      isSettled: true,
      settledAt: now - 45 * 24 * 60 * 60 * 1000,
      settledById: currentUser._id,
      createdAt: now - 55 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx13Id,
      friendId: graceId,
      amount: 10.00,
      settledAmount: 10.00,
      isSettled: true,
      settledAt: now - 55 * 24 * 60 * 60 * 1000,
      createdAt: now - 55 * 24 * 60 * 60 * 1000,
    });

    // SETTLE-ALL EVENT (45 days ago) - Cleared everything with Grace
    // Net at that point: Grace owed $30, User owed $10 = Net $20 to user
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: graceId,
      amount: 20.00,  // Net amount settled
      currency: "USD",
      direction: "from_friend",  // Grace paid user the net difference
      note: "Settled all",
      balanceBeforeSettlement: 20.00,  // Net balance was $20 (Grace owed)
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: "[]",
      settledAt: now - 45 * 24 * 60 * 60 * 1000,
      createdAt: now - 45 * 24 * 60 * 60 * 1000,
    });

    // NEW Transaction 14: Dinner 5 days ago (YOU paid, Grace owes - PARTIAL because Grace paid $20 of $50)
    const tx14Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: selfFriend!._id,
      title: "Sushi Night",
      emoji: "🍣",
      description: "New dinner after settle-all",
      totalAmount: 100.00,
      currency: "USD",
      splitMethod: "equal",
      status: "partial",  // Partial because Grace paid $20 of $50
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: tx14Id,
      friendId: selfFriend!._id,
      amount: 50.00,
      settledAmount: 50.00,
      isSettled: true,
      settledAt: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });
    const graceSplit1Id = await ctx.db.insert("splits", {
      transactionId: tx14Id,
      friendId: graceId,
      amount: 50.00,
      settledAmount: 20.00,  // Grace paid $20 of $50 (partial)
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Partial settlement from Grace (3 days ago)
    await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: graceId,
      amount: 20.00,
      currency: "USD",
      direction: "from_friend",
      note: "Partial payment for sushi",
      balanceBeforeSettlement: 50.00,  // Grace owed $50 before this payment
      exchangeRates: SEED_EXCHANGE_RATES,
      affectedSplitsJson: JSON.stringify([{ splitId: graceSplit1Id, amountApplied: 20.00 }]),
      settledAt: now - 3 * 24 * 60 * 60 * 1000,
      createdAt: now - 3 * 24 * 60 * 60 * 1000,
    });

    // NEW Transaction 15: Movie 2 days ago (Grace paid, YOU owe - PENDING)
    const tx15Id = await ctx.db.insert("transactions", {
      createdById: currentUser._id,
      paidById: graceId,
      title: "Movie Night",
      emoji: "🎬",
      description: "New movie after settle-all",
      totalAmount: 40.00,
      currency: "USD",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: tx15Id,
      friendId: selfFriend!._id,
      amount: 20.00,
      settledAmount: 0,  // Not settled yet
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx15Id,
      friendId: graceId,
      amount: 20.00,
      settledAmount: 20.00,
      isSettled: true,
      settledAt: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    return {
      message: "Sample data created for your account!",
      created: {
        friends: 6, // Bob, Charlie, Diana, Eve, Frank, Grace
        transactions: 15,
        splits: 32,
        settlements: 9,  // Added 1 for Charlie Movie Night
      },
      summary: {
        currencies: "USD, EUR, GBP, JPY, INR",
        fullySettledFriend: "Eve Martinez - All balances settled (net $0)",
        partialSettlements: "Frank Wilson - NET: owes $40 ($100-$60) + €26 ($46-€20) = ~$68.26; you owe $15 ($40-$25) = NET ~$53 Frank owes you",
        settleAllHistory: "Grace Kim - After settle-all: owes $30 ($50-$20 settled), you owe $20 (movie) = NET $10 Grace owes you",
        pendingBalances: "Bob: owes $40, you owe €39 = NET ~$2.40 you owe Bob | Charlie: owes $40 + ¥4485 (~$30), Movie Night £12 settled = NET ~$70 Charlie owes | Diana: owes $750, you owe ₹415 (~$5) = NET ~$745 Diana owes",
      },
    };
  },
});

/**
 * Seed the database with sample data for development/testing.
 * Run with: npx convex run seed:seedDatabase
 */
export const seedDatabase = mutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();

    // Check if data already exists
    const existingUsers = await ctx.db.query("users").collect();
    if (existingUsers.length > 0) {
      return { message: "Database already has data. Skipping seed." };
    }

    // ============================================
    // 1. CREATE SAMPLE USERS
    // ============================================
    const user1Id = await ctx.db.insert("users", {
      clerkId: "user_sample_alice_123",
      email: "alice@example.com",
      name: "Alice Johnson",
      phone: "+1234567890",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Alice",
      defaultCurrency: "USD",
      createdAt: now,
    });

    const user2Id = await ctx.db.insert("users", {
      clerkId: "user_sample_bob_456",
      email: "bob@example.com",
      name: "Bob Smith",
      phone: "+1987654321",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Bob",
      defaultCurrency: "USD",
      createdAt: now,
    });

    const user3Id = await ctx.db.insert("users", {
      clerkId: "user_sample_charlie_789",
      email: "charlie@example.com",
      name: "Charlie Brown",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Charlie",
      defaultCurrency: "EUR",
      createdAt: now,
    });

    // ============================================
    // 2. CREATE FRIENDS FOR USER 1 (Alice)
    // ============================================
    
    // Alice's "self" friend entry
    const aliceSelfId = await ctx.db.insert("friends", {
      ownerId: user1Id,
      linkedUserId: user1Id,
      name: "Alice Johnson",
      email: "alice@example.com",
      phone: "+1234567890",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Alice",
      isDummy: false,
      isSelf: true,
      createdAt: now,
    });

    // Alice's friend: Bob (linked user)
    const aliceFriendBobId = await ctx.db.insert("friends", {
      ownerId: user1Id,
      linkedUserId: user2Id,
      name: "Bob Smith",
      email: "bob@example.com",
      phone: "+1987654321",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Bob",
      isDummy: false,
      isSelf: false,
      createdAt: now,
    });

    // Alice's friend: Charlie (linked user)
    const aliceFriendCharlieId = await ctx.db.insert("friends", {
      ownerId: user1Id,
      linkedUserId: user3Id,
      name: "Charlie Brown",
      email: "charlie@example.com",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Charlie",
      isDummy: false,
      isSelf: false,
      createdAt: now,
    });

    // Alice's dummy friend: Diana (not a real user)
    const aliceFriendDianaId = await ctx.db.insert("friends", {
      ownerId: user1Id,
      name: "Diana Ross",
      email: "diana@example.com",
      isDummy: true,
      isSelf: false,
      createdAt: now,
    });

    // ============================================
    // 3. CREATE FRIENDS FOR USER 2 (Bob)
    // ============================================
    
    // Bob's "self" friend entry
    const bobSelfId = await ctx.db.insert("friends", {
      ownerId: user2Id,
      linkedUserId: user2Id,
      name: "Bob Smith",
      email: "bob@example.com",
      phone: "+1987654321",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Bob",
      isDummy: false,
      isSelf: true,
      createdAt: now,
    });

    // Bob's friend: Alice (linked user)
    const bobFriendAliceId = await ctx.db.insert("friends", {
      ownerId: user2Id,
      linkedUserId: user1Id,
      name: "Alice Johnson",
      email: "alice@example.com",
      phone: "+1234567890",
      avatarUrl: "https://api.dicebear.com/7.x/avataaars/svg?seed=Alice",
      isDummy: false,
      isSelf: false,
      createdAt: now,
    });

    // ============================================
    // 4. CREATE SAMPLE TRANSACTIONS (with exchange rates)
    // ============================================

    // Transaction 1: Dinner split (Equal) - Alice paid in USD
    const transaction1Id = await ctx.db.insert("transactions", {
      createdById: user1Id,
      paidById: aliceSelfId,
      title: "Dinner at Italian Place",
      emoji: "🍝",
      description: "Team dinner celebration",
      totalAmount: 120.50,
      currency: "USD",
      splitMethod: "equal",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 2 * 24 * 60 * 60 * 1000, // 2 days ago
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Transaction 2: Groceries (By Item) - Bob paid in EUR
    const transaction2Id = await ctx.db.insert("transactions", {
      createdById: user1Id,
      paidById: aliceFriendBobId,
      title: "Weekly Groceries",
      emoji: "🛒",
      totalAmount: 78.89, // EUR
      currency: "EUR",
      splitMethod: "byItem",
      status: "pending",
      exchangeRates: SEED_EXCHANGE_RATES,
      items: [
        {
          id: "item1",
          name: "Milk & Eggs",
          quantity: 1,
          unitPrice: 14.03,
          assignedToIds: [aliceSelfId, aliceFriendBobId],
        },
        {
          id: "item2",
          name: "Snacks",
          quantity: 1,
          unitPrice: 23.46,
          assignedToIds: [aliceFriendBobId],
        },
        {
          id: "item3",
          name: "Household Items",
          quantity: 1,
          unitPrice: 41.40,
          assignedToIds: [aliceSelfId, aliceFriendBobId, aliceFriendCharlieId],
        },
      ],
      date: now - 5 * 24 * 60 * 60 * 1000, // 5 days ago
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Transaction 3: Movie tickets (Unequal) - Charlie paid in GBP
    const transaction3Id = await ctx.db.insert("transactions", {
      createdById: user1Id,
      paidById: aliceFriendCharlieId,
      title: "Movie Night",
      emoji: "🎬",
      description: "Avengers movie",
      totalAmount: 35.55, // GBP
      currency: "GBP",
      splitMethod: "unequal",
      status: "settled",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 10 * 24 * 60 * 60 * 1000, // 10 days ago
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Transaction 4: Rent split (By Parts) - Alice paid in USD
    const transaction4Id = await ctx.db.insert("transactions", {
      createdById: user1Id,
      paidById: aliceSelfId,
      title: "Monthly Rent",
      emoji: "🏠",
      description: "Apartment rent for January",
      totalAmount: 2400.00,
      currency: "USD",
      splitMethod: "byParts",
      status: "partial",
      exchangeRates: SEED_EXCHANGE_RATES,
      date: now - 1 * 24 * 60 * 60 * 1000, // 1 day ago
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    // ============================================
    // 5. CREATE SPLITS FOR TRANSACTIONS
    // ============================================

    // Splits for Transaction 1 (Dinner - Equal split among 3)
    const perPersonDinner = 120.50 / 3;
    
    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceSelfId,
      amount: perPersonDinner,
      settledAmount: perPersonDinner,  // Payer's share fully settled
      isSettled: true, // Alice paid, so her part is settled
      settledAt: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendBobId,
      amount: perPersonDinner,
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendCharlieId,
      amount: perPersonDinner,
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 2 (Groceries - By Item)
    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceSelfId,
      amount: 22.625, // Half of milk+eggs (7.625) + third of household (15)
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendBobId,
      amount: 48.125, // Half of milk+eggs (7.625) + snacks (25.50) + third of household (15)
      settledAmount: 48.125,  // Payer's share fully settled
      isSettled: true, // Bob paid, his part is settled
      settledAt: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00, // Third of household items
      settledAmount: 0,
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 3 (Movie - Unequal, all settled)
    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceSelfId,
      amount: 15.00,
      settledAmount: 15.00,
      isSettled: true,
      settledAt: now - 8 * 24 * 60 * 60 * 1000,
      settledById: user1Id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendBobId,
      amount: 15.00,
      settledAmount: 15.00,
      isSettled: true,
      settledAt: now - 9 * 24 * 60 * 60 * 1000,
      settledById: user2Id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00,
      settledAmount: 15.00,  // Payer's share
      isSettled: true, // Charlie paid
      settledAt: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 4 (Rent - By Parts: Alice 2 parts, Bob 1 part, Diana 1 part)
    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceSelfId,
      amount: 1200.00, // 2/4 parts
      settledAmount: 1200.00,  // Payer's share
      percentage: 50,
      isSettled: true, // Alice paid
      settledAt: now - 1 * 24 * 60 * 60 * 1000,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceFriendBobId,
      amount: 600.00, // 1/4 parts
      settledAmount: 600.00,
      percentage: 25,
      isSettled: true,
      settledAt: now,
      settledById: user2Id,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceFriendDianaId,
      amount: 600.00, // 1/4 parts
      settledAmount: 0,
      percentage: 25,
      isSettled: false, // Diana hasn't paid yet
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    // ============================================
    // 6. CREATE SAMPLE INVITATION
    // ============================================
    await ctx.db.insert("invitations", {
      senderId: user1Id,
      friendId: aliceFriendDianaId,
      recipientEmail: "diana@example.com",
      status: "pending",
      token: "invite_diana_abc123xyz",
      expiresAt: now + 7 * 24 * 60 * 60 * 1000, // Expires in 7 days
      createdAt: now,
    });

    return {
      message: "Database seeded successfully!",
      created: {
        users: 3,
        friends: 7,
        transactions: 4,
        splits: 12,
        invitations: 1,
      },
    };
  },
});

/**
 * Clear all data from the database.
 * Run with: npx convex run seed:clearDatabase
 * WARNING: This will delete ALL data!
 */
export const clearDatabase = mutation({
  args: {
    confirmDelete: v.boolean(),
  },
  handler: async (ctx, { confirmDelete }) => {
    if (!confirmDelete) {
      return { message: "Deletion cancelled. Pass confirmDelete: true to proceed." };
    }

    // Delete in reverse order of dependencies
    const invitations = await ctx.db.query("invitations").collect();
    for (const inv of invitations) {
      await ctx.db.delete(inv._id);
    }

    const settlements = await ctx.db.query("settlements").collect();
    for (const settlement of settlements) {
      await ctx.db.delete(settlement._id);
    }

    const splits = await ctx.db.query("splits").collect();
    for (const split of splits) {
      await ctx.db.delete(split._id);
    }

    const transactions = await ctx.db.query("transactions").collect();
    for (const tx of transactions) {
      await ctx.db.delete(tx._id);
    }

    const friends = await ctx.db.query("friends").collect();
    for (const friend of friends) {
      await ctx.db.delete(friend._id);
    }

    const users = await ctx.db.query("users").collect();
    for (const user of users) {
      await ctx.db.delete(user._id);
    }

    // Also clear exchange rates cache
    const exchangeRates = await ctx.db.query("exchangeRates").collect();
    for (const rate of exchangeRates) {
      await ctx.db.delete(rate._id);
    }

    return {
      message: "Database cleared successfully!",
      deleted: {
        users: users.length,
        friends: friends.length,
        transactions: transactions.length,
        splits: splits.length,
        settlements: settlements.length,
        invitations: invitations.length,
        exchangeRates: exchangeRates.length,
      },
    };
  },
});

/**
 * Clear seed data for the current user (friends, transactions, splits).
 * Run with: npx convex run seed:clearUserData '{"clerkId": "your_clerk_id"}'
 */
export const clearUserData = mutation({
  args: {
    clerkId: v.string(),
  },
  handler: async (ctx, { clerkId }) => {
    // Find the current user
    const currentUser = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", clerkId))
      .first();

    if (!currentUser) {
      return { message: "User not found." };
    }

    // Get all friends for this user
    const friends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", currentUser._id))
      .collect();

    const friendIds = friends.map((f) => f._id);

    // Delete all settlements for this user's friends
    let settlementsDeleted = 0;
    for (const friend of friends) {
      const settlements = await ctx.db
        .query("settlements")
        .withIndex("by_friend", (q) => q.eq("friendId", friend._id))
        .collect();
      for (const settlement of settlements) {
        await ctx.db.delete(settlement._id);
        settlementsDeleted++;
      }
    }

    // Delete all splits for transactions created by this user
    const transactions = await ctx.db
      .query("transactions")
      .filter((q) => q.eq(q.field("createdById"), currentUser._id))
      .collect();

    let splitsDeleted = 0;
    for (const tx of transactions) {
      const splits = await ctx.db
        .query("splits")
        .withIndex("by_transaction", (q) => q.eq("transactionId", tx._id))
        .collect();
      for (const split of splits) {
        await ctx.db.delete(split._id);
        splitsDeleted++;
      }
    }

    // Delete all transactions created by this user
    for (const tx of transactions) {
      await ctx.db.delete(tx._id);
    }

    // Delete all friends except the self entry
    let friendsDeleted = 0;
    for (const friend of friends) {
      if (!friend.isSelf) {
        await ctx.db.delete(friend._id);
        friendsDeleted++;
      }
    }

    return {
      message: "User data cleared successfully! You can now run seedForCurrentUser again.",
      deleted: {
        friends: friendsDeleted,
        transactions: transactions.length,
        splits: splitsDeleted,
        settlements: settlementsDeleted,
      },
    };
  },
});
