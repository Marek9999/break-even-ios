//
//  PreviewData.swift
//  break-even-ios
//
//  Sample data for SwiftUI Previews.
//

#if DEBUG
import Foundation

// MARK: - ConvexFriend Samples

extension ConvexFriend {
    static let previewSelf = ConvexFriend(
        _id: "friend-self",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Me",
        email: "me@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: true,
        inviteStatus: "none",
        createdAt: Date().timeIntervalSince1970 * 1000
    )

    static let previewAlice = ConvexFriend(
        _id: "friend-alice",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Alice Johnson",
        email: "alice@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        inviteStatus: "accepted",
        createdAt: Date().timeIntervalSince1970 * 1000
    )

    static let previewBob = ConvexFriend(
        _id: "friend-bob",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Bob Smith",
        email: "bob@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        inviteStatus: "accepted",
        createdAt: Date().timeIntervalSince1970 * 1000
    )

    static let previewCarla = ConvexFriend(
        _id: "friend-carla",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Carla Reyes",
        email: nil,
        phone: "+14155551234",
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        inviteStatus: "accepted",
        createdAt: Date().timeIntervalSince1970 * 1000
    )

    static let previewDave = ConvexFriend(
        _id: "friend-dave",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Dave Park",
        email: "dave@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        inviteStatus: "accepted",
        createdAt: Date().timeIntervalSince1970 * 1000
    )

    static let previewElla = ConvexFriend(
        _id: "friend-ella",
        ownerId: "user1",
        linkedUserId: nil,
        name: "Ella Chen",
        email: "ella@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        inviteStatus: "accepted",
        createdAt: Date().timeIntervalSince1970 * 1000
    )
}

// MARK: - EnrichedSplit Samples

extension EnrichedSplit {
    static func preview(
        id: String = UUID().uuidString,
        transactionId: String = "tx-1",
        friend: ConvexFriend = .previewAlice,
        amount: Double = 52.27
    ) -> EnrichedSplit {
        EnrichedSplit(
            _id: id,
            transactionId: transactionId,
            friendId: friend._id,
            amount: amount,
            percentage: nil,
            createdAt: Date().timeIntervalSince1970 * 1000,
            friend: friend
        )
    }
}

// MARK: - EnrichedTransaction Samples

extension EnrichedTransaction {
    private static func daysAgo(_ days: Int) -> Double {
        Date().addingTimeInterval(TimeInterval(-days * 86400)).timeIntervalSince1970 * 1000
    }

    static let previewDinner = EnrichedTransaction(
        _id: "tx-1",
        createdById: "user1",
        paidById: "friend-self",
        title: "Team Dinner",
        emoji: "🍕",
        description: "Friday night pizza",
        totalAmount: 156.80,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: nil,
        date: daysAgo(1),
        createdAt: daysAgo(1),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s1", transactionId: "tx-1", friend: .previewSelf, amount: 52.27),
            .preview(id: "s2", transactionId: "tx-1", friend: .previewAlice, amount: 52.27),
            .preview(id: "s3", transactionId: "tx-1", friend: .previewBob, amount: 52.26),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewGroceries = EnrichedTransaction(
        _id: "tx-2",
        createdById: "user1",
        paidById: "friend-alice",
        title: "Grocery Run",
        emoji: "🛒",
        description: nil,
        totalAmount: 89.45,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: nil,
        date: daysAgo(3),
        createdAt: daysAgo(3),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewAlice,
        splits: [
            .preview(id: "s4", transactionId: "tx-2", friend: .previewSelf, amount: 44.73),
            .preview(id: "s5", transactionId: "tx-2", friend: .previewAlice, amount: 44.72),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewCoffee = EnrichedTransaction(
        _id: "tx-3",
        createdById: "user1",
        paidById: "friend-self",
        title: "Coffee & Pastries",
        emoji: "☕️",
        description: nil,
        totalAmount: 24.50,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: nil,
        date: daysAgo(5),
        createdAt: daysAgo(5),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s6", transactionId: "tx-3", friend: .previewSelf, amount: 12.25),
            .preview(id: "s7", transactionId: "tx-3", friend: .previewCarla, amount: 12.25),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewRoadTrip = EnrichedTransaction(
        _id: "tx-4",
        createdById: "user1",
        paidById: "friend-bob",
        title: "Road Trip Gas",
        emoji: "⛽️",
        description: "Highway refuel",
        totalAmount: 72.00,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: nil,
        date: daysAgo(7),
        createdAt: daysAgo(7),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewBob,
        splits: [
            .preview(id: "s8", transactionId: "tx-4", friend: .previewSelf, amount: 24.00),
            .preview(id: "s9", transactionId: "tx-4", friend: .previewBob, amount: 24.00),
            .preview(id: "s10", transactionId: "tx-4", friend: .previewAlice, amount: 24.00),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewConcert = EnrichedTransaction(
        _id: "tx-5",
        createdById: "user1",
        paidById: "friend-self",
        title: "Concert Tickets",
        emoji: "🎵",
        description: nil,
        totalAmount: 320.00,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: nil,
        date: daysAgo(14),
        createdAt: daysAgo(14),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s11", transactionId: "tx-5", friend: .previewSelf, amount: 160.00),
            .preview(id: "s12", transactionId: "tx-5", friend: .previewCarla, amount: 160.00),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewEuroTrip = EnrichedTransaction(
        _id: "tx-6",
        createdById: "user1",
        paidById: "friend-self",
        title: "Paris Lunch",
        emoji: "🥐",
        description: "Bistro near the Louvre",
        totalAmount: 68.00,
        currency: "EUR",
        splitMethod: "equal",
        receiptFileId: nil,
        items: nil,
        exchangeRates: ExchangeRates(
            baseCurrency: "USD",
            rates: .fallback,
            fetchedAt: daysAgo(10)
        ),
        date: daysAgo(10),
        createdAt: daysAgo(10),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s13", transactionId: "tx-6", friend: .previewSelf, amount: 34.00),
            .preview(id: "s14", transactionId: "tx-6", friend: .previewAlice, amount: 34.00),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    /// 5 participants, receipt photo, and itemized list
    static let previewFullReceipt = EnrichedTransaction(
        _id: "tx-7",
        createdById: "user1",
        paidById: "friend-self",
        title: "Uniqlo",
        emoji: "🛍️",
        description: "Shopping trip",
        totalAmount: 123.56,
        currency: "CAD",
        splitMethod: "byItem",
        receiptFileId: "storage-fake-1",
        items: [
            ConvexTransactionItem(id: "item-1", name: "Graphic Tee", quantity: 1, unitPrice: 29.99, assignedToIds: ["friend-self", "friend-alice", "friend-bob", "friend-carla", "friend-dave"]),
            ConvexTransactionItem(id: "item-2", name: "Slim Fit Jeans", quantity: 1, unitPrice: 49.99, assignedToIds: ["friend-alice", "friend-bob"]),
            ConvexTransactionItem(id: "item-3", name: "Socks Pack", quantity: 1, unitPrice: 12.99, assignedToIds: []),
            ConvexTransactionItem(id: "item-4", name: "Hoodie", quantity: 1, unitPrice: 30.59, assignedToIds: ["friend-self", "friend-ella", "friend-carla"]),
        ],
        exchangeRates: nil,
        date: daysAgo(2),
        createdAt: daysAgo(2),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s15", transactionId: "tx-7", friend: .previewSelf, amount: 24.71),
            .preview(id: "s16", transactionId: "tx-7", friend: .previewAlice, amount: 30.99),
            .preview(id: "s17", transactionId: "tx-7", friend: .previewBob, amount: 30.99),
            .preview(id: "s18", transactionId: "tx-7", friend: .previewCarla, amount: 16.19),
            .preview(id: "s19", transactionId: "tx-7", friend: .previewDave, amount: 6.00),
        ],
        receiptUrl: "https://picsum.photos/400/600",
        lastEditedByName: nil
    )

    /// Receipt photo only, no itemized list
    static let previewReceiptOnly = EnrichedTransaction(
        _id: "tx-8",
        createdById: "user1",
        paidById: "friend-alice",
        title: "Thai Dinner",
        emoji: "🍜",
        description: nil,
        totalAmount: 85.40,
        currency: "USD",
        splitMethod: "equal",
        receiptFileId: "storage-fake-2",
        items: nil,
        exchangeRates: nil,
        date: daysAgo(4),
        createdAt: daysAgo(4),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewAlice,
        splits: [
            .preview(id: "s20", transactionId: "tx-8", friend: .previewSelf, amount: 28.47),
            .preview(id: "s21", transactionId: "tx-8", friend: .previewAlice, amount: 28.47),
            .preview(id: "s22", transactionId: "tx-8", friend: .previewBob, amount: 28.46),
        ],
        receiptUrl: "https://picsum.photos/400/600",
        lastEditedByName: nil
    )

    /// Itemized list only, no receipt photo
    static let previewItemsOnly = EnrichedTransaction(
        _id: "tx-9",
        createdById: "user1",
        paidById: "friend-self",
        title: "Costco Run",
        emoji: "🛒",
        description: nil,
        totalAmount: 142.75,
        currency: "USD",
        splitMethod: "byItem",
        receiptFileId: nil,
        items: [
            ConvexTransactionItem(id: "item-5", name: "Paper Towels", quantity: 2, unitPrice: 18.99, assignedToIds: ["friend-self", "friend-bob"]),
            ConvexTransactionItem(id: "item-6", name: "Olive Oil", quantity: 1, unitPrice: 14.99, assignedToIds: ["friend-self"]),
            ConvexTransactionItem(id: "item-7", name: "Frozen Pizza", quantity: 3, unitPrice: 12.49, assignedToIds: ["friend-self", "friend-alice", "friend-bob"]),
            ConvexTransactionItem(id: "item-8", name: "Laundry Pods", quantity: 1, unitPrice: 24.99, assignedToIds: []),
        ],
        exchangeRates: nil,
        date: daysAgo(6),
        createdAt: daysAgo(6),
        lastEditedBy: nil,
        lastEditedAt: nil,
        payer: .previewSelf,
        splits: [
            .preview(id: "s23", transactionId: "tx-9", friend: .previewSelf, amount: 71.37),
            .preview(id: "s24", transactionId: "tx-9", friend: .previewAlice, amount: 12.49),
            .preview(id: "s25", transactionId: "tx-9", friend: .previewBob, amount: 58.89),
        ],
        receiptUrl: nil,
        lastEditedByName: nil
    )

    static let previewList: [EnrichedTransaction] = [
        previewDinner,
        previewGroceries,
        previewCoffee,
        previewRoadTrip,
        previewConcert,
        previewEuroTrip,
    ]
}
#endif
