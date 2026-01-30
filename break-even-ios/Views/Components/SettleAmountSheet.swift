//
//  SettleAmountSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-21.
//

import SwiftUI
import CoreText

// MARK: - Core Text Path Helper

/// Converts text strings into geometric paths for Liquid Glass rendering
struct TextPathHelper {
    /// Cache for previously computed paths to improve performance
    private static var pathCache: [String: Path] = [:]
    
    static func convert(text: String, font: UIFont) -> Path {
        let cacheKey = "\(text)-\(font.fontName)-\(font.pointSize)"
        
        // Return cached path if available
        if let cached = pathCache[cacheKey] {
            return cached
        }
        
        let attributes = [NSAttributedString.Key.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        
        let cgPath = CGMutablePath()
        
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            for i in 0..<glyphCount {
                let range = CFRangeMake(i, 1)
                var glyph = CGGlyph()
                var position = CGPoint.zero
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)
                
                if let letterPath = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) {
                    let transform = CGAffineTransform(translationX: position.x, y: position.y)
                    cgPath.addPath(letterPath, transform: transform)
                }
            }
        }
        
        // Core Text paths are upside down; flip them
        var path = Path(cgPath)
        let bounds = path.boundingRect
        let transform = CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -bounds.height)
        
        let finalPath = path.applying(transform)
        
        // Cache the result
        pathCache[cacheKey] = finalPath
        
        return finalPath
    }
    
    /// Clears the path cache (useful for memory management)
    static func clearCache() {
        pathCache.removeAll()
    }
}

// MARK: - Glass Text Shape

/// A Shape that renders text glyphs for use with .glassEffect
struct GlassTextShape: Shape {
    let text: String
    let font: UIFont
    
    func path(in rect: CGRect) -> Path {
        guard !text.isEmpty else { return Path() }
        
        let path = TextPathHelper.convert(text: text, font: font)
        let bounds = path.boundingRect
        
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        
        // Center the path within the target rect
        let scaleX = rect.width / bounds.width
        let scaleY = rect.height / bounds.height
        let scale = min(scaleX, scaleY, 1.0) // Don't scale up, only down if needed
        
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        
        let offsetX = (rect.width - scaledWidth) / 2 - bounds.minX * scale
        let offsetY = (rect.height - scaledHeight) / 2 - bounds.minY * scale
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: offsetX / scale, y: offsetY / scale)
        
        return path.applying(transform)
    }
}

// MARK: - Shared Text Configuration

/// Shared configuration for amount display text
enum AmountTextConfig {
    static let fontSize: CGFloat = 48
    static let fontWeight: UIFont.Weight = .bold
    static var uiFont: UIFont { UIFont.systemFont(ofSize: fontSize, weight: fontWeight) }
    static var swiftUIFont: Font { .system(size: fontSize, weight: .bold) }
    
    static func textSize(for text: String) -> CGSize {
        let attributes = [NSAttributedString.Key.font: uiFont]
        return (text as NSString).size(withAttributes: attributes)
    }
}

// MARK: - SettleView

/// SettleView designed for NavigationStack push navigation
/// Follows iOS 26 best practices with Liquid Glass styling
/// Optimized for performance - no init calculations, uses .onAppear for setup
struct SettleView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool
    
    // Core State - initialized in .onAppear, not init
    @State private var amount: Double = 0
    @State private var amountText: String = ""
    @State private var settlementDate: Date = Date()
    @State private var isLoading = false
    @State private var error: String?
    
    // Props - passed in directly, no transformation in init
    let friend: ConvexFriend
    let userName: String
    let userAvatarUrl: String?
    let maxAmount: Double
    let currency: String
    let isUserPaying: Bool
    let onSettle: (Double, Date) async throws -> Void
    
    // Computed properties instead of init calculations
    private var isValid: Bool {
        amount > 0 && amount <= maxAmount + 0.01
    }
    
    private var currencySymbol: String {
        SupportedCurrency.from(code: currency)?.symbol ?? "$"
    }
    
    // Computed property for initials - no init calculation needed
    private var userInitials: String {
        userName.components(separatedBy: " ")
            .reduce("") { $0 + ($1.first.map(String.init) ?? "") }
            .uppercased()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Transfer flow visualization
                transferFlowSection
                
                // Total to settle info
                HStack {
                    Text("Total to settle")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(maxAmount.asCurrency(code: currency))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(isUserPaying ? Color.appDestructive : Color.accent)
                }
                
                // Amount input with Liquid Glass text display
                glassAmountInputSection
                
                // Quick amount buttons
                quickAmountButtons
                
                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Set initial value in onAppear, not init - prevents first-tap lag
            self.amount = maxAmount
            self.amountText = formatAmountForDisplay(maxAmount)
        }
        .onChange(of: amountText) { oldValue, newValue in
            // Strip commas to get the raw number
            let cleaned = newValue.replacingOccurrences(of: ",", with: "")
            let newAmount = Double(cleaned) ?? 0
            amount = newAmount
            
            // Format with commas for display (only if the value changed to avoid cursor issues)
            let formatted = formatAmountForDisplay(newAmount)
            if formatted != newValue && !newValue.isEmpty {
                amountText = formatted
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView("Processing...")
                        .frame(height: 56)
                } else {
                    SlideToSettleView(
                        title: "Slide to Settle \(amount.asCurrency(code: currency))",
                        onUnlock: {
                            Task { await settle() }
                        }
                    )
                    .opacity(isValid ? 1 : 0.5)
                    .allowsHitTesting(isValid)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .navigationTitle("Settle Payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Text determines the size, DatePicker overlaid for interaction
                Text(settlementDate.smartFormatted)
                    .padding(.horizontal, 12)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.accent)
                    .overlay {
                        DatePicker(selection: $settlementDate, in: ...Date(), displayedComponents: .date) {}
                            .labelsHidden()
                            .colorMultiply(.clear)
                    }
            }
        }
        .interactiveDismissDisabled(isLoading)
    }
    
    // MARK: - Transfer Flow Section
    
    private var transferFlowSection: some View {
        HStack(spacing: 12) {
            // Top person
            personRow(
                name: "Me",
                avatarUrl: userAvatarUrl,
                initials: userInitials,
                isUser: isUserPaying
            )
            
            Spacer()
            
            // Arrow
            Text(isUserPaying ? "You Pay" : "You Get")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isUserPaying ? Color.appDestructive : Color.accent)
                .padding(.bottom, 24)
            
            Spacer()
            
            // Bottom person
            personRow(
                name: friend.name,
                avatarUrl: friend.avatarUrl,
                initials: friend.initials,
                isUser: !isUserPaying
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func personRow(name: String, avatarUrl: String?, initials: String, isUser: Bool) -> some View {
        VStack(spacing: 12) {
            // Avatar
            if let url = avatarUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    default:
                        initialsAvatar(initials: initials, isUser: isUser)
                    }
                }
                .frame(width: 80, height: 80)
            } else {
                initialsAvatar(initials: initials, isUser: isUser)
            }
            
            Text(name)
                .font(.headline)
                .fontWeight(.medium)
        }
    }
    
    private func initialsAvatar(initials: String, isUser: Bool) -> some View {
        Text(initials)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 80, height: 80)
            .glassEffect(.regular.tint(isUser ? Color.accentColor.opacity(0.6) : Color.accent.opacity(0.4)), in: .circle)
    }
    
    // MARK: - Glass Amount Input Section (Liquid Glass Text)
    
    // Placeholder text when empty
    private let placeholderText = "0"
    
    // The amount text shown (shows placeholder when empty)
    private var displayAmountText: String {
        amountText.isEmpty ? placeholderText : amountText
    }
    
    // Opacity for glass effect (0.3 when showing placeholder)
    private var glassOpacity: Double {
        amountText.isEmpty ? 0.3 : 0.8
    }
    
    // Size calculations
    private var currencySize: CGSize {
        AmountTextConfig.textSize(for: currencySymbol)
    }
    
    private var amountSize: CGSize {
        AmountTextConfig.textSize(for: displayAmountText)
    }
    
    private var glassAmountInputSection: some View {
        ZStack(alignment: .center) {
            // Glass effect layer - currency + amount
            HStack(alignment: .center, spacing: 8) {
                // Currency symbol glass
                Color.clear
                    .frame(width: currencySize.width, height: currencySize.height)
                    .glassEffect(
                        .regular.tint(Color.text.opacity(0.3)).interactive(),
                        in: GlassTextShape(text: currencySymbol, font: AmountTextConfig.uiFont)
                    )
                
                // Amount glass (shows "0" placeholder when empty)
                Color.clear
                    .frame(width: amountSize.width, height: amountSize.height)
                    .glassEffect(
                        .regular.tint(Color.text.opacity(glassOpacity)).interactive(),
                        in: GlassTextShape(text: displayAmountText, font: AmountTextConfig.uiFont)
                    )
            }
            
            // Invisible layer - currency + TextField (same layout)
            HStack(alignment: .center, spacing: 8) {
                // Currency symbol (invisible)
                Text(currencySymbol)
                    .font(AmountTextConfig.swiftUIFont)
                    .foregroundStyle(.clear)
                    .frame(width: currencySize.width, height: currencySize.height)
                
                // TextField with "0" placeholder to align cursor
                TextField(placeholderText, text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .foregroundStyle(.clear)
                    .tint(.accent)
                    .font(AmountTextConfig.swiftUIFont)
                    .frame(width: amountSize.width, height: amountSize.height)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .contentShape(Rectangle())
        .onTapGesture {
            isAmountFocused = true
        }
    }
    
    // Helper to format amount for display with commas
    private func formatAmountForDisplay(_ value: Double) -> String {
        if value == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
    
    // MARK: - Quick Amount Buttons
    
    private var quickAmountButtons: some View {
        HStack(spacing: 8) {
            QuickAmountButton(label: "50%") {
                setAmount(maxAmount * 0.5)
            }
            QuickAmountButton(label: "75%") {
                setAmount(maxAmount * 0.75)
            }
            QuickAmountButton(label: "100%") {
                setAmount(maxAmount)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 90))
    }
    
    private func setAmount(_ value: Double) {
        amount = value
        amountText = formatAmountForDisplay(value)
    }
    
    // MARK: - Actions
    
    private func settle() async {
        guard isValid else { return }
        
        isLoading = true
        error = nil
        
        do {
            try await onSettle(amount, settlementDate)
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Quick Amount Button

private struct QuickAmountButton: View {
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(Color.accentSecondary.opacity(0.3))
        .clipShape(ConcentricRectangle(topLeadingCorner: .concentric(minimum: 6), topTrailingCorner: .concentric(minimum: 6), bottomLeadingCorner: .concentric(minimum: 6), bottomTrailingCorner: .concentric(minimum: 6)))
    }
}

// MARK: - Preview

#Preview("User Pays Friend") {
    NavigationStack {
        SettleView(
            friend: ConvexFriend(
                _id: "1",
                ownerId: "owner",
                linkedUserId: nil,
                name: "Alice",
                email: nil,
                phone: nil,
                avatarUrl: nil,
                isDummy: false,
                isSelf: false,
                createdAt: Date().timeIntervalSince1970 * 1000
            ),
            userName: "John Doe",
            userAvatarUrl: nil,
            maxAmount: 150.50,
            currency: "CAD",
            isUserPaying: true,
            onSettle: { _, _ in }
        )
    }
}

#Preview("Friend Pays User") {
    NavigationStack {
        SettleView(
            friend: ConvexFriend(
                _id: "1",
                ownerId: "owner",
                linkedUserId: nil,
                name: "Bob",
                email: nil,
                phone: nil,
                avatarUrl: nil,
                isDummy: false,
                isSelf: false,
                createdAt: Date().timeIntervalSince1970 * 1000
            ),
            userName: "Jane Smith",
            userAvatarUrl: nil,
            maxAmount: 75.25,
            currency: "USD",
            isUserPaying: false,
            onSettle: { _, _ in }
        )
    }
}
