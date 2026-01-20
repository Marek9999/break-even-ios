//
//  Currency.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-19.
//

import Foundation

/// Supported currencies in the app
enum SupportedCurrency: String, CaseIterable, Codable, Identifiable {
    case USD
    case EUR
    case GBP
    case CAD
    case AUD
    case INR
    case JPY
    
    var id: String { rawValue }
    
    /// Currency symbol (e.g., "$", "€")
    var symbol: String {
        switch self {
        case .USD: return "$"
        case .EUR: return "€"
        case .GBP: return "£"
        case .CAD: return "C$"
        case .AUD: return "A$"
        case .INR: return "₹"
        case .JPY: return "¥"
        }
    }
    
    /// Full currency name
    var name: String {
        switch self {
        case .USD: return "US Dollar"
        case .EUR: return "Euro"
        case .GBP: return "British Pound"
        case .CAD: return "Canadian Dollar"
        case .AUD: return "Australian Dollar"
        case .INR: return "Indian Rupee"
        case .JPY: return "Japanese Yen"
        }
    }
    
    /// Display string combining code and name (e.g., "USD - US Dollar")
    var displayName: String {
        "\(rawValue) - \(name)"
    }
    
    /// Short display with symbol and code (e.g., "$ USD")
    var shortDisplay: String {
        "\(symbol) \(rawValue)"
    }
    
    /// Flag emoji for the currency's primary country
    var flag: String {
        switch self {
        case .USD: return "🇺🇸"
        case .EUR: return "🇪🇺"
        case .GBP: return "🇬🇧"
        case .CAD: return "🇨🇦"
        case .AUD: return "🇦🇺"
        case .INR: return "🇮🇳"
        case .JPY: return "🇯🇵"
        }
    }
    
    /// Number of decimal places typically used for this currency
    var decimalPlaces: Int {
        switch self {
        case .JPY:
            return 0 // Japanese Yen doesn't use decimal places
        default:
            return 2
        }
    }
    
    /// Create a SupportedCurrency from a string code, returning nil if invalid
    static func from(code: String) -> SupportedCurrency? {
        return SupportedCurrency(rawValue: code.uppercased())
    }
}

// MARK: - Exchange Rates Model

/// Exchange rates snapshot stored with transactions
struct ExchangeRates: Codable, Equatable {
    let baseCurrency: String
    let rates: CurrencyRates
    let fetchedAt: Double
    
    /// Convert an amount from one currency to another
    func convert(amount: Double, from fromCurrency: String, to toCurrency: String) -> Double {
        if fromCurrency == toCurrency {
            return amount
        }
        
        guard let fromRate = rates.rate(for: fromCurrency),
              let toRate = rates.rate(for: toCurrency) else {
            return amount
        }
        
        // Convert through USD (base currency)
        let amountInUSD = amount / fromRate
        return amountInUSD * toRate
    }
}

/// Currency rates relative to USD
struct CurrencyRates: Codable, Equatable {
    let USD: Double
    let EUR: Double
    let GBP: Double
    let CAD: Double
    let AUD: Double
    let INR: Double
    let JPY: Double
    
    /// Get rate for a currency code
    func rate(for code: String) -> Double? {
        switch code.uppercased() {
        case "USD": return USD
        case "EUR": return EUR
        case "GBP": return GBP
        case "CAD": return CAD
        case "AUD": return AUD
        case "INR": return INR
        case "JPY": return JPY
        default: return nil
        }
    }
    
    /// Default fallback rates (approximate values)
    static let fallback = CurrencyRates(
        USD: 1.0,
        EUR: 0.92,
        GBP: 0.79,
        CAD: 1.36,
        AUD: 1.53,
        INR: 83.12,
        JPY: 149.50
    )
}

// MARK: - JSON Encoding for Convex

extension ExchangeRates {
    /// Convert to JSON string for Convex API
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
}
