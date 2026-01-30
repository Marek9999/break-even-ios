//
//  Extensions.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-12-28.
//

import SwiftUI

// MARK: - View Extensions

extension View {
    /// Adds haptic feedback on tap
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        }
    }
    
    /// Applies card styling
    func cardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Date Extensions

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Smart date format: "Jan 5" for current year, "Jan 5, '25" for other years
    /// Uses abbreviated year (.twoDigits) to keep UI compact
    var smartFormatted: String {
        let currentYear = Calendar.current.component(.year, from: .now)
        let targetYear = Calendar.current.component(.year, from: self)
        
        if currentYear == targetYear {
            // Omit the year if it matches the current year
            return self.formatted(.dateTime.month(.abbreviated).day())
        } else {
            // Include abbreviated year if it's a different year
            return self.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
    
    var fullFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions

extension Double {
    /// Format as currency using default currency (USD)
    var asCurrency: String {
        asCurrency(code: Configuration.defaultCurrency)
    }
    
    /// Format as currency using a specific currency code
    /// Uses custom symbols: $ (USD), € (EUR), £ (GBP), C$ (CAD), A$ (AUD), ₹ (INR), ¥ (JPY)
    func asCurrency(code: String) -> String {
        let symbol = currencySymbol(for: code)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = (code == "JPY") ? 0 : 2
        formatter.maximumFractionDigits = (code == "JPY") ? 0 : 2
        let formattedNumber = formatter.string(from: NSNumber(value: self)) ?? String(format: code == "JPY" ? "%.0f" : "%.2f", self)
        return "\(symbol)\(formattedNumber)"
    }
    
    /// Compact currency format for pills (e.g., "$21.5" instead of "$21.50")
    var asCompactCurrency: String {
        asCompactCurrency(code: Configuration.defaultCurrency)
    }
    
    /// Compact currency format with specific currency code (e.g., "$21.5" instead of "$21.50")
    /// Uses custom symbols: $ (USD), € (EUR), £ (GBP), C$ (CAD), A$ (AUD), ₹ (INR), ¥ (JPY)
    func asCompactCurrency(code: String) -> String {
        let symbol = currencySymbol(for: code)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        
        // Handle Japanese Yen which doesn't use decimal places
        if code == "JPY" {
            formatter.maximumFractionDigits = 0
        } else {
            // Remove trailing zeros
            if self == floor(self) {
                formatter.maximumFractionDigits = 0
            } else if (self * 10) == floor(self * 10) {
                formatter.maximumFractionDigits = 1
            } else {
                formatter.maximumFractionDigits = 2
            }
        }
        let formattedNumber = formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
        return "\(symbol)\(formattedNumber)"
    }
    
    var asPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
    }
    
    /// Helper to get currency symbol
    private func currencySymbol(for code: String) -> String {
        if let currency = SupportedCurrency.from(code: code) {
            return currency.symbol
        }
        return "$"
    }
}

// MARK: - Color Extensions

extension Color {
    // App accent colors from assets
    static let appAccent = Color("AccentColor")
    static let appAccentSecondary = Color("AccentSecondary")
    static let appDestructive = Color("Destructive")
    static let appDestructiveSecondary = Color("DesctructiveSecondary")
    static let appDestructiveText = Color("DestructiveText")
    static let appText = Color("Text")
    
    // Semantic colors
    static let owedToMe = Color("AccentColor")
    static let iOwe = Color("Destructive")
    static let owedToMeSecondary = Color("AccentSecondary")
    static let iOweSecondary = Color("DesctructiveSecondary")
    
    // Legacy aliases
    static let appPrimary = Color("AccentColor")
    static let appSecondary = Color.gray
    static let appSuccess = Color.green
    static let appWarning = Color.orange
    static let appDanger = Color("Destructive")
    static let pending = Color.orange
    static let settled = Color.green
}

// MARK: - String Extensions

extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
}
