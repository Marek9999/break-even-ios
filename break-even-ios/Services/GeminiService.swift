//
//  GeminiService.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-12-28.
//

import Foundation
import UIKit

/// Service for analyzing receipts using Gemini Vision API
@Observable
class GeminiService {
    static let shared = GeminiService()
    
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    private init() {
        self.apiKey = Configuration.geminiAPIKey
    }
    
    // MARK: - Receipt Analysis
    
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysisResult {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.imageConversionFailed
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": """
                            Look at this image. First determine if it is a receipt, invoice, or bill of any kind.
                            
                            If the image is NOT a receipt/invoice/bill, return ONLY this JSON and nothing else:
                            {"isReceipt": false}
                            
                            If the image IS a receipt/invoice/bill, extract the information in JSON format following these rules:
                            
                            IMPORTANT RULES:
                            1. Return ONLY valid JSON, no markdown, no code blocks, no explanations
                            2. All prices must be numbers (not strings), without currency symbols
                            3. quantity must be a number (can be decimal like 1.0)
                            4. If you cannot read a value, use these defaults:
                               - merchantName: "Receipt"
                               - emoji: "🧾"
                               - items: [] (empty array)
                               - quantity: 1
                               - unitPrice: 0
                               - subtotal: 0
                               - tax: 0
                               - tip: 0
                               - total: 0
                               - date: "" (empty string)
                            5. NEVER use null - use empty string "" or 0 instead
                            6. emoji must be a single emoji that best represents the merchant or category (e.g. 🍕 for pizza, 🛒 for grocery, ☕ for coffee shop, 🍺 for bar, ⛽ for gas station, 💊 for pharmacy)
                            
                            Expected JSON structure:
                            {
                                "isReceipt": true,
                                "merchantName": "Store Name",
                                "emoji": "🛒",
                                "items": [
                                    {
                                        "name": "Item description",
                                        "quantity": 1,
                                        "unitPrice": 9.99
                                    }
                                ],
                                "subtotal": 9.99,
                                "tax": 0.80,
                                "tip": 0,
                                "total": 10.79,
                                "date": "2025-01-18"
                            }
                            
                            Now analyze the image and return the JSON:
                            """
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(details: "Invalid response type")
        }
        
        // Check for error response
        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse error details from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.requestFailed(details: "API Error (\(httpResponse.statusCode)): \(message)")
            }
            throw GeminiError.requestFailed(details: "HTTP \(httpResponse.statusCode)")
        }
        
        // Parse Gemini response
        let geminiResponse: GeminiResponse
        do {
            geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            // Log the raw response for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("Gemini raw response: \(responseString)")
            throw GeminiError.parsingFailed(details: "Failed to decode response: \(error.localizedDescription)")
        }
        
        guard let textContent = geminiResponse.candidates.first?.content.parts.first?.text else {
            throw GeminiError.noContent
        }
        
        // Extract JSON from response (in case there's extra text)
        let jsonString = extractJSON(from: textContent)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GeminiError.parsingFailed(details: "Failed to convert JSON string to data")
        }
        
        do {
            let result = try JSONDecoder().decode(ReceiptAnalysisResult.self, from: jsonData)
            
            if result.isReceipt == false {
                throw GeminiError.notAReceipt
            }
            
            print("=== Receipt Analysis Result ===")
            print("Merchant: \(result.merchantName ?? "nil")")
            print("Emoji: \(result.emoji ?? "nil")")
            print("Total: \(result.total ?? 0)")
            print("Subtotal: \(result.subtotal ?? 0)")
            print("Tax: \(result.tax ?? 0)")
            print("Tip: \(result.tip ?? 0)")
            print("Date: \(result.date ?? "nil")")
            print("Items count: \(result.safeItems.count)")
            for (index, item) in result.safeItems.enumerated() {
                print("  Item \(index + 1): \(item.name) - qty: \(item.quantity) @ \(item.unitPrice)")
            }
            print("==============================")
            
            return result
        } catch let error as GeminiError {
            throw error
        } catch {
            print("Receipt JSON parsing error: \(error)")
            print("JSON string was: \(jsonString)")
            throw GeminiError.parsingFailed(details: "Invalid receipt format: \(error.localizedDescription)")
        }
    }
    
    private func extractJSON(from text: String) -> String {
        // Find JSON content between { and }
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[startIndex...endIndex])
    }
}

// MARK: - Response Models

struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]
}

struct GeminiPart: Decodable {
    let text: String?
}

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
