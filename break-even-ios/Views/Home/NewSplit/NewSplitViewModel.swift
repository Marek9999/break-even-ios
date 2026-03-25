//
//  NewSplitViewModel.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import ConvexMobile
import Foundation
import Photos

// MARK: - Encodable Extension for JSON String Conversion

private extension Encodable {
    /// Convert an Encodable to a JSON string for Convex API calls
    func asJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert to JSON string"
            ))
        }
        return jsonString
    }
}

private extension Array where Element: Encodable {
    /// Convert an array of Encodable to a JSON string
    func asJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert array to JSON string"
            ))
        }
        return jsonString
    }
}

// MARK: - Transaction Creation Structs (for JSON encoding)

/// Item structure for Convex API
private struct ConvexItemPayload: Encodable {
    let id: String
    let name: String
    let quantity: Int
    let unitPrice: Double
    let assignedToIds: [String]
}

/// Split structure for Convex API
private struct ConvexSplitPayload: Encodable {
    let friendId: String
    let amount: Double
    let percentage: Double?
}

/// Split method options for dividing expenses
enum NewSplitMethod: String, CaseIterable, Identifiable {
    case equal = "EQUAL"
    case unequal = "UNEQUAL"
    case byParts = "BY PARTS"
    case byItem = "BY ITEM"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .equal: return "equal"
        case .unequal: return "dollarsign"
        case .byParts: return "chart.pie"
        case .byItem: return "list.bullet"
        }
    }
    
    var description: String {
        switch self {
        case .equal: return "Split evenly"
        case .unequal: return "Custom amounts"
        case .byParts: return "By shares"
        case .byItem: return "Assign items"
        }
    }
    
    /// Convert to Convex split method string
    var convexValue: String {
        switch self {
        case .equal: return "equal"
        case .unequal: return "unequal"
        case .byParts: return "byParts"
        case .byItem: return "byItem"
        }
    }
    
    /// Parse from Convex split method string
    static func from(convexValue: String) -> NewSplitMethod? {
        switch convexValue {
        case "equal": return .equal
        case "unequal": return .unequal
        case "byParts": return .byParts
        case "byItem": return .byItem
        default: return nil
        }
    }
}

/// Item for by-item split method
/// `amount` is the per-unit price; total = amount * quantity
struct SplitItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Int = 1
    var amount: Double
    var assignedTo: Set<String> = []
    
    var totalPrice: Double {
        amount * Double(quantity)
    }
    
    var formattedAmount: String {
        amount.asCurrency
    }
}

/// Observable view model for the New Split flow
@MainActor
@Observable
class NewSplitViewModel {
    // MARK: - Basic Info
    var emoji: String = ""
    var title: String = ""
    var date: Date = Date()
    var currency: String = "USD"
    
    // MARK: - People
    var paidBy: ConvexFriend?
    var participants: [ConvexFriend] = []
    
    // MARK: - Amount & Split
    var totalAmount: Double = 0
    var splitMethod: NewSplitMethod = .equal
    
    // MARK: - Method-specific data
    /// For unequal split: custom amounts per friend ID
    var customAmounts: [String: Double] = [:]
    
    /// For unequal split: tracks which participants have had a value manually entered
    var unequalEnteredIds: Set<String> = []
    
    /// For by-parts split: number of parts per friend ID
    var partsPerPerson: [String: Int] = [:]
    
    /// For by-item split: list of items
    var items: [SplitItem] = []
    
    // MARK: - Receipt data (from camera scan)
    var scannedReceiptImage: UIImage?
    var isProcessingReceipt: Bool = false
    var receiptFileId: String?
    
    // MARK: - Pre-selection (from PersonDetailSheet)
    var preSelectedFriend: ConvexFriend?
    
    // MARK: - Edit Mode
    var editingTransactionId: String?
    var creatorUserId: String?
    var isEditing: Bool { editingTransactionId != nil }
    
    // MARK: - State
    var isLoading = false
    var error: String?
    
    // MARK: - Computed Properties
    
    var isValid: Bool {
        guard !title.isEmpty,
              totalAmount > 0,
              paidBy != nil,
              !participants.isEmpty else { return false }
        
        if splitMethod == .unequal {
            return abs(unequalSplitDifference) < 0.01
        }
        
        return true
    }
    
    var totalParts: Int {
        participants.reduce(0) { total, friend in
            total + (partsPerPerson[friend.id] ?? 1)
        }
    }
    
    var itemsTotal: Double {
        items.reduce(0) { $0 + $1.totalPrice }
    }
    
    var itemsTotalMismatch: Bool {
        !items.isEmpty && abs(itemsTotal - totalAmount) > 0.01
    }
    
    // MARK: - Exchange Rates
    
    /// Cached exchange rates for conversion (fetched from Convex action)
    var exchangeRates: ExchangeRates?
    var isFetchingRates = false
    
    // MARK: - Initialization
    
    init(preSelectedFriend: ConvexFriend? = nil, defaultCurrency: String = "USD") {
        self.currency = defaultCurrency
        self.preSelectedFriend = preSelectedFriend
        if let friend = preSelectedFriend {
            self.participants = [friend]
        }
    }
    
    /// Initialize in edit mode from an existing transaction
    init(from transaction: EnrichedTransaction, allFriends: [ConvexFriend]) {
        self.editingTransactionId = transaction._id
        self.creatorUserId = transaction.createdById
        self.emoji = transaction.emoji
        self.title = transaction.title
        self.date = transaction.dateValue
        self.currency = transaction.currency
        self.totalAmount = transaction.totalAmount
        self.receiptFileId = transaction.receiptFileId
        self.exchangeRates = transaction.exchangeRates
        
        let method = NewSplitMethod.from(convexValue: transaction.splitMethod) ?? .equal
        self.splitMethod = method
        
        let selfFriend = allFriends.first(where: { $0.isSelf })
        
        // Remap each split's friend to the current user's equivalent friend record.
        // This prevents duplicates when the split was created by another user whose
        // friend records have different IDs than the current user's.
        var friendIdMapping: [String: String] = [:]
        
        let participantFriends: [ConvexFriend] = transaction.splits.compactMap { split in
            let resolved = Self.resolveToLocalFriend(
                splitFriend: split.friend,
                splitFriendId: split.friendId,
                allFriends: allFriends,
                selfFriend: selfFriend
            )
            if let resolved, resolved._id != split.friendId {
                friendIdMapping[split.friendId] = resolved._id
            }
            return resolved
        }
        
        // Deduplicate (in case two foreign records resolved to the same local friend)
        var seen = Set<String>()
        self.participants = participantFriends.filter { seen.insert($0.id).inserted }
        
        // Remap the payer to the current user's friend record
        if let payer = transaction.payer {
            self.paidBy = Self.resolveToLocalFriend(
                splitFriend: payer,
                splitFriendId: payer._id,
                allFriends: allFriends,
                selfFriend: selfFriend
            ) ?? payer
        } else {
            self.paidBy = transaction.payer
        }
        
        switch method {
        case .equal:
            break
        case .unequal:
            for split in transaction.splits {
                let mappedId = friendIdMapping[split.friendId] ?? split.friendId
                customAmounts[mappedId] = split.amount
                unequalEnteredIds.insert(mappedId)
            }
        case .byParts:
            for split in transaction.splits {
                let mappedId = friendIdMapping[split.friendId] ?? split.friendId
                if let pct = split.percentage, pct > 0 {
                    let parts = max(1, Int(round(pct / 10.0)))
                    partsPerPerson[mappedId] = parts
                } else {
                    partsPerPerson[mappedId] = 1
                }
            }
        case .byItem:
            if let txItems = transaction.items {
                self.items = txItems.map { item in
                    let remappedAssignees = Set(item.assignedToIds.map { friendIdMapping[$0] ?? $0 })
                    return SplitItem(
                        name: item.name,
                        quantity: item.quantity,
                        amount: item.unitPrice,
                        assignedTo: remappedAssignees
                    )
                }
            }
        }
    }
    
    /// Maps a foreign friend record to the current user's equivalent from allFriends.
    private static func resolveToLocalFriend(
        splitFriend: ConvexFriend?,
        splitFriendId: String,
        allFriends: [ConvexFriend],
        selfFriend: ConvexFriend?
    ) -> ConvexFriend? {
        // Direct match in allFriends
        if let match = allFriends.first(where: { $0._id == splitFriendId }) {
            return match
        }
        
        guard let splitFriend else { return nil }
        
        // Foreign friend pointing to the current user → use selfFriend
        if let selfF = selfFriend, splitFriend.linkedUserId == selfF.ownerId {
            return selfF
        }
        
        // Foreign self-friend (represents the creator) → find them in our friends by linkedUserId
        if splitFriend.isSelf,
           let match = allFriends.first(where: { $0.linkedUserId == splitFriend.ownerId }) {
            return match
        }
        
        // Match by linkedUserId
        if let linkedId = splitFriend.linkedUserId,
           let match = allFriends.first(where: { $0.linkedUserId == linkedId }) {
            return match
        }
        
        return splitFriend
    }
    
    // MARK: - Split Calculations
    
    func calculateShare(for friend: ConvexFriend) -> Double {
        guard participants.contains(where: { $0.id == friend.id }) else { return 0 }
        
        switch splitMethod {
        case .equal:
            return totalAmount / Double(max(participants.count, 1))
            
        case .unequal:
            return customAmounts[friend.id] ?? 0
            
        case .byParts:
            let personParts = partsPerPerson[friend.id] ?? 1
            let total = totalParts
            guard total > 0 else { return 0 }
            return totalAmount * (Double(personParts) / Double(total))
            
        case .byItem:
            var personTotal: Double = 0
            for item in items {
                if item.assignedTo.contains(friend.id) {
                    let splitCount = max(item.assignedTo.count, 1)
                    personTotal += item.totalPrice / Double(splitCount)
                }
            }
            return personTotal
        }
    }
    
    func formattedShare(for friend: ConvexFriend) -> String {
        calculateShare(for: friend).asCurrency(code: currency)
    }
    
    // MARK: - Participant Management
    
    func addParticipant(_ friend: ConvexFriend) {
        guard !participants.contains(where: { $0.id == friend.id }) else { return }
        participants.append(friend)
        
        // Initialize defaults for split methods
        partsPerPerson[friend.id] = 1
        customAmounts[friend.id] = 0
    }
    
    func removeParticipant(_ friend: ConvexFriend) {
        participants.removeAll { $0.id == friend.id }
        partsPerPerson.removeValue(forKey: friend.id)
        customAmounts.removeValue(forKey: friend.id)
        unequalEnteredIds.remove(friend.id)
        
        // Remove from item assignments
        for index in items.indices {
            items[index].assignedTo.remove(friend.id)
        }
    }
    
    func toggleParticipant(_ friend: ConvexFriend) {
        if participants.contains(where: { $0.id == friend.id }) {
            removeParticipant(friend)
        } else {
            addParticipant(friend)
        }
    }
    
    // MARK: - Item Management (for by-item split)
    
    func addItem(name: String, amount: Double, quantity: Int = 1) {
        let item = SplitItem(name: name, quantity: quantity, amount: amount)
        items.append(item)
    }
    
    func updateItem(id: UUID, name: String, quantity: Int, amount: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = name
        items[index].quantity = quantity
        items[index].amount = amount
    }
    
    func removeItem(_ item: SplitItem) {
        items.removeAll { $0.id == item.id }
    }
    
    func toggleItemAssignment(item: SplitItem, friend: ConvexFriend) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        if items[index].assignedTo.contains(friend.id) {
            items[index].assignedTo.remove(friend.id)
        } else {
            items[index].assignedTo.insert(friend.id)
        }
    }
    
    func assignAllToItem(item: SplitItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].assignedTo = Set(participants.map(\.id))
    }
    
    func unassignAllFromItem(item: SplitItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].assignedTo.removeAll()
    }
    
    // MARK: - Parts Management (for by-parts split)
    
    func incrementParts(for friend: ConvexFriend) {
        let current = partsPerPerson[friend.id] ?? 1
        partsPerPerson[friend.id] = current + 1
    }
    
    func decrementParts(for friend: ConvexFriend) {
        let current = partsPerPerson[friend.id] ?? 1
        if current > 1 {
            partsPerPerson[friend.id] = current - 1
        }
    }
    
    func getParts(for friend: ConvexFriend) -> Int {
        partsPerPerson[friend.id] ?? 1
    }
    
    // MARK: - Custom Amount Management (for unequal split)
    
    func setCustomAmount(_ amount: Double, for friend: ConvexFriend) {
        customAmounts[friend.id] = amount
    }
    
    func getCustomAmount(for friend: ConvexFriend) -> Double {
        customAmounts[friend.id] ?? 0
    }
    
    /// Sum of custom amounts only for current participants
    var assignedTotal: Double {
        participants.reduce(0) { $0 + (customAmounts[$1.id] ?? 0) }
    }
    
    /// Positive = remaining, negative = over budget
    var unequalSplitDifference: Double {
        totalAmount - assignedTotal
    }
    
    var remainingToAssign: Double {
        totalAmount - assignedTotal
    }
    
    func suggestedPlaceholder(for friend: ConvexFriend) -> String {
        guard !unequalEnteredIds.contains(friend.id) else { return "0.00" }
        let unfilledCount = participants.filter { !unequalEnteredIds.contains($0.id) }.count
        guard unfilledCount > 0 else { return "0.00" }
        let filledSum = participants
            .filter { unequalEnteredIds.contains($0.id) }
            .reduce(0.0) { $0 + (customAmounts[$1.id] ?? 0) }
        let remainder = totalAmount - filledSum
        guard remainder > 0 else { return "0.00" }
        let suggested = remainder / Double(unfilledCount)
        return String(format: "%.2f", suggested)
    }
    
    // MARK: - Receipt Processing
    
    func applyReceiptData(title: String, total: Double, items: [SplitItem]) {
        self.title = title
        self.totalAmount = total
        self.items = items
        
        // If items exist, default to by-item split
        if !items.isEmpty {
            self.splitMethod = .byItem
        }
    }
    
    /// Clear receipt data and associated items
    func clearReceipt() {
        scannedReceiptImage = nil
        receiptFileId = nil
        items = []
        
        if splitMethod == .byItem {
            splitMethod = .equal
        }
    }
    
    /// Clear only the receipt photo, keeping the item list intact
    func clearReceiptPhoto() {
        scannedReceiptImage = nil
        receiptFileId = nil
    }
    
    /// Replace existing receipt data with new scan result
    func replaceReceiptData(from result: ReceiptScanResult) {
        receiptFileId = nil
        
        title = result.title.isEmpty ? "Receipt" : result.title
        totalAmount = result.total
        emoji = result.emoji ?? "🧾"
        scannedReceiptImage = result.image
        items = result.items
        splitMethod = .byItem
        
        #if DEBUG
        print("=== Receipt Data Replaced: \(title), Items: \(items.count) ===")
        #endif
    }
    
    // MARK: - Save Receipt to Photo Library
    
    func saveReceiptToPhotoLibrary(image: UIImage) async throws {
        // Request authorization first
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        guard status == .authorized || status == .limited else {
            throw NewSplitError.photoLibraryAccessDenied
        }
        
        // Save to photo library
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NewSplitError.photoLibrarySaveFailed)
                }
            }
        }
    }
    
    // MARK: - Upload Receipt Image to Convex
    
    func uploadReceiptImage(image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NewSplitError.invalidData
        }
        
        let client = ConvexService.shared.client
        
        // Get upload URL from Convex
        let uploadUrl: String = try await client.mutation("files:generateUploadUrl", with: [String: String]())
        
        #if DEBUG
        print("=== Upload URL received ===")
        #endif
        
        // Upload the image
        guard let url = URL(string: uploadUrl) else {
            throw NewSplitError.uploadFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NewSplitError.uploadFailed
        }
        
        // Convex returns the storage ID in the response body as JSON: {"storageId": "..."}
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storageId = json["storageId"] as? String {
                return storageId
            }
        } catch {
            #if DEBUG
            print("=== Failed to parse upload response: \(error) ===")
            #endif
        }
        
        #if DEBUG
        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("=== Raw upload response: \(responseString) ===")
        #endif
        
        throw NewSplitError.uploadFailed
    }
    
    // MARK: - Fetch Exchange Rates
    
    /// Fetch exchange rates from Convex (calls API only if cache is stale)
    func fetchExchangeRates() async throws -> ExchangeRates {
        if let cached = exchangeRates {
            return cached
        }
        
        isFetchingRates = true
        defer { isFetchingRates = false }
        
        let client = ConvexService.shared.client
        
        // Call the Convex action to get (potentially cached) exchange rates
        let rates: ExchangeRates = try await client.action(
            "currency:getOrFetchExchangeRates",
            with: [String: String]()
        )
        
        self.exchangeRates = rates
        return rates
    }
    
    // MARK: - Save Transaction
    
    func save(clerkId: String) async throws -> String {
        guard isValid else {
            throw NewSplitError.invalidData
        }
        
        guard let paidBy = paidBy else {
            throw NewSplitError.invalidData
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Fetch exchange rates for currency conversion (uses cache if fresh)
        let rates: ExchangeRates?
        do {
            rates = try await fetchExchangeRates()
        } catch {
            #if DEBUG
            print("=== Warning: Could not fetch exchange rates: \(error) ===")
            #endif
            rates = nil
        }
        
        // Handle receipt image if we have one
        var finalReceiptFileId: String? = receiptFileId
        if let image = scannedReceiptImage, receiptFileId == nil {
            do {
                try await saveReceiptToPhotoLibrary(image: image)
            } catch {
                #if DEBUG
                print("=== Warning: Could not save to Photo Library: \(error) ===")
                #endif
            }
            finalReceiptFileId = try await uploadReceiptImage(image: image)
        }
        
        let args = try buildMutationArgs(
            clerkId: clerkId,
            paidBy: paidBy,
            finalReceiptFileId: finalReceiptFileId,
            rates: rates
        )
        
        let client = ConvexService.shared.client
        
        if let txId = editingTransactionId {
            var updateArgs = args
            updateArgs["transactionId"] = txId
            let updatedTransactionId: String = try await client.mutation(
                "transactions:updateTransactionFromJson",
                with: updateArgs
            )
            return updatedTransactionId
        } else {
            let createdTransactionId: String = try await client.mutation(
                "transactions:createTransactionFromJson",
                with: args
            )
            return createdTransactionId
        }
    }
    
    /// Build the shared mutation args dictionary for both create and update
    private func buildMutationArgs(
        clerkId: String,
        paidBy: ConvexFriend,
        finalReceiptFileId: String?,
        rates: ExchangeRates?
    ) throws -> [String: String] {
        var itemsJson: String? = nil
        if splitMethod == .byItem && !items.isEmpty {
            let convexItems = items.map { item in
                ConvexItemPayload(
                    id: item.id.uuidString,
                    name: item.name,
                    quantity: item.quantity,
                    unitPrice: item.amount,
                    assignedToIds: Array(item.assignedTo)
                )
            }
            itemsJson = try convexItems.asJSONString()
        }
        
        let splitPayloads: [ConvexSplitPayload] = participants.map { friend in
            let amount = calculateShare(for: friend)
            let percentage: Double? = splitMethod == .byParts
                ? Double(getParts(for: friend)) / Double(totalParts) * 100
                : nil
            
            return ConvexSplitPayload(
                friendId: friend.id,
                amount: amount,
                percentage: percentage
            )
        }
        let splitsJson = try splitPayloads.asJSONString()
        
        var args: [String: String] = [
            "clerkId": clerkId,
            "paidById": paidBy.id,
            "title": title,
            "emoji": emoji.isEmpty ? "📝" : emoji,
            "totalAmount": String(totalAmount),
            "currency": currency,
            "splitMethod": splitMethod.convexValue,
            "date": String(date.timeIntervalSince1970 * 1000),
            "splitsJson": splitsJson
        ]
        
        if let itemsJson = itemsJson {
            args["itemsJson"] = itemsJson
        }
        
        if let fileId = finalReceiptFileId {
            args["receiptFileId"] = fileId
        }
        
        if let rates = rates, let ratesJson = rates.toJSONString() {
            args["exchangeRatesJson"] = ratesJson
        }
        
        return args
    }
    
    // MARK: - Reset
    
    func reset() {
        emoji = ""
        title = ""
        date = Date()
        paidBy = nil
        participants = []
        totalAmount = 0
        splitMethod = .equal
        customAmounts = [:]
        unequalEnteredIds = []
        partsPerPerson = [:]
        items = []
        scannedReceiptImage = nil
        isProcessingReceipt = false
        receiptFileId = nil
        exchangeRates = nil
        isFetchingRates = false
        error = nil
        
        // Re-apply pre-selected friend if any
        if let friend = preSelectedFriend {
            participants = [friend]
        }
    }
}

// MARK: - Errors

enum NewSplitError: LocalizedError {
    case invalidData
    case saveFailed
    case uploadFailed
    case photoLibraryAccessDenied
    case photoLibrarySaveFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Please fill in all required fields"
        case .saveFailed:
            return "Failed to save the split"
        case .uploadFailed:
            return "Failed to upload receipt image"
        case .photoLibraryAccessDenied:
            return "Photo Library access denied. Please enable in Settings."
        case .photoLibrarySaveFailed:
            return "Failed to save receipt to Photo Library"
        }
    }
}

// MARK: - Preview Helpers

extension NewSplitViewModel {
    static var preview: NewSplitViewModel {
        let vm = NewSplitViewModel()
        vm.title = "Dinner at Restaurant"
        vm.emoji = "🍕"
        vm.totalAmount = 120.50
        vm.date = Date()
        return vm
    }
    
    static var previewWithItems: NewSplitViewModel {
        let vm = NewSplitViewModel()
        vm.title = "Grocery Shopping"
        vm.emoji = "🛒"
        vm.totalAmount = 85.00
        vm.splitMethod = .byItem
        
        var item1 = SplitItem(name: "Milk & Eggs", amount: 15.00)
        var item2 = SplitItem(name: "Snacks", amount: 25.00)
        var item3 = SplitItem(name: "Household Items", amount: 45.00)
        
        vm.items = [item1, item2, item3]
        
        return vm
    }
}
