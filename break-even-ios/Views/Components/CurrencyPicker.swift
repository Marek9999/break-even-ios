//
//  CurrencyPicker.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-19.
//

import SwiftUI

/// A reusable currency picker component
struct CurrencyPicker: View {
    @Binding var selectedCurrency: String
    var label: String = "Currency"
    var showLabel: Bool = true
    
    var body: some View {
        if showLabel {
            Picker(label, selection: $selectedCurrency) {
                ForEach(SupportedCurrency.allCases) { currency in
                    HStack(spacing: 8) {
                        Text(currency.flag)
                        Text(currency.rawValue)
                            .fontWeight(.medium)
                        Text("-")
                            .foregroundStyle(.secondary)
                        Text(currency.name)
                            .foregroundStyle(.secondary)
                    }
                    .tag(currency.rawValue)
                }
            }
        } else {
            Picker("", selection: $selectedCurrency) {
                ForEach(SupportedCurrency.allCases) { currency in
                    HStack(spacing: 8) {
                        Text(currency.flag)
                        Text(currency.rawValue)
                            .fontWeight(.medium)
                    }
                    .tag(currency.rawValue)
                }
            }
            .labelsHidden()
        }
    }
}

/// Inline currency selector button that shows a sheet
struct CurrencyButton: View {
    @Binding var selectedCurrency: String
    @State private var showPicker = false
    
    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                if let currency = SupportedCurrency.from(code: selectedCurrency) {
                    Text(currency.flag)
                    Text(currency.rawValue)
                        .fontWeight(.medium)
                } else {
                    Text(selectedCurrency)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            CurrencyPickerSheet(selectedCurrency: $selectedCurrency)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Full-screen currency picker sheet
struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCurrency: String
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SupportedCurrency.allCases) { currency in
                    Button {
                        selectedCurrency = currency.rawValue
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(currency.flag)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currency.rawValue)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text(currency.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(currency.symbol)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            
                            if selectedCurrency == currency.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Compact currency display for amount fields
struct CurrencySymbolView: View {
    let currencyCode: String
    
    var body: some View {
        if let currency = SupportedCurrency.from(code: currencyCode) {
            Text(currency.symbol)
                .font(.title)
                .foregroundStyle(.secondary)
        } else {
            Text(currencyCode)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Currency Picker") {
    struct PreviewWrapper: View {
        @State private var currency = "USD"
        
        var body: some View {
            Form {
                CurrencyPicker(selectedCurrency: $currency)
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Currency Button") {
    struct PreviewWrapper: View {
        @State private var currency = "EUR"
        
        var body: some View {
            VStack(spacing: 20) {
                CurrencyButton(selectedCurrency: $currency)
                Text("Selected: \(currency)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

#Preview("Currency Picker Sheet") {
    struct PreviewWrapper: View {
        @State private var currency = "GBP"
        @State private var showSheet = true
        
        var body: some View {
            Button("Show Picker") {
                showSheet = true
            }
            .sheet(isPresented: $showSheet) {
                CurrencyPickerSheet(selectedCurrency: $currency)
            }
        }
    }
    
    return PreviewWrapper()
}
