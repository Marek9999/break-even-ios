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
      isSettled: true,
      settledAt: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx1Id,
      friendId: bobId,
      amount: 40.00,
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx1Id,
      friendId: charlieId,
      amount: 40.00,
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
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx2Id,
      friendId: bobId,
      amount: 39.00,
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

    // Splits for movie (3 people, £12 each)
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: selfFriend!._id,
      amount: 12.00, // £12 GBP
      isSettled: true,
      settledAt: now - 8 * 24 * 60 * 60 * 1000,
      settledById: currentUser._id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: bobId,
      amount: 12.00,
      isSettled: true,
      settledAt: now - 9 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx3Id,
      friendId: charlieId,
      amount: 12.00,
      isSettled: true,
      settledAt: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
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
      percentage: 50,
      isSettled: true,
      settledAt: now - 1 * 24 * 60 * 60 * 1000,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx4Id,
      friendId: dianaId,
      amount: 750.00,
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
      isSettled: true,
      settledAt: now - 3 * 24 * 60 * 60 * 1000,
      createdAt: now - 3 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx5Id,
      friendId: charlieId,
      amount: 4485.00, // ~$30 USD
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
      isSettled: false,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });
    await ctx.db.insert("splits", {
      transactionId: tx6Id,
      friendId: dianaId,
      amount: 415.00,
      isSettled: true,
      settledAt: now - 4 * 24 * 60 * 60 * 1000,
      createdAt: now - 4 * 24 * 60 * 60 * 1000,
    });

    return {
      message: "Sample data created for your account!",
      created: {
        friends: 3,
        transactions: 6,
        splits: 15,
      },
      summary: {
        currencies: "USD, EUR, GBP, JPY, INR",
        youAreOwed: "$40 from Bob (USD) + $40 from Charlie (USD) + $750 from Diana (USD) + ¥4485 from Charlie (JPY) = ~$860 total",
        youOwe: "€39 to Bob (EUR) + ₹415 to Diana (INR) = ~$47 total",
        netBalance: "You are owed ~$813 (amounts converted to USD)",
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
      isSettled: true, // Alice paid, so her part is settled
      settledAt: now - 2 * 24 * 60 * 60 * 1000,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendBobId,
      amount: perPersonDinner,
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendCharlieId,
      amount: perPersonDinner,
      isSettled: false,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 2 (Groceries - By Item)
    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceSelfId,
      amount: 22.625, // Half of milk+eggs (7.625) + third of household (15)
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendBobId,
      amount: 48.125, // Half of milk+eggs (7.625) + snacks (25.50) + third of household (15)
      isSettled: true, // Bob paid, his part is settled
      settledAt: now - 5 * 24 * 60 * 60 * 1000,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00, // Third of household items
      isSettled: false,
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 3 (Movie - Unequal, all settled)
    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceSelfId,
      amount: 15.00,
      isSettled: true,
      settledAt: now - 8 * 24 * 60 * 60 * 1000,
      settledById: user1Id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendBobId,
      amount: 15.00,
      isSettled: true,
      settledAt: now - 9 * 24 * 60 * 60 * 1000,
      settledById: user2Id,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00,
      isSettled: true, // Charlie paid
      settledAt: now - 10 * 24 * 60 * 60 * 1000,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 4 (Rent - By Parts: Alice 2 parts, Bob 1 part, Diana 1 part)
    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceSelfId,
      amount: 1200.00, // 2/4 parts
      percentage: 50,
      isSettled: true, // Alice paid
      settledAt: now - 1 * 24 * 60 * 60 * 1000,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceFriendBobId,
      amount: 600.00, // 1/4 parts
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
      },
    };
  },
});
