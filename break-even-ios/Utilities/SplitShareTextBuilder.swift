//
//  SplitShareTextBuilder.swift
//  break-even-ios
//
//  Created by Cursor on 2026-03-25.
//

import Foundation

enum SplitShareTextBuilder {
    private static let divider = "________________________________"
    
    static func text(for transaction: EnrichedTransaction, currentUserLabel: String? = nil) -> String {
        var sections: [String] = []
        
        sections.append(titleSection(for: transaction))
        sections.append(summarySection(for: transaction, currentUserLabel: currentUserLabel))
        sections.append(participantsSection(for: transaction, currentUserLabel: currentUserLabel))
        
        if hasReceipt(for: transaction) {
            sections.append(receiptSection(for: transaction))
        }
        
        if let itemsSection = itemizedSection(for: transaction, currentUserLabel: currentUserLabel) {
            sections.append(itemsSection)
        }
        
        if let activitySection = activitySection(for: transaction) {
            sections.append(activitySection)
        }
        
        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    private static func titleSection(for transaction: EnrichedTransaction) -> String {
        "\(transaction.emoji) \(transaction.title.uppercased())"
    }
    
    private static func summarySection(for transaction: EnrichedTransaction, currentUserLabel: String?) -> String {
        var lines = [
            divider,
            "Total: \(transaction.totalAmount.asCurrency(code: transaction.currency))",
            "Split method: \(splitMethodName(for: transaction))",
            "Paid by: \(displayName(for: transaction.payer, currentUserLabel: currentUserLabel) ?? transaction.payerName)",
            "Date: \(transaction.dateValue.formatted(date: .long, time: .omitted))",
        ]
        
        if let description = transaction.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            lines.append("Note: \(description)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func participantsSection(for transaction: EnrichedTransaction, currentUserLabel: String?) -> String {
        let sectionTitle = transaction.splitMethod == ConvexSplitMethod.byParts.rawValue
            ? "SHARES"
            : "PARTICIPANTS"
        
        var lines = [sectionTitle, divider]
        lines.append(contentsOf: transaction.splits.map { participantLine(for: $0, in: transaction, currentUserLabel: currentUserLabel) })
        return lines.joined(separator: "\n")
    }
    
    private static func participantLine(
        for split: EnrichedSplit,
        in transaction: EnrichedTransaction,
        currentUserLabel: String?
    ) -> String {
        let name = displayName(for: split.friend, currentUserLabel: currentUserLabel) ?? split.personName
        let amount = split.amount.asCurrency(code: transaction.currency)
        
        if transaction.splitMethod == ConvexSplitMethod.byParts.rawValue,
           let shareDescription = sharesDescription(for: split, in: transaction) {
            return "\(name) - \(shareDescription) - \(amount)"
        }
        
        return "\(name) - \(amount)"
    }
    
    private static func receiptSection(for transaction: EnrichedTransaction) -> String {
        var lines = [
            "RECEIPT",
            divider,
            "Receipt photo attached in app: Yes",
        ]
        
        if transaction.items?.isEmpty != false {
            lines.append("Structured line items: None")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func itemizedSection(for transaction: EnrichedTransaction, currentUserLabel: String?) -> String? {
        guard let items = transaction.items, !items.isEmpty else { return nil }
        
        var lines = [
            "LINE ITEMS",
            divider,
        ]
        
        for (index, item) in items.enumerated() {
            if index > 0 {
                lines.append("")
            }
            
            lines.append(itemLine(for: item, currencyCode: transaction.currency))
            lines.append("Assigned to: \(assignedNames(for: item, in: transaction, currentUserLabel: currentUserLabel))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func itemLine(for item: ConvexTransactionItem, currencyCode: String) -> String {
        "\(item.name) x\(item.quantity) - \(item.totalPrice.asCurrency(code: currencyCode))"
    }
    
    private static func assignedNames(
        for item: ConvexTransactionItem,
        in transaction: EnrichedTransaction,
        currentUserLabel: String?
    ) -> String {
        let names = item.assignedToIds.compactMap { assignedId in
            transaction.splits.first(where: { $0.friendId == assignedId }).map {
                displayName(for: $0.friend, currentUserLabel: currentUserLabel) ?? $0.personName
            }
        }
        
        return names.isEmpty ? "No one assigned" : names.joined(separator: ", ")
    }
    
    private static func activitySection(for transaction: EnrichedTransaction) -> String? {
        var lines: [String] = []
        
        if let editHistory = transaction.enrichedEditHistory, !editHistory.isEmpty {
            if lines.isEmpty {
                lines = ["ACTIVITY", divider]
            }
            
            for entry in editHistory.reversed() {
                let editedAt = Date(timeIntervalSince1970: entry.editedAt / 1000)
                lines.append("Edited by \(entry.editedByName) on \(editedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        } else if let editedByName = transaction.lastEditedByName,
                  let editedAt = transaction.lastEditedAt {
            let editedDate = Date(timeIntervalSince1970: editedAt / 1000)
            lines = [
                "ACTIVITY",
                divider,
                "Edited by \(editedByName) on \(editedDate.formatted(date: .abbreviated, time: .shortened))",
            ]
        }
        
        if let createdByName = transaction.createdByName {
            let createdAt = Date(timeIntervalSince1970: transaction.createdAt / 1000)
            if lines.isEmpty {
                lines = ["ACTIVITY", divider]
            }
            lines.append("Created by \(createdByName) on \(createdAt.formatted(date: .abbreviated, time: .shortened))")
        }
        
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    
    private static func splitMethodName(for transaction: EnrichedTransaction) -> String {
        ConvexSplitMethod(rawValue: transaction.splitMethod)?.displayName ?? transaction.splitMethod
    }
    
    private static func hasReceipt(for transaction: EnrichedTransaction) -> Bool {
        transaction.receiptUrl != nil || transaction.receiptFileId != nil
    }
    
    private static func displayName(for friend: ConvexFriend?, currentUserLabel: String?) -> String? {
        if friend?.isSelf == true, let currentUserLabel, !currentUserLabel.isEmpty {
            return currentUserLabel
        }
        return friend?.displayName
    }
    
    private static func sharesDescription(for split: EnrichedSplit, in transaction: EnrichedTransaction) -> String? {
        if let shareCount = inferredShareCount(for: split, in: transaction) {
            return "\(shareCount) share\(shareCount == 1 ? "" : "s")"
        }
        
        if let percentage = split.percentage {
            return percentage.asPercentage
        }
        
        return nil
    }
    
    private static func inferredShareCount(for split: EnrichedSplit, in transaction: EnrichedTransaction) -> Int? {
        let percentages = transaction.splits.compactMap(\.percentage)
        guard percentages.count == transaction.splits.count, !percentages.isEmpty else {
            return nil
        }
        
        for scale in 1...24 {
            let inferredCounts = percentages.map { Int(round($0 * Double(scale) / 100.0)) }
            guard inferredCounts.allSatisfy({ $0 > 0 }) else { continue }
            
            let total = inferredCounts.reduce(0, +)
            guard total > 0 else { continue }
            
            let rebuiltPercentages = inferredCounts.map { Double($0) / Double(total) * 100.0 }
            let isMatch = zip(percentages, rebuiltPercentages).allSatisfy { original, rebuilt in
                abs(original - rebuilt) < 0.2
            }
            
            if isMatch, let splitIndex = transaction.splits.firstIndex(of: split) {
                return inferredCounts[splitIndex]
            }
        }
        
        return nil
    }
    
}
