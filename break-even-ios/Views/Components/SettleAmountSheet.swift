//
//  SettleAmountSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-21.
//

import SwiftUI

/// Data model for presenting the settle view
struct SettleViewData: Identifiable {
    let id = UUID()
    let friend: ConvexFriend
    let userName: String
    let userAvatarUrl: String?
    let maxAmount: Double
    let currency: String
    let isUserPaying: Bool
    let onSettle: (Double, Date) async throws -> Void
}

/// Full-screen view for entering settlement amount with visual transfer flow
struct SettleView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Settlement data
    let data: SettleViewData
    
    @State private var amountText: String = ""
    @State private var settlementDate: Date = Date()
    @State private var isLoading = false
    @State private var error: String?
    @State private var isSettled = false
    @FocusState private var isAmountFocused: Bool
    
    private var amount: Double {
        Double(amountText) ?? 0
    }
    
    private var isValid: Bool {
        amount > 0 && amount <= data.maxAmount + 0.01 // Small tolerance
    }
    
    private var currencySymbol: String {
        SupportedCurrency.from(code: data.currency)?.symbol ?? "$"
    }
    
    private var userInitials: String {
        let components = data.userName.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let firstName = components.first, firstName.count >= 2 {
            return String(firstName.prefix(2)).uppercased()
        } else {
            return String(data.userName.prefix(2)).uppercased()
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                // Main content card
                VStack(spacing: 24) {
                    // Transfer Flow Header
                    transferFlowSection
                    
                    // Total to settle
                    HStack(spacing: 4) {
                        Text("Total to settle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(data.maxAmount.asCurrency(code: data.currency))
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(data.isUserPaying ? Color.appDestructive : Color.accent)
                    }
                    .padding(.vertical, 8)
                    
                    // Amount Input
                    amountInputSection
                    
                    // Quick amount buttons
                    quickAmountButtonsSection
                    
                    // Error message
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Settle Button
                    settleButton
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                isAmountFocused = false
            }
            .navigationTitle("Settle Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(settlementDate.smartFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay {
                            // 3. Put the REAL DatePicker on top, but make it invisible
                            DatePicker(
                                "",
                                selection: $settlementDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            // This is the magic: it's still there to be tapped,
                            // but it doesn't render visually.
                            .opacity(0.011)
                            .contentShape(Rectangle())
                        }
                }
            }
            .onAppear {
                // Pre-fill with full amount
                amountText = formatAmount(data.maxAmount)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAmountFocused = true
                }
            }
            .interactiveDismissDisabled(isLoading)
        }
    }
    
    // MARK: - Transfer Flow Section
    
    private var transferFlowSection: some View {
        VStack(alignment: .center,spacing: 12) {
            // Top person (Friend)
            personRow(
                name: data.friend.name,
                avatarUrl: data.friend.avatarUrl,
                initials: data.friend.initials,
                isFriend: true
            )
            
            // Direction arrow with text and date picker
            HStack {
                
                // Arrow and text
                HStack(spacing: 12) {
                    Image(systemName: data.isUserPaying ? "arrow.up" : "arrow.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(data.isUserPaying ? Color.appDestructive : Color.accent)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill( data.isUserPaying ? Color.destructive.opacity(0.2) : Color.accent.opacity(0.2))
                        )
                    
                    Text(data.isUserPaying ? "You are paying" : "You will receive")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(data.isUserPaying ? Color.appDestructive : Color.accent)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 2)
                
            }
            .padding(.vertical, 4)
            
            // Bottom person (User - "Me")
            personRow(
                name: "Me",
                avatarUrl: data.userAvatarUrl,
                initials: userInitials,
                isFriend: false
            )
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Person Row
    
    private func personRow(name: String, avatarUrl: String?, initials: String, isFriend: Bool) -> some View {
        HStack(spacing: 16) {
            // Avatar
            avatarImage(url: avatarUrl, initials: initials, isFriend: isFriend)
                .frame(width: 40, height: 40)
            
            // Name
            Text(name)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
        }
    }
    
    // MARK: - Avatar Image
    
    @ViewBuilder
    private func avatarImage(url: String?, initials: String, isFriend: Bool) -> some View {
        if let avatarUrl = url, let imageUrl = URL(string: avatarUrl) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure, .empty:
                    initialsAvatar(initials: initials, isFriend: isFriend)
                @unknown default:
                    initialsAvatar(initials: initials, isFriend: isFriend)
                }
            }
        } else {
            initialsAvatar(initials: initials, isFriend: isFriend)
        }
    }
    
    private func initialsAvatar(initials: String, isFriend: Bool) -> some View {
        Text(initials)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isFriend ? .accent : .white)
            .frame(width: 40, height: 40)
            .background(isFriend ? Color.accentSecondary : Color.accentColor)
            .clipShape(Circle())
    }
    
    // MARK: - Amount Input Section
    
    private var amountInputSection: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(currencySymbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("0", text: $amountText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .focused($isAmountFocused)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.accentSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Quick Amount Buttons
    
    private var quickAmountButtonsSection: some View {
        HStack(spacing: 12) {
            QuickAmountButton(label: "50%", amount: data.maxAmount * 0.5, currency: data.currency) {
                amountText = formatAmount(data.maxAmount * 0.5)
            }
            QuickAmountButton(label: "75%", amount: data.maxAmount * 0.75, currency: data.currency) {
                amountText = formatAmount(data.maxAmount * 0.75)
            }
            QuickAmountButton(label: "100%", amount: data.maxAmount, currency: data.currency) {
                amountText = formatAmount(data.maxAmount)
            }
        }
    }
    
    // MARK: - Settle Button
    
    private var settleButton: some View {
        Button {
            Task { await settle() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Settle \(amount.asCurrency(code: data.currency))")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid || isLoading)
    }
    
    // MARK: - Helper Methods
    
    private func formatAmount(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        if formatted.hasSuffix(".00") {
            return String(formatted.dropLast(3))
        } else if formatted.hasSuffix("0") && formatted.contains(".") {
            return String(formatted.dropLast())
        }
        return formatted
    }
    
    private func settle() async {
        guard isValid else { return }
        
        isLoading = true
        error = nil
        
        do {
            try await data.onSettle(amount, settlementDate)
            await MainActor.run {
                isSettled = true
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

struct QuickAmountButton: View {
    let label: String
    let amount: Double
    let currency: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(amount.asCurrency(code: currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Preview

#Preview("User Pays Friend") {
    SettleView(
        data: SettleViewData(
            friend: ConvexFriend(
                _id: "1",
                ownerId: "owner",
                linkedUserId: nil,
                name: "Alice Johnson",
                email: "alice@example.com",
                phone: nil,
                avatarUrl: nil,
                isDummy: true,
                isSelf: false,
                createdAt: Date().timeIntervalSince1970
            ),
            userName: "John Doe",
            userAvatarUrl: nil,
            maxAmount: 150.50,
            currency: "CAD",
            isUserPaying: true,
            onSettle: { amount, date in
                print("Settling \(amount) on \(date)")
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    )
}

#Preview("Friend Pays User") {
    SettleView(
        data: SettleViewData(
            friend: ConvexFriend(
                _id: "1",
                ownerId: "owner",
                linkedUserId: nil,
                name: "Bob Smith",
                email: "bob@example.com",
                phone: nil,
                avatarUrl: nil,
                isDummy: true,
                isSelf: false,
                createdAt: Date().timeIntervalSince1970
            ),
            userName: "Jane Doe",
            userAvatarUrl: nil,
            maxAmount: 75.00,
            currency: "USD",
            isUserPaying: false,
            onSettle: { amount, date in
                print("Settling \(amount) on \(date)")
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    )
}
