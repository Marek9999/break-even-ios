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
    
    var fullFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions

extension Double {
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Configuration.defaultCurrency
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
    
    /// Compact currency format for pills (e.g., "$21.5" instead of "$21.50")
    var asCompactCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Configuration.defaultCurrency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        // Remove trailing zeros
        if self == floor(self) {
            formatter.maximumFractionDigits = 0
        } else if (self * 10) == floor(self * 10) {
            formatter.maximumFractionDigits = 1
        }
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
    
    var asPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
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
