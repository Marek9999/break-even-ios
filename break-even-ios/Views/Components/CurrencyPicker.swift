//
//  CurrencyPicker.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-19.
//

import SwiftUI
import UIKit

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
        }
    }
}

// MARK: - Wheel Picker Configuration

/// Tweak these values to control the wheel picker appearance
private enum WheelPickerConfig {
    static let rowHeight: CGFloat = 50
    static let fontSize: CGFloat = 22
    static let flagFontSize: CGFloat = 24
    static let flagCodeSpacing: CGFloat = 8
    static let contentWidth: CGFloat = 180
}

// MARK: - UIKit Wheel Picker

struct CurrencyWheelPicker: UIViewRepresentable {
    @Binding var selection: String
    
    private let currencies = SupportedCurrency.allCases
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        if let index = currencies.firstIndex(where: { $0.rawValue == selection }) {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
        return picker
    }
    
    func updateUIView(_ picker: UIPickerView, context: Context) {
        guard let index = currencies.firstIndex(where: { $0.rawValue == selection }) else { return }
        let current = picker.selectedRow(inComponent: 0)
        if current != index {
            picker.selectRow(index, inComponent: 0, animated: true)
        }
    }
    
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        private let parent: CurrencyWheelPicker
        
        init(_ parent: CurrencyWheelPicker) {
            self.parent = parent
        }
        
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.currencies.count
        }
        
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            WheelPickerConfig.rowHeight
        }
        
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let currency = parent.currencies[row]
            
            let wrapper = (view?.tag == 999 ? view : nil) ?? {
                let outer = UIView()
                outer.tag = 999
                
                let content = UIView()
                content.tag = 200
                content.translatesAutoresizingMaskIntoConstraints = false
                
                let flagLabel = UILabel()
                flagLabel.tag = 1
                flagLabel.font = .systemFont(ofSize: WheelPickerConfig.flagFontSize)
                flagLabel.translatesAutoresizingMaskIntoConstraints = false
                flagLabel.setContentHuggingPriority(.required, for: .horizontal)
                
                let codeLabel = UILabel()
                codeLabel.tag = 2
                codeLabel.font = .systemFont(ofSize: WheelPickerConfig.fontSize, weight: .semibold)
                codeLabel.translatesAutoresizingMaskIntoConstraints = false
                codeLabel.setContentHuggingPriority(.required, for: .horizontal)
                
                let symbolLabel = UILabel()
                symbolLabel.tag = 3
                symbolLabel.font = .systemFont(ofSize: WheelPickerConfig.fontSize, weight: .medium)
                symbolLabel.textAlignment = .right
                symbolLabel.translatesAutoresizingMaskIntoConstraints = false
                symbolLabel.setContentHuggingPriority(.required, for: .horizontal)
                
                outer.addSubview(content)
                content.addSubview(flagLabel)
                content.addSubview(codeLabel)
                content.addSubview(symbolLabel)
                
                NSLayoutConstraint.activate([
                    content.centerXAnchor.constraint(equalTo: outer.centerXAnchor),
                    content.centerYAnchor.constraint(equalTo: outer.centerYAnchor),
                    content.widthAnchor.constraint(equalToConstant: WheelPickerConfig.contentWidth),
                    
                    flagLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    flagLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                    
                    codeLabel.leadingAnchor.constraint(equalTo: flagLabel.trailingAnchor, constant: WheelPickerConfig.flagCodeSpacing),
                    codeLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                    
                    symbolLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    symbolLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                ])
                
                return outer
            }()
            
            if let flagLabel = wrapper.viewWithTag(1) as? UILabel {
                flagLabel.text = currency.flag
            }
            if let codeLabel = wrapper.viewWithTag(2) as? UILabel {
                codeLabel.text = currency.rawValue
            }
            if let symbolLabel = wrapper.viewWithTag(3) as? UILabel {
                symbolLabel.text = currency.symbol
            }
            
            return wrapper
        }
        
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.selection = parent.currencies[row].rawValue
        }
    }
}

// MARK: - Currency Picker Sheet

/// Wheel-style currency picker sheet with draft-commit pattern
struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCurrency: String
    @State private var draft: String
    
    init(selectedCurrency: Binding<String>) {
        _selectedCurrency = selectedCurrency
        _draft = State(initialValue: selectedCurrency.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            CurrencyWheelPicker(selection: $draft)
                .navigationTitle("Select Currency")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Select") {
                            selectedCurrency = draft
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
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        } else {
            Text(currencyCode)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

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
            VStack(spacing: 20) {
                Text("Selected: \(currency)")
                Button("Show Picker") {
                    showSheet = true
                }
            }
            .sheet(isPresented: $showSheet) {
                CurrencyPickerSheet(selectedCurrency: $currency)
                    .presentationDetents([.medium])
            }
        }
    }
    
    return PreviewWrapper()
}
