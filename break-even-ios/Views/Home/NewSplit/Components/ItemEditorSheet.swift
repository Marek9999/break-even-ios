//
//  ItemEditorSheet.swift
//  break-even-ios
//
//  Unified add/edit item sheet used by:
//    - The scan-receipt confirmation screen (InlineScanReceiptFlow)
//    - The "By Item" split section (ExpandableItemRow + AddItem button) in
//      both InlineNewSplitFlow and NewSplitSheet.
//

import SwiftUI

struct ItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// `nil` puts the sheet in "add" mode. Otherwise we are editing the
    /// supplied item.
    let initialItem: SplitItem?
    let currencyCode: String
    /// Called with `(name, quantity, unitPrice)`.
    let onSave: (String, Int, Double) -> Void
    /// Only invoked in edit mode. Pass `nil` (the default) for add mode.
    var onDelete: (() -> Void)? = nil

    @State private var name: String
    @State private var quantity: Int
    @State private var priceText: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case price
    }

    init(
        initialItem: SplitItem?,
        currencyCode: String,
        onSave: @escaping (String, Int, Double) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.initialItem = initialItem
        self.currencyCode = currencyCode
        self.onSave = onSave
        self.onDelete = onDelete
        if let initialItem {
            _name = State(initialValue: initialItem.name)
            _quantity = State(initialValue: max(1, initialItem.quantity))
            _priceText = State(initialValue: Self.formatPrice(initialItem.amount))
        } else {
            _name = State(initialValue: "")
            _quantity = State(initialValue: 1)
            _priceText = State(initialValue: "")
        }
    }

    private static func formatPrice(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private var isEditMode: Bool { initialItem != nil }

    private var navigationTitle: String { isEditMode ? "Edit Item" : "Add Item" }

    private var saveButtonLabel: String { isEditMode ? "Save" : "Add" }

    private var currencySymbol: String {
        SupportedCurrency.from(code: currencyCode)?.symbol ?? "$"
    }

    private var unitPrice: Double {
        Double(priceText) ?? 0
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && unitPrice > 0
            && quantity >= 1
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    nameRow
                    quantityRow
                    priceRow
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
            .listSectionSpacing(.compact)
            .navigationTitle(navigationTitle)
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
                    Button(saveButtonLabel) {
                        focusedField = nil
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            quantity,
                            unitPrice
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditMode, onDelete != nil {
                    deleteButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            // Drop the user straight into the most useful field for the mode.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedField = isEditMode ? nil : .name
            }
        }
    }

    // MARK: - Rows

    private var nameRow: some View {
        HStack {
            Text("Item Name")
                .foregroundStyle(.text.opacity(0.7))

            Spacer(minLength: 12)

            TextField("Item Name", text: $name)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .foregroundStyle(.text)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .price }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .name }
    }

    private var quantityRow: some View {
        HStack {
            Text("Quantity")
                .foregroundStyle(.text.opacity(0.7))

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                let isMinimum = quantity <= 1

                Button {
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.text.opacity(isMinimum ? 0.3 : 1.0))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .buttonRepeatBehavior(.enabled)
                .disabled(isMinimum)

                Text("\(quantity)")
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .monospacedDigit()
                    .frame(minWidth: 18)

                Button {
                    quantity += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.text)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .buttonRepeatBehavior(.enabled)
            }
        }
    }

    private var priceRow: some View {
        HStack {
            Text("Price")
                .foregroundStyle(.text.opacity(0.7))

            Spacer(minLength: 12)

            HStack(spacing: 1) {
                Text(currencySymbol)
                    .foregroundStyle(.text)

                TextField("0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.text)
                    .focused($focusedField, equals: .price)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .price }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete?()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                Text("Delete Item")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.red)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.15))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Edit Item") {
    ItemEditorSheet(
        initialItem: SplitItem(name: "Margherita Pizza", quantity: 2, amount: 14.99),
        currencyCode: "USD",
        onSave: { _, _, _ in },
        onDelete: { }
    )
    .preferredColorScheme(.dark)
}

#Preview("Add Item") {
    ItemEditorSheet(
        initialItem: nil,
        currencyCode: "USD",
        onSave: { _, _, _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
