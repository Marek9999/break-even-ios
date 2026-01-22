//
//  ConvexModels.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation

// MARK: - User

/// User model from Convex
struct ConvexUser: Codable, Identifiable, Hashable {
    let _id: String
    let clerkId: String
    let email: String
    let name: String
    let phone: String?
    let avatarUrl: String?
    private let _defaultCurrency: String?
    let createdAt: Double
    
    var id: String { _id }
    
    /// User's default currency (defaults to USD if not set)
    var defaultCurrency: String {
        _defaultCurrency ?? "USD"
    }
    
    enum CodingKeys: String, CodingKey {
        case _id
        case clerkId
        case email
        case name
        case phone
        case avatarUrl
        case _defaultCurrency = "defaultCurrency"
        case createdAt
    }
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let firstName = components.first, firstName.count >= 2 {
            return String(firstName.prefix(2)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
}

// MARK: - Friend

/// Friend model from Convex
struct ConvexFriend: Codable, Identifiable, Hashable {
    let _id: String
    let ownerId: String
    let linkedUserId: String?
    let name: String
    let email: String?
    let phone: String?
    let avatarUrl: String?
    let isDummy: Bool
    let isSelf: Bool
    let createdAt: Double
    
    var id: String { _id }
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let firstName = components.first, firstName.count >= 2 {
            return String(firstName.prefix(2)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    var displayName: String {
        isSelf ? "Me" : name
    }
}

// MARK: - Friend with Balance

/// Response from getFriendsWithBalances query
struct FriendsWithBalancesResponse: Codable {
    let balances: [FriendWithBalance]
    let userCurrency: String
}

/// Balance breakdown by original currency
struct CurrencyBalance: Codable, Hashable {
    let friendOwes: Double
    let userOwes: Double
}

/// Friend with calculated balance (amounts converted to user's default currency)
struct FriendWithBalance: Codable, Identifiable, Hashable {
    let friend: ConvexFriend
    let friendOwesUser: Double      // Converted to user's default currency
    let userOwesFriend: Double      // Converted to user's default currency
    let netBalance: Double          // Converted to user's default currency
    let isOwedToUser: Bool
    let balancesByCurrency: [String: CurrencyBalance]?  // Original amounts by currency
    
    var id: String { friend.id }
    
    var displayAmount: Double {
        abs(netBalance)
    }
}

// MARK: - Transaction

/// Transaction model from Convex
struct ConvexTransaction: Codable, Identifiable, Hashable {
    let _id: String
    let createdById: String
    let paidById: String
    let title: String
    let emoji: String
    let description: String?
    let totalAmount: Double
    let currency: String
    let splitMethod: String
    let receiptFileId: String?
    let items: [ConvexTransactionItem]?
    let exchangeRates: ExchangeRates?  // Exchange rates snapshot at creation time
    let date: Double
    let createdAt: Double
    
    var id: String { _id }
    
    var dateValue: Date {
        Date(timeIntervalSince1970: date / 1000)
    }
    
    var createdAtDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
    
    /// Format amount with the transaction's currency
    var formattedAmount: String {
        totalAmount.asCurrency(code: currency)
    }
    
    /// Convert amount to a different currency using stored exchange rates
    func convertedAmount(to targetCurrency: String) -> Double {
        guard let rates = exchangeRates else {
            return totalAmount
        }
        return rates.convert(amount: totalAmount, from: currency, to: targetCurrency)
    }
    
    /// Format amount converted to a different currency
    func formattedAmount(in targetCurrency: String) -> String {
        convertedAmount(to: targetCurrency).asCurrency(code: targetCurrency)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(_id)
    }
    
    static func == (lhs: ConvexTransaction, rhs: ConvexTransaction) -> Bool {
        lhs._id == rhs._id
    }
}

/// Transaction item for by-item splits
struct ConvexTransactionItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let quantity: Int
    let unitPrice: Double
    let assignedToIds: [String]
    
    var totalPrice: Double {
        Double(quantity) * unitPrice
    }
}

// MARK: - Enriched Transaction (with payer and splits info)

/// Transaction with all related data
struct EnrichedTransaction: Codable, Identifiable {
    let _id: String
    let createdById: String
    let paidById: String
    let title: String
    let emoji: String
    let description: String?
    let totalAmount: Double
    let currency: String
    let splitMethod: String
    let receiptFileId: String?
    let items: [ConvexTransactionItem]?
    let exchangeRates: ExchangeRates?  // Exchange rates snapshot at creation time
    let date: Double
    let createdAt: Double
    let payer: ConvexFriend?
    let splits: [EnrichedSplit]
    let receiptUrl: String?
    
    var id: String { _id }
    
    var dateValue: Date {
        Date(timeIntervalSince1970: date / 1000)
    }
    
    /// Format amount with the transaction's currency
    var formattedAmount: String {
        totalAmount.asCurrency(code: currency)
    }
    
    /// Convert amount to a different currency using stored exchange rates
    func convertedAmount(to targetCurrency: String) -> Double {
        guard let rates = exchangeRates else {
            return totalAmount
        }
        return rates.convert(amount: totalAmount, from: currency, to: targetCurrency)
    }
    
    /// Format amount converted to a different currency
    func formattedAmount(in targetCurrency: String) -> String {
        convertedAmount(to: targetCurrency).asCurrency(code: targetCurrency)
    }
    
    var payerName: String {
        payer?.displayName ?? "Unknown"
    }
}

// MARK: - Split

/// Individual split model from Convex
struct ConvexSplit: Codable, Identifiable, Hashable {
    let _id: String
    let transactionId: String
    let friendId: String
    let amount: Double
    let percentage: Double?
    let createdAt: Double
    
    var id: String { _id }
    
    var formattedAmount: String {
        amount.asCurrency
    }
}

/// Split with friend info
struct EnrichedSplit: Codable, Identifiable, Hashable {
    let _id: String
    let transactionId: String
    let friendId: String
    let amount: Double
    let percentage: Double?
    let createdAt: Double
    let friend: ConvexFriend?
    
    var id: String { _id }
    
    var formattedAmount: String {
        amount.asCurrency
    }
    
    var personName: String {
        friend?.displayName ?? "Unknown"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(_id)
    }
    
    static func == (lhs: EnrichedSplit, rhs: EnrichedSplit) -> Bool {
        lhs._id == rhs._id
    }
}

// MARK: - Invitation

/// Invitation model from Convex
struct ConvexInvitation: Codable, Identifiable {
    let _id: String
    let senderId: String
    let friendId: String
    let recipientEmail: String?
    let recipientPhone: String?
    let status: String
    let token: String
    let expiresAt: Double
    let createdAt: Double
    
    var id: String { _id }
    
    var expiresAtDate: Date {
        Date(timeIntervalSince1970: expiresAt / 1000)
    }
    
    var isExpired: Bool {
        expiresAtDate < Date()
    }
    
    var isPending: Bool {
        status == "pending" && !isExpired
    }
}

/// Invitation with related data
struct EnrichedInvitation: Codable, Identifiable {
    let _id: String
    let senderId: String
    let friendId: String
    let recipientEmail: String?
    let recipientPhone: String?
    let status: String
    let token: String
    let expiresAt: Double
    let createdAt: Double
    let friend: ConvexFriend?
    let isExpired: Bool
    
    var id: String { _id }
    
    var expiresAtDate: Date {
        Date(timeIntervalSince1970: expiresAt / 1000)
    }
    
    var isPending: Bool {
        status == "pending" && !isExpired
    }
}

// MARK: - Balance

/// Balance summary between user and friend (with currency conversion)
struct BalanceSummary: Codable {
    let friendOwesUser: Double       // Converted to user's default currency
    let userOwesFriend: Double       // Converted to user's default currency
    let netBalance: Double           // Converted to user's default currency
    let userCurrency: String         // User's default currency
    let balancesByCurrency: [String: CurrencyBalance]?  // Original amounts by currency
    
    var isOwedToUser: Bool {
        netBalance > 0
    }
    
    var displayAmount: Double {
        abs(netBalance)
    }
    
    /// Format the net balance with the user's currency
    var formattedBalance: String {
        displayAmount.asCurrency(code: userCurrency)
    }
}

// MARK: - Split Method

enum ConvexSplitMethod: String, Codable, CaseIterable {
    case equal = "equal"
    case unequal = "unequal"
    case byParts = "byParts"
    case byItem = "byItem"
    
    var displayName: String {
        switch self {
        case .equal: return "Split Equally"
        case .unequal: return "By Amount"
        case .byParts: return "By Shares"
        case .byItem: return "By Item"
        }
    }
}

// MARK: - Settlement

/// Settlement record for history display
struct Settlement: Codable, Identifiable {
    let _id: String
    let createdById: String
    let friendId: String
    let amount: Double
    let currency: String
    let direction: String  // "to_friend" (user pays) or "from_friend" (friend pays user)
    let note: String?
    let exchangeRates: ExchangeRates?
    let settledAt: Double
    let createdAt: Double
    
    var id: String { _id }
    
    var settledAtDate: Date {
        Date(timeIntervalSince1970: settledAt / 1000)
    }
    
    var createdAtDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
    
    /// Whether user paid friend (vs friend paid user)
    var isUserPaying: Bool {
        direction == "to_friend"
    }
    
    /// Formatted amount with currency
    var formattedAmount: String {
        amount.asCurrency(code: currency)
    }
}

/// Response from settleAmount mutation
struct SettleAmountResponse: Codable {
    let settlementId: String
    let settledAmount: Double
}

// MARK: - Enriched Settlement (with converted amounts)

/// Settlement with converted amount for display in user's currency
struct EnrichedSettlement: Codable, Identifiable {
    let _id: String
    let createdById: String
    let friendId: String
    let amount: Double
    let currency: String
    let direction: String
    let note: String?
    let balanceBeforeSettlement: Double?  // Total owed before this settlement (for "X out of Y" display)
    let exchangeRates: ExchangeRates?
    let settledAt: Double
    let createdAt: Double
    let convertedAmount: Double  // Amount in user's currency
    let convertedCurrency: String  // User's currency code
    let convertedBalanceBefore: Double?  // balanceBeforeSettlement in user's currency
    
    var id: String { _id }
    
    var settledAtDate: Date {
        Date(timeIntervalSince1970: settledAt / 1000)
    }
    
    /// Whether user paid friend (vs friend paid user)
    var isUserPaying: Bool {
        direction == "to_friend"
    }
    
    /// Formatted amount in user's currency
    var formattedConvertedAmount: String {
        convertedAmount.asCurrency(code: convertedCurrency)
    }
    
    /// Formatted "out of" amount in user's currency (if available)
    var formattedConvertedBalanceBefore: String? {
        guard let balance = convertedBalanceBefore else { return nil }
        return balance.asCurrency(code: convertedCurrency)
    }
    
    /// Formatted original amount
    var formattedAmount: String {
        amount.asCurrency(code: currency)
    }
}

// MARK: - Activity with Friend Response

/// Response from getActivityWithFriend query
struct ActivityWithFriendResponse: Codable {
    let transactions: [EnrichedTransaction]
    let settlements: [EnrichedSettlement]
    let userCurrency: String
}

// MARK: - Activity Item (for combined feed)

/// Unified activity item for displaying transactions and settlements in a combined list
enum ActivityItem: Identifiable {
    case transaction(EnrichedTransaction, originalAmount: Double, originalCurrency: String, isOwed: Bool)
    case settlement(EnrichedSettlement)
    
    var id: String {
        switch self {
        case .transaction(let tx, _, _, _):
            return "tx-\(tx.id)"
        case .settlement(let s):
            return "settle-\(s.id)"
        }
    }
    
    var date: Date {
        switch self {
        case .transaction(let tx, _, _, _):
            return tx.dateValue
        case .settlement(let s):
            return s.settledAtDate
        }
    }
    
    /// Sort key (timestamp in milliseconds)
    var sortTimestamp: Double {
        switch self {
        case .transaction(let tx, _, _, _):
            return tx.date
        case .settlement(let s):
            return s.settledAt
        }
    }
}
