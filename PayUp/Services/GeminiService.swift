//
//  GeminiService.swift
//  PayUp
//
//  Created by Rudra Das on 2025-12-28.
//

import Foundation
import ConvexMobile
import UIKit

/// Service for analyzing receipts using Gemini Vision API
@Observable
class GeminiService {
    static let shared = GeminiService()

    private init() {}
    
    // MARK: - Receipt Analysis
    
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysisResult {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.imageConversionFailed
        }
        
        let base64Image = imageData.base64EncodedString()

        let result: ReceiptAnalysisResult
        do {
            result = try await ConvexService.shared.client.action(
                "receiptAnalysis:analyzeReceipt",
                with: [
                    "imageBase64": base64Image,
                    "mimeType": "image/jpeg",
                ] as [String: String]
            )
        } catch {
            #if DEBUG
            print("Receipt analysis action failed: \(error)")
            #endif
            throw GeminiError.requestFailed(details: error.localizedDescription)
        }

        if result.isReceipt == false {
            throw GeminiError.notAReceipt
        }

        #if DEBUG
        print("=== Receipt Analysis Result ===")
        print("Merchant: \(result.merchantName ?? "nil")")
        print("Emoji: \(result.emoji ?? "nil")")
        print("Total: \(result.total ?? 0)")
        print("Items count: \(result.safeItems.count)")
        print("==============================")
        #endif

        return result
    }
}

// MARK: - Response Models

struct ReceiptAnalysisResult: Decodable {
    let isReceipt: Bool?
    let merchantName: String?
    let emoji: String?
    let items: [ReceiptItem]?
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let total: Double?
    let date: String?
    
    /// Safe accessor for items - returns empty array if nil
    var safeItems: [ReceiptItem] {
        items ?? []
    }
    
    struct ReceiptItem: Decodable {
        let name: String
        let quantity: Double  // Changed to Double to handle "1.0" from JSON
        let unitPrice: Double
        
        // Custom decoding to handle various number formats
        enum CodingKeys: String, CodingKey {
            case name, quantity, unitPrice
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Name - try String first, fallback to empty
            self.name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown Item"
            
            // Quantity - try Double, Int, or String
            if let doubleValue = try? container.decode(Double.self, forKey: .quantity) {
                self.quantity = doubleValue
            } else if let intValue = try? container.decode(Int.self, forKey: .quantity) {
                self.quantity = Double(intValue)
            } else if let stringValue = try? container.decode(String.self, forKey: .quantity),
                      let parsed = Double(stringValue) {
                self.quantity = parsed
            } else {
                self.quantity = 1.0  // Default to 1
            }
            
            // UnitPrice - try Double, Int, or String
            if let doubleValue = try? container.decode(Double.self, forKey: .unitPrice) {
                self.unitPrice = doubleValue
            } else if let intValue = try? container.decode(Int.self, forKey: .unitPrice) {
                self.unitPrice = Double(intValue)
            } else if let stringValue = try? container.decode(String.self, forKey: .unitPrice),
                      let parsed = Double(stringValue) {
                self.unitPrice = parsed
            } else {
                self.unitPrice = 0.0  // Default to 0
            }
        }
    }
    
    func toSplitItems() -> [SplitItem] {
        safeItems.map { item in
            SplitItem(
                name: item.name,
                quantity: max(1, Int(item.quantity)),
                amount: item.unitPrice
            )
        }
    }
}

enum GeminiError: Error, LocalizedError {
    case imageConversionFailed
    case invalidURL
    case requestFailed(details: String)
    case noContent
    case parsingFailed(details: String)
    case notAReceipt
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to process image"
        case .invalidURL:
            return "Invalid API URL"
        case .requestFailed(let details):
            return "Failed to analyze receipt: \(details)"
        case .noContent:
            return "No content in response"
        case .parsingFailed(let details):
            return "Failed to parse receipt data: \(details)"
        case .notAReceipt:
            return "The image does not appear to be a receipt"
        }
    }
}
