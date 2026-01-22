//
//  SplitDetailView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

/// Alias for backward compatibility
typealias TransactionDetailView = SplitDetailView

struct SplitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    let transaction: EnrichedTransaction
    let userCurrency: String  // User's default currency for display
    
    @State private var detailedTransaction: EnrichedTransaction?
    @State private var isLoading = false
    @State private var showDeleteAlert = false
    
    private var displayTransaction: EnrichedTransaction {
        detailedTransaction ?? transaction
    }
    
    /// Whether the transaction currency differs from user's default
    private var showCurrencyConversion: Bool {
        displayTransaction.currency != userCurrency
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Amount Card
                amountCard
                
                // Receipt Image (if available)
                if let receiptUrl = displayTransaction.receiptUrl, let url = URL(string: receiptUrl) {
                    receiptSection(url: url)
                }
                
                // Splits Section
                splitsSection
                
                // Items Section (if by-item split)
                if let items = displayTransaction.items, !items.isEmpty {
                    itemsSection(items: items)
                }
                
                // Delete Button
                deleteButton
            }
            .padding()
        }
        .navigationTitle("Split Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDetails()
        }
        .alert("Delete Split", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("Are you sure you want to delete this split? This cannot be undone.")
        }
    }
    
    // MARK: - Load Details
    
    private func loadDetails() {
        Task {
            // Use subscribe + first value pattern since ConvexMobile has no query() method
            let subscription = convexService.client.subscribe(
                to: "transactions:getTransactionDetail",
                with: ["transactionId": transaction._id],
                yielding: EnrichedTransaction?.self
            )
            .replaceError(with: nil)
            .values
            
            var iterator = subscription.makeAsyncIterator()
            if let detail = await iterator.next() {
                await MainActor.run {
                    self.detailedTransaction = detail
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(displayTransaction.emoji)
                .font(.system(size: 60))
            
            Text(displayTransaction.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(displayTransaction.dateValue.formatted(date: .long, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Amount Card
    
    private var amountCard: some View {
        VStack(spacing: 8) {
            Text("Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Show amount in original transaction currency
            Text(displayTransaction.formattedAmount)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // If transaction currency differs from user's default, show converted amount
            if showCurrencyConversion {
                Text("(\(displayTransaction.formattedAmount(in: userCurrency)))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text("Paid by")
                    .foregroundStyle(.secondary)
                Text(displayTransaction.payerName)
                    .fontWeight(.medium)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Receipt Section
    
    private func receiptSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Receipt")
                .font(.headline)
            
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 200)
                    .overlay {
                        ProgressView()
                    }
            }
        }
    }
    
    // MARK: - Splits Section
    
    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split Breakdown")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(displayTransaction.splits, id: \.id) { split in
                    SplitRow(
                        split: split,
                        currencyCode: displayTransaction.currency,
                        showConversion: showCurrencyConversion,
                        userCurrency: userCurrency,
                        exchangeRates: displayTransaction.exchangeRates
                    )
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Items Section
    
    private func itemsSection(items: [ConvexTransactionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body)
                            
                            if item.quantity > 1 {
                                Text("Qty: \(item.quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Show item price in transaction's currency
                        Text(item.totalPrice.asCurrency(code: displayTransaction.currency))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 4)
                    
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Delete Button
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Split")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top)
    }
    
    // MARK: - Delete Transaction
    
    private func deleteTransaction() {
        Task {
            do {
                let _: Bool = try await convexService.client.mutation(
                    "transactions:deleteTransaction",
                    with: ["transactionId": transaction._id]
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Failed to delete transaction: \(error)")
            }
        }
    }
}

// MARK: - Split Row

struct SplitRow: View {
    let split: EnrichedSplit
    let currencyCode: String
    let showConversion: Bool
    let userCurrency: String
    let exchangeRates: ExchangeRates?
    
    /// Converted amount in user's currency
    private var convertedAmount: Double {
        guard let rates = exchangeRates else {
            return split.amount
        }
        return rates.convert(amount: split.amount, from: currencyCode, to: userCurrency)
    }
    
    var body: some View {
        HStack {
            // Avatar
            if let friend = split.friend {
                Text(friend.initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            
            // Name
            Text(split.personName)
                .font(.body)
            
            Spacer()
            
            // Amount display
            VStack(alignment: .trailing, spacing: 2) {
                Text(split.amount.asCurrency(code: currencyCode))
                    .font(.body)
                    .fontWeight(.medium)
                
                if showConversion {
                    Text("(\(convertedAmount.asCurrency(code: userCurrency)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SplitDetailView(
            transaction: EnrichedTransaction(
                _id: "1",
                createdById: "user1",
                paidById: "friend1",
                title: "Team Dinner",
                emoji: "🍕",
                description: nil,
                totalAmount: 156.80,
                currency: "EUR",
                splitMethod: "equal",
                receiptFileId: nil,
                items: nil,
                exchangeRates: ExchangeRates(
                    baseCurrency: "USD",
                    rates: CurrencyRates.fallback,
                    fetchedAt: Date().timeIntervalSince1970 * 1000
                ),
                date: Date().timeIntervalSince1970 * 1000,
                createdAt: Date().timeIntervalSince1970 * 1000,
                payer: nil,
                splits: [],
                receiptUrl: nil
            ),
            userCurrency: "USD"
        )
    }
}
