import { internalMutation, internalQuery, mutation } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { v } from "convex/values";
import { requireIdentity } from "./lib/auth";

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

const SEED_RECEIPT_FILE_IDS = {
  sengyoSushi: "kg2d9hxktvtzs6zwfhjrc55m5x886zdj" as Id<"_storage">,
  ihop: "kg20k6mnnnfc358gn67e2a87ad887dtb" as Id<"_storage">,
  mcdonalds: "kg2d97kdkts8px6wc0d5j5r0tx886fhp" as Id<"_storage">,
};

const SEED_RECEIPT_FILE_ID_SET = new Set<string>(Object.values(SEED_RECEIPT_FILE_IDS));

function isSeedReceiptFileId(storageId: Id<"_storage"> | string) {
  return SEED_RECEIPT_FILE_ID_SET.has(storageId.toString());
}


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
    await requireIdentity(ctx, clerkId);
    const now = Date.now();
    const day = 24 * 60 * 60 * 1000;

    const currentUser = await ctx.db
      .query("users")
      .withIndex("by_clerkId", (q) => q.eq("clerkId", clerkId))
      .first();

    if (!currentUser) {
      throw new Error("User not found. Please log in first.");
    }

    const existingFriends = await ctx.db
      .query("friends")
      .withIndex("by_owner", (q) => q.eq("ownerId", currentUser._id))
      .collect();

    if (existingFriends.length > 1) {
      return { message: "You already have sample data. Delete friends first to re-seed." };
    }

    let selfFriend = existingFriends.find((friend) => friend.isSelf);
    if (!selfFriend) {
      const selfId = await ctx.db.insert("friends", {
        ownerId: currentUser._id,
        linkedUserId: currentUser._id,
        name: currentUser.name,
        email: currentUser.email,
        phone: currentUser.phone,
        avatarUrl: currentUser.avatarUrl,
        avatarEmoji: "🙂",
        avatarColor: "#42A5F5",
        isDummy: false,
        isSelf: true,
        inviteStatus: "none",
        createdAt: now,
      });
      selfFriend = (await ctx.db.get(selfId)) ?? undefined;
    }

    if (!selfFriend) {
      throw new Error("Could not create your self contact.");
    }

    type SeedFriendKey = "maya" | "leo" | "nina" | "omar" | "sofia" | "priya";
    type SeedFriendSpec = {
      key: SeedFriendKey;
      name: string;
      email: string;
      phone?: string;
      emoji: string;
      color: string;
    };

    const friendSpecs: SeedFriendSpec[] = [
      { key: "maya", name: "Maya Patel", email: "maya@example.com", phone: "+14165550112", emoji: "🐼", color: "#EC407A" },
      { key: "leo", name: "Leo Chen", email: "leo@example.com", phone: "+14165550123", emoji: "🦊", color: "#42A5F5" },
      { key: "nina", name: "Nina Park", email: "nina@example.com", emoji: "🐨", color: "#AB47BC" },
      { key: "omar", name: "Omar Johnson", email: "omar@example.com", emoji: "🦁", color: "#66BB6A" },
      { key: "sofia", name: "Sofia Reyes", email: "sofia@example.com", emoji: "🐧", color: "#FFA726" },
      { key: "priya", name: "Priya Shah", email: "priya@example.com", emoji: "🐰", color: "#26A69A" },
    ];

    const friends = {} as Record<SeedFriendKey, Id<"friends">>;
    for (const spec of friendSpecs) {
      friends[spec.key] = await ctx.db.insert("friends", {
        ownerId: currentUser._id,
        name: spec.name,
        email: spec.email,
        phone: spec.phone,
        avatarEmoji: spec.emoji,
        avatarColor: spec.color,
        isDummy: true,
        isSelf: false,
        inviteStatus: "invite_sent",
        createdAt: now,
      });
    }

    type SeedItem = {
      name: string;
      quantity?: number;
      unitPrice: number;
      assignedToIds: Id<"friends">[];
    };

    type SeedSplit = {
      friendId: Id<"friends">;
      amount: number;
      percentage?: number;
    };

    type SeedTransaction = {
      title: string;
      emoji: string;
      description?: string;
      totalAmount: number;
      currency: string;
      splitMethod: string;
      paidById: Id<"friends">;
      daysAgo: number;
      receiptFileId?: Id<"_storage">;
      items?: SeedItem[];
      splits: SeedSplit[];
    };

    const splitFromItems = (items: SeedItem[]) => {
      const totals = new Map<string, { friendId: Id<"friends">; amount: number }>();
      for (const item of items) {
        const quantity = item.quantity ?? 1;
        const assignees = item.assignedToIds;
        const share = (quantity * item.unitPrice) / assignees.length;
        for (const friendId of assignees) {
          const key = friendId.toString();
          const current = totals.get(key) ?? { friendId, amount: 0 };
          current.amount += share;
          totals.set(key, current);
        }
      }

      return Array.from(totals.values()).map((split) => ({
        friendId: split.friendId,
        amount: Number(split.amount.toFixed(2)),
      }));
    };

    const insertTransaction = async (tx: SeedTransaction) => {
      const timestamp = now - tx.daysAgo * day;
      const transactionId = await ctx.db.insert("transactions", {
        createdById: currentUser._id,
        paidById: tx.paidById,
        title: tx.title,
        emoji: tx.emoji,
        description: tx.description,
        totalAmount: tx.totalAmount,
        currency: tx.currency,
        splitMethod: tx.splitMethod,
        receiptFileId: tx.receiptFileId,
        items: tx.items?.map((item, index) => ({
          id: `seed-${tx.title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${index + 1}`,
          name: item.name,
          quantity: item.quantity ?? 1,
          unitPrice: item.unitPrice,
          assignedToIds: item.assignedToIds,
        })),
        exchangeRates: SEED_EXCHANGE_RATES,
        date: timestamp,
        createdAt: timestamp,
      });

      for (const split of tx.splits) {
        await ctx.db.insert("splits", {
          transactionId,
          friendId: split.friendId,
          amount: split.amount,
          percentage: split.percentage,
          createdAt: timestamp,
        });
      }

      return transactionId;
    };

    const insertSeedActivity = async (args: {
      actorName: string;
      type: string;
      message: string;
      daysAgo: number;
      transactionId?: Id<"transactions">;
      friendId?: Id<"friends">;
      settlementId?: Id<"settlements">;
      isRead?: boolean;
    }) => {
      await ctx.db.insert("activities", {
        userId: currentUser._id,
        actorId: currentUser._id,
        actorName: args.actorName,
        type: args.type,
        message: args.message,
        transactionId: args.transactionId,
        friendId: args.friendId,
        settlementId: args.settlementId,
        metadata: args.transactionId
          ? JSON.stringify({ seeded: true, transactionId: args.transactionId })
          : JSON.stringify({ seeded: true }),
        isRead: args.isRead ?? false,
        createdAt: now - args.daysAgo * day,
      });
    };

    const everyone = [selfFriend._id, friends.maya, friends.leo, friends.nina];
    const sushiItems: SeedItem[] = [
      { name: "Maki A 18pcs", unitPrice: 16.95, assignedToIds: [selfFriend._id, friends.maya] },
      { name: "Veggie Roll 18pcs", unitPrice: 15.95, assignedToIds: [friends.leo, friends.nina] },
      { name: "Deep Fried Porkchop Curry", unitPrice: 14.95, assignedToIds: [selfFriend._id] },
      { name: "Takoyaki 5pcs", unitPrice: 7.45, assignedToIds: [friends.maya, friends.leo] },
      { name: "Torched 8", unitPrice: 18.45, assignedToIds: [selfFriend._id, friends.nina] },
      { name: "Veggie Gyoza 6pcs", unitPrice: 7.45, assignedToIds: [friends.leo, friends.nina] },
      { name: "Veggie Tempura Curry", unitPrice: 12.95, assignedToIds: [friends.maya] },
      { name: "Sweet Yam 6pcs", unitPrice: 5.45, assignedToIds: everyone },
      { name: "Assorted Tempura 7pcs", unitPrice: 13.45, assignedToIds: everyone },
      { name: "HST", unitPrice: 14.69, assignedToIds: everyone },
      { name: "Tip", unitPrice: 19.16, assignedToIds: everyone },
    ];

    const ihopCrew = [selfFriend._id, friends.omar, friends.sofia, friends.nina];
    const ihopItems: SeedItem[] = [
      { name: "Jalapeño Kick Burger", quantity: 2, unitPrice: 24.99, assignedToIds: [selfFriend._id, friends.omar] },
      { name: "Cali Melt", unitPrice: 25.99, assignedToIds: [friends.sofia] },
      { name: "Pancake Combo", unitPrice: 27.99, assignedToIds: [selfFriend._id] },
      { name: "Spinach Mushroom Omelette", unitPrice: 29.99, assignedToIds: [friends.nina] },
      { name: "Mexican Tres Leches", unitPrice: 21.99, assignedToIds: ihopCrew },
      { name: "Poblano Benedict", unitPrice: 28.99, assignedToIds: [friends.omar] },
      { name: "Vanilla Cold Brew", unitPrice: 6.99, assignedToIds: [selfFriend._id] },
      { name: "Hot Cocoa", unitPrice: 4.99, assignedToIds: [friends.sofia] },
      { name: "18% Gratuity", unitPrice: 35.44, assignedToIds: ihopCrew },
      { name: "HST", unitPrice: 32.77, assignedToIds: ihopCrew },
      { name: "Service Fee", unitPrice: 19.69, assignedToIds: ihopCrew },
    ];

    const mcdonaldsItems: SeedItem[] = [
      { name: "Big Mac", unitPrice: 7.49, assignedToIds: [friends.leo] },
      { name: "Salted Caramel Iced Coffee", unitPrice: 2.69, assignedToIds: [selfFriend._id] },
      { name: "HST", unitPrice: 1.32, assignedToIds: [selfFriend._id, friends.leo] },
    ];

    const transactions: SeedTransaction[] = [
      {
        title: "Sengyo Sushi",
        emoji: "🍣",
        description: "Receipt scan with item-by-item assignments",
        totalAmount: 146.90,
        currency: "CAD",
        splitMethod: "byItem",
        paidById: selfFriend._id,
        daysAgo: 1,
        receiptFileId: SEED_RECEIPT_FILE_IDS.sengyoSushi,
        items: sushiItems,
        splits: splitFromItems(sushiItems),
      },
      {
        title: "IHOP Brunch",
        emoji: "🥞",
        description: "Big brunch with shared fees and gratuity",
        totalAmount: 284.81,
        currency: "CAD",
        splitMethod: "byItem",
        paidById: friends.omar,
        daysAgo: 3,
        receiptFileId: SEED_RECEIPT_FILE_IDS.ihop,
        items: ihopItems,
        splits: splitFromItems(ihopItems),
      },
      {
        title: "Late Night McDonald’s",
        emoji: "🍔",
        description: "Tiny receipt, still itemized",
        totalAmount: 11.50,
        currency: "CAD",
        splitMethod: "byItem",
        paidById: friends.leo,
        daysAgo: 5,
        receiptFileId: SEED_RECEIPT_FILE_IDS.mcdonalds,
        items: mcdonaldsItems,
        splits: splitFromItems(mcdonaldsItems),
      },
      {
        title: "Cabin Groceries",
        emoji: "🛒",
        description: "Unequal split for a weekend away",
        totalAmount: 186.42,
        currency: "USD",
        splitMethod: "unequal",
        paidById: selfFriend._id,
        daysAgo: 7,
        splits: [
          { friendId: selfFriend._id, amount: 48.20 },
          { friendId: friends.maya, amount: 36.10 },
          { friendId: friends.leo, amount: 52.12 },
          { friendId: friends.priya, amount: 50.00 },
        ],
      },
      {
        title: "Movie Tickets",
        emoji: "🎬",
        description: "Simple equal split",
        totalAmount: 72.00,
        currency: "USD",
        splitMethod: "equal",
        paidById: friends.omar,
        daysAgo: 10,
        splits: [
          { friendId: selfFriend._id, amount: 24.00 },
          { friendId: friends.omar, amount: 24.00 },
          { friendId: friends.sofia, amount: 24.00 },
        ],
      },
      {
        title: "Rent Share",
        emoji: "🏠",
        description: "By-parts split for different room sizes",
        totalAmount: 1800.00,
        currency: "USD",
        splitMethod: "byParts",
        paidById: selfFriend._id,
        daysAgo: 14,
        splits: [
          { friendId: selfFriend._id, amount: 900.00, percentage: 50.00 },
          { friendId: friends.priya, amount: 600.00, percentage: 33.33 },
          { friendId: friends.maya, amount: 300.00, percentage: 16.67 },
        ],
      },
      {
        title: "Studio Coffee Run",
        emoji: "☕",
        description: "Settled example for the activity timeline",
        totalAmount: 28.50,
        currency: "USD",
        splitMethod: "equal",
        paidById: friends.sofia,
        daysAgo: 18,
        splits: [
          { friendId: selfFriend._id, amount: 9.50 },
          { friendId: friends.sofia, amount: 9.50 },
          { friendId: friends.nina, amount: 9.50 },
        ],
      },
    ];

    const transactionIds: Record<string, Id<"transactions">> = {};
    for (const transaction of transactions) {
      transactionIds[transaction.title] = await insertTransaction(transaction);
    }

    const mayaSettlementId = await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: friends.maya,
      amount: 150.00,
      currency: "USD",
      direction: "from_friend",
      note: "Partial rent + groceries payback",
      balanceBeforeSettlement: 336.10,
      exchangeRates: SEED_EXCHANGE_RATES,
      settledAt: now - 4 * day,
      createdAt: now - 4 * day,
    });

    const omarSettlementId = await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: friends.omar,
      amount: 10.00,
      currency: "USD",
      direction: "to_friend",
      note: "Partial movie payback",
      balanceBeforeSettlement: 24.00,
      exchangeRates: SEED_EXCHANGE_RATES,
      settledAt: now - 8 * day,
      createdAt: now - 8 * day,
    });

    const sofiaSettlementId = await ctx.db.insert("settlements", {
      createdById: currentUser._id,
      friendId: friends.sofia,
      amount: 9.50,
      currency: "USD",
      direction: "to_friend",
      note: "Coffee settled",
      balanceBeforeSettlement: 9.50,
      exchangeRates: SEED_EXCHANGE_RATES,
      settledAt: now - 16 * day,
      createdAt: now - 16 * day,
    });

    await insertSeedActivity({
      actorName: "Maya Patel",
      type: "settlement_recorded",
      message: "Maya paid you $150.00 toward Rent Share and Cabin Groceries",
      friendId: friends.maya,
      settlementId: mayaSettlementId,
      daysAgo: 0.25,
    });

    await insertSeedActivity({
      actorName: currentUser.name,
      type: "split_created",
      message: `${currentUser.name} created "Sengyo Sushi"`,
      transactionId: transactionIds["Sengyo Sushi"],
      daysAgo: 1,
      isRead: true,
    });

    await insertSeedActivity({
      actorName: "Omar Johnson",
      type: "split_created",
      message: "Omar added you to \"IHOP Brunch\"",
      transactionId: transactionIds["IHOP Brunch"],
      friendId: friends.omar,
      daysAgo: 3,
    });

    await insertSeedActivity({
      actorName: "Leo Chen",
      type: "split_created",
      message: "Leo added you to \"Late Night McDonald’s\"",
      transactionId: transactionIds["Late Night McDonald’s"],
      friendId: friends.leo,
      daysAgo: 5,
      isRead: true,
    });

    await insertSeedActivity({
      actorName: currentUser.name,
      type: "split_edited",
      message: `${currentUser.name} updated item assignments for "Cabin Groceries"`,
      transactionId: transactionIds["Cabin Groceries"],
      daysAgo: 6,
    });

    await insertSeedActivity({
      actorName: currentUser.name,
      type: "settlement_recorded",
      message: `${currentUser.name} paid Omar $10.00 for Movie Tickets`,
      friendId: friends.omar,
      settlementId: omarSettlementId,
      daysAgo: 8,
      isRead: true,
    });

    await insertSeedActivity({
      actorName: "Priya Shah",
      type: "invitation_accepted",
      message: "Priya accepted your friend invite",
      friendId: friends.priya,
      daysAgo: 12,
      isRead: true,
    });

    await insertSeedActivity({
      actorName: currentUser.name,
      type: "split_created",
      message: `${currentUser.name} created "Rent Share"`,
      transactionId: transactionIds["Rent Share"],
      daysAgo: 14,
      isRead: true,
    });

    await insertSeedActivity({
      actorName: currentUser.name,
      type: "settlement_recorded",
      message: `${currentUser.name} settled Studio Coffee Run with Sofia`,
      friendId: friends.sofia,
      settlementId: sofiaSettlementId,
      daysAgo: 16,
      isRead: true,
    });

    return {
      message: "Fresh sample data created for your account!",
      created: {
        friends: friendSpecs.length,
        transactions: transactions.length,
        receiptBackedTransactions: 3,
        splits: transactions.reduce((total, transaction) => total + transaction.splits.length, 0),
        settlements: 3,
        activities: 9,
      },
      summary: {
        avatars: "Emoji + color sample friends for the updated avatar UI",
        receipts: "Sengyo Sushi, IHOP Brunch, and Late Night McDonald’s use uploaded receipt images with by-item splits",
        splitMethods: "Includes byItem, equal, unequal, and byParts transactions",
        settlementStates: "Includes pending balances, partial settlement, and fully settled coffee history",
        activityFeed: "Includes split, settlement, edit, and invitation activity rows with read/unread states",
      },
    };
  },
});

/**
 * Seed the database with sample data for development/testing.
 * Run with: npx convex run seed:seedDatabase
 */
export const seedDatabase = internalMutation({
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
      inviteStatus: "none",
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
      inviteStatus: "accepted",
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
      inviteStatus: "accepted",
      createdAt: now,
    });

    // Alice's dummy friend: Diana (not a real user)
    const aliceFriendDianaId = await ctx.db.insert("friends", {
      ownerId: user1Id,
      name: "Diana Ross",
      email: "diana@example.com",
      isDummy: true,
      isSelf: false,
      inviteStatus: "invite_sent",
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
      inviteStatus: "none",
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
      inviteStatus: "accepted",
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
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendBobId,
      amount: perPersonDinner,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction1Id,
      friendId: aliceFriendCharlieId,
      amount: perPersonDinner,
      createdAt: now - 2 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 2 (Groceries - By Item)
    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceSelfId,
      amount: 22.625, // Half of milk+eggs (7.625) + third of household (15)
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendBobId,
      amount: 48.125, // Half of milk+eggs (7.625) + snacks (25.50) + third of household (15)
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction2Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00, // Third of household items
      createdAt: now - 5 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 3 (Movie - Unequal, all settled)
    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceSelfId,
      amount: 15.00,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendBobId,
      amount: 15.00,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction3Id,
      friendId: aliceFriendCharlieId,
      amount: 15.00,
      createdAt: now - 10 * 24 * 60 * 60 * 1000,
    });

    // Splits for Transaction 4 (Rent - By Parts: Alice 2 parts, Bob 1 part, Diana 1 part)
    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceSelfId,
      amount: 1200.00, // 2/4 parts
      percentage: 50,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceFriendBobId,
      amount: 600.00, // 1/4 parts
      percentage: 25,
      createdAt: now - 1 * 24 * 60 * 60 * 1000,
    });

    await ctx.db.insert("splits", {
      transactionId: transaction4Id,
      friendId: aliceFriendDianaId,
      amount: 600.00, // 1/4 parts
      percentage: 25,
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

const RESET_USER_LINKED_DATA_CONFIRMATION = "DELETE_USER_LINKED_DATA";

async function collectResetCounts(ctx: any) {
  const [
    users,
    notificationDevices,
    friends,
    exchangeRates,
    transactions,
    splits,
    settlements,
    invitations,
    activities,
    transactionParticipants,
  ] = await Promise.all([
    ctx.db.query("users").collect(),
    ctx.db.query("notificationDevices").collect(),
    ctx.db.query("friends").collect(),
    ctx.db.query("exchangeRates").collect(),
    ctx.db.query("transactions").collect(),
    ctx.db.query("splits").collect(),
    ctx.db.query("settlements").collect(),
    ctx.db.query("invitations").collect(),
    ctx.db.query("activities").collect(),
    ctx.db.query("transactionParticipants").collect(),
  ]);

  return {
    users: users.length,
    notificationDevices: notificationDevices.length,
    friends: friends.length,
    exchangeRates: exchangeRates.length,
    transactions: transactions.length,
    splits: splits.length,
    settlements: settlements.length,
    invitations: invitations.length,
    activities: activities.length,
    transactionParticipants: transactionParticipants.length,
    receiptFiles: transactions.filter((transaction: Doc<"transactions">) => transaction.receiptFileId).length,
  };
}

async function clearUserLinkedTables(ctx: any) {
  const notificationDevices = await ctx.db.query("notificationDevices").collect();
  for (const device of notificationDevices) {
    await ctx.db.delete(device._id);
  }

  const activities = await ctx.db.query("activities").collect();
  for (const activity of activities) {
    await ctx.db.delete(activity._id);
  }

  const transactionParticipants = await ctx.db.query("transactionParticipants").collect();
  for (const participant of transactionParticipants) {
    await ctx.db.delete(participant._id);
  }

  const invitations = await ctx.db.query("invitations").collect();
  for (const invitation of invitations) {
    await ctx.db.delete(invitation._id);
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
  let receiptFilesDeleted = 0;
  for (const transaction of transactions) {
    if (transaction.receiptFileId) {
      try {
        if (!isSeedReceiptFileId(transaction.receiptFileId)) {
          await ctx.storage.delete(transaction.receiptFileId);
          receiptFilesDeleted++;
        }
      } catch {
        // Ignore missing storage blobs so document cleanup can still complete.
      }
    }
    await ctx.db.delete(transaction._id);
  }

  const friends = await ctx.db.query("friends").collect();
  for (const friend of friends) {
    await ctx.db.delete(friend._id);
  }

  const exchangeRates = await ctx.db.query("exchangeRates").collect();
  for (const rate of exchangeRates) {
    await ctx.db.delete(rate._id);
  }

  return {
    notificationDevices: notificationDevices.length,
    activities: activities.length,
    transactionParticipants: transactionParticipants.length,
    invitations: invitations.length,
    settlements: settlements.length,
    splits: splits.length,
    transactions: transactions.length,
    friends: friends.length,
    exchangeRates: exchangeRates.length,
    receiptFiles: receiptFilesDeleted,
  };
}

/**
 * Inspect the current reset state for dev troubleshooting.
 * Run with: npx convex run seed:getResettableDataCounts
 */
export const getResettableDataCounts = internalQuery({
  args: {},
  handler: async (ctx) => {
    const counts = await collectResetCounts(ctx);
    const userLinkedTables = [
      "notificationDevices",
      "friends",
      "exchangeRates",
      "transactions",
      "splits",
      "settlements",
      "invitations",
      "activities",
      "transactionParticipants",
      "receiptFiles",
    ] as const;

    const userLinkedRowsRemaining = userLinkedTables.reduce(
      (total, tableName) => total + counts[tableName],
      0
    );

    return {
      counts,
      usersPreserved: counts.users,
      userLinkedRowsRemaining,
      isClean: userLinkedRowsRemaining === 0,
    };
  },
});

/**
 * Clear all user-linked data while preserving Clerk-backed Convex users.
 * Run with: npx convex run seed:clearUserLinkedData '{"confirmText":"DELETE_USER_LINKED_DATA"}'
 */
export const clearUserLinkedData = internalMutation({
  args: {
    confirmText: v.string(),
  },
  handler: async (ctx, { confirmText }) => {
    if (confirmText !== RESET_USER_LINKED_DATA_CONFIRMATION) {
      throw new Error(
        `Reset cancelled. Pass confirmText: "${RESET_USER_LINKED_DATA_CONFIRMATION}" to proceed.`
      );
    }

    const before = await collectResetCounts(ctx);
    const deleted = await clearUserLinkedTables(ctx);
    const after = await collectResetCounts(ctx);

    return {
      message: "User-linked data cleared successfully. Convex users were preserved.",
      deleted,
      before,
      after,
      usersPreserved: after.users,
      isClean:
        after.notificationDevices === 0 &&
        after.friends === 0 &&
        after.exchangeRates === 0 &&
        after.transactions === 0 &&
        after.splits === 0 &&
        after.settlements === 0 &&
        after.invitations === 0 &&
        after.activities === 0 &&
        after.transactionParticipants === 0 &&
        after.receiptFiles === 0,
    };
  },
});

/**
 * Clear all data from the database.
 * Run with: npx convex run seed:clearDatabase
 * WARNING: This will delete ALL data!
 */
export const clearDatabase = internalMutation({
  args: {
    confirmDelete: v.boolean(),
  },
  handler: async (ctx, { confirmDelete }) => {
    if (!confirmDelete) {
      return { message: "Deletion cancelled. Pass confirmDelete: true to proceed." };
    }

    const deleted = await clearUserLinkedTables(ctx);

    const users = await ctx.db.query("users").collect();
    for (const user of users) {
      await ctx.db.delete(user._id);
    }

    return {
      message: "Database cleared successfully!",
      deleted: {
        users: users.length,
        ...deleted,
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
    await requireIdentity(ctx, clerkId);
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
      if (tx.receiptFileId && !isSeedReceiptFileId(tx.receiptFileId)) {
        try {
          await ctx.storage.delete(tx.receiptFileId);
        } catch {
          // Ignore missing storage blobs so document cleanup can still complete.
        }
      }
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

