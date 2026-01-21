//
//  SettleAmountSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-21.
//

import SwiftUI

/// Reusable sheet for entering settlement amount
struct SettleAmountSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let maxAmount: Double
    let currency: String
    let friendName: String
    let isUserPaying: Bool  // true = user pays friend, false = friend pays user
    let onSettle: (Double) async throws -> Void
    
    @State private var amountText: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var isAmountFocused: Bool
    
    private var amount: Double {
        Double(amountText) ?? 0
    }
    
    private var isValid: Bool {
        amount > 0 && amount <= maxAmount + 0.01 // Small tolerance
    }
    
    private var headerText: String {
        isUserPaying ? "Pay \(friendName)" : "Receive from \(friendName)"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: isUserPaying ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isUserPaying ? Color.appDestructive : Color.accent)
                    
                    Text(headerText)
                        .font(.headline)
                    
                    Text("Max: \(maxAmount.asCurrency(code: currency))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                // Amount Input
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(SupportedCurrency.from(code: currency)?.symbol ?? "$")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("0", text: $amountText)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($isAmountFocused)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.tint(Color.accent.opacity(0.1)))
                    
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
                
                // Quick amount buttons
                HStack(spacing: 12) {
                    QuickAmountButton(label: "25%", amount: maxAmount * 0.25, currency: currency) {
                        amountText = formatAmount(maxAmount * 0.25)
                    }
                    QuickAmountButton(label: "50%", amount: maxAmount * 0.5, currency: currency) {
                        amountText = formatAmount(maxAmount * 0.5)
                    }
                    QuickAmountButton(label: "Full", amount: maxAmount, currency: currency) {
                        amountText = formatAmount(maxAmount)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Settle Button
                Button {
                    Task { await settle() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Settle \(amount.asCurrency(code: currency))")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValid || isLoading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill with full amount
            amountText = formatAmount(maxAmount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAmountFocused = true
            }
        }
        .interactiveDismissDisabled(isLoading)
    }
    
    private func formatAmount(_ value: Double) -> String {
        // Format with 2 decimal places, removing trailing zeros
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
            try await onSettle(amount)
            await MainActor.run {
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

#Preview {
    SettleAmountSheet(
        maxAmount: 150.50,
        currency: "USD",
        friendName: "Alice",
        isUserPaying: false,
        onSettle: { amount in
            print("Settling \(amount)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    )
}
