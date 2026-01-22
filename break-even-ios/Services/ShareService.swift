//
//  ShareService.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import Foundation
import UIKit

/// Service for sharing splits via various methods
class ShareService {
    static let shared = ShareService()
    
    private init() {}
    
    // MARK: - Generate Share Content
    
    func generatePlainTextSummary(for transaction: EnrichedTransaction) -> String {
        let splits = transaction.splits ?? []
        
        var text = """
        💸 Split Request: \(transaction.emoji) \(transaction.title)
        
        Total: \(transaction.formattedAmount)
        Paid by: \(transaction.payerName)
        
        Split breakdown:
        """
        
        for split in splits {
            let friendName = split.friend?.displayName ?? "Unknown"
            text += "\n• \(friendName): \(split.formattedAmount)"
        }
        
        text += "\n\nSent via Break Even"
        
        return text
    }
    
    // MARK: - Share Actions
    
    func share(transaction: EnrichedTransaction, from viewController: UIViewController) {
        let text = generatePlainTextSummary(for: transaction)
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        viewController.present(activityVC, animated: true)
    }
    
    func copyToClipboard(transaction: EnrichedTransaction) {
        UIPasteboard.general.string = generatePlainTextSummary(for: transaction)
    }
}
