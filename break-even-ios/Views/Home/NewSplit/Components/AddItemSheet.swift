//
//  AddItemSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let currencyCode: String
    let onAdd: (String, Double, Int) -> Void
    
    @State private var itemName = ""
    @State private var totalPriceText = ""
    @State private var quantity = 1
    
    private var currencySymbol: String {
        SupportedCurrency.from(code: currencyCode)?.symbol ?? "$"
    }
    
    private var totalPrice: Double {
        Double(totalPriceText) ?? 0
    }
    
    private var pricePerUnit: Double {
        quantity > 0 ? totalPrice / Double(quantity) : 0
    }
    
    private var isValid: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty && totalPrice > 0 && quantity >= 1
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 24) {
                    itemNameRow
                    totalRow
                    quantityRow
                    
                    if totalPrice > 0 && quantity > 1 {
                        pricePerUnitRow
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(itemName.trimmingCharacters(in: .whitespaces), pricePerUnit, quantity)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isValid ? .accent : .text.opacity(0.3))
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Field Rows
    
    private var itemNameRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Item Name")
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
                .frame(width: 110, alignment: .leading)
                .padding(.horizontal, 16)
            
            TextField("Item Name", text: $itemName)
                .font(.body)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.background.tertiary)
                .clipShape(Capsule())
        }
    }
    
    private var totalRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Total")
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
                .frame(width: 110, alignment: .leading)
                .padding(.horizontal, 16)
            
            HStack(spacing: 6) {
                Text(currencySymbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                TextField("0.00", text: $totalPriceText)
                    .font(.body)
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.tertiary)
            .clipShape(Capsule())
        }
    }
    
    private var quantityRow: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quantity")
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
                .frame(width: 110, alignment: .leading)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                let isMinimum = quantity <= 1
                
                Button {
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.text.opacity(isMinimum ? 0.3 : 1.0))
                        .frame(width: 36, height: 36)
                        .background(.background.secondary.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonRepeatBehavior(.enabled)
                .disabled(isMinimum)
                
                Spacer()
                
                Text("\(quantity)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(minWidth: 30)
                
                Spacer()
                
                Button {
                    quantity += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.text)
                        .frame(width: 36, height: 36)
                        .background(.background.secondary.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonRepeatBehavior(.enabled)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var pricePerUnitRow: some View {
        HStack {
            Text("Price per unit")
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(pricePerUnit.asCurrency(code: currencyCode))
                .font(.body)
                .fontWeight(.medium)
        }
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("Add Item Sheet") {
    AddItemSheet(currencyCode: "USD", onAdd: { _, _, _ in })
}
#endif
