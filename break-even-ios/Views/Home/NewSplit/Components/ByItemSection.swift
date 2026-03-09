//
//  ByItemSection.swift
//  break-even-ios
//
//  Standalone view for the "By Item" split method section.
//

import SwiftUI

struct ByItemSection: View {
    @Bindable var viewModel: NewSplitViewModel
    @Binding var expandedItemIds: Set<UUID>
    @Binding var showAddItemSheet: Bool
    @Binding var showReceiptCamera: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.scannedReceiptImage == nil && viewModel.itemsTotalMismatch {
                ItemsTotalMismatchBar(
                    itemsTotal: viewModel.itemsTotal,
                    splitTotal: viewModel.totalAmount,
                    currencyCode: viewModel.currency
                )
            }
            
            if !viewModel.items.isEmpty {
                columnHeaders
                itemsList
            }
            
            addItemButton
            
            if viewModel.scannedReceiptImage == nil {
                scanReceiptLink
            }
        }
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Item")
                .font(.caption)
                .foregroundStyle(.text.opacity(0.6))
            
            Spacer(minLength: 12)
            
            Text("Qty")
                .font(.caption)
                .foregroundStyle(.text.opacity(0.6))
                .frame(width: 44, alignment: .center)
            
            Text("Price")
                .font(.caption)
                .foregroundStyle(.text.opacity(0.6))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Items List

    private var itemsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                let items = viewModel.items
                let isFirst = index == 0
                let isLast = index == items.count - 1
                let isItemExpanded = expandedItemIds.contains(item.id)
                let isPrevExpanded = index > 0 && index - 1 < items.count && expandedItemIds.contains(items[index - 1].id)
                let isNextExpanded = index + 1 < items.count && expandedItemIds.contains(items[index + 1].id)
                let bottomSpacing: CGFloat = isLast ? 0 : (isItemExpanded || isNextExpanded ? 16 : 8)
                
                ExpandableItemRow(
                    item: item,
                    participants: viewModel.participants,
                    currencyCode: viewModel.currency,
                    isFirst: isFirst,
                    isLast: isLast,
                    isAboveExpanded: isPrevExpanded,
                    isBelowExpanded: isNextExpanded,
                    isExpanded: Binding(
                        get: { expandedItemIds.contains(item.id) },
                        set: { newValue in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if newValue {
                                    expandedItemIds = [item.id]
                                } else {
                                    expandedItemIds.remove(item.id)
                                }
                            }
                        }
                    ),
                    onToggleAssignment: { friend in
                        viewModel.toggleItemAssignment(item: item, friend: friend)
                    },
                    onAssignAll: {
                        viewModel.assignAllToItem(item: item)
                    },
                    onUnassignAll: {
                        viewModel.unassignAllFromItem(item: item)
                    },
                    onUpdate: { name, qty, amount in
                        viewModel.updateItem(id: item.id, name: name, quantity: qty, amount: amount)
                    },
                    onRemove: {
                        withAnimation {
                            expandedItemIds.remove(item.id)
                            viewModel.removeItem(item)
                        }
                    }
                )
                .padding(.bottom, bottomSpacing)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expandedItemIds)
    }

    // MARK: - Add Item Button

    private var addItemButton: some View {
        Button {
            showAddItemSheet = true
        } label: {
            HStack {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                Text("Add Item")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 12)
            .foregroundStyle(.text)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Scan Receipt Link

    private var scanReceiptLink: some View {
        Button {
            showReceiptCamera = true
        } label: {
            Text("Or scan a receipt")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("By Item Section") {
    let vm = NewSplitViewModel(defaultCurrency: "USD")
    vm.totalAmount = 87.50
    vm.splitMethod = .byItem
    vm.participants = [.previewSelf, .previewAlice, .previewBob]
    vm.items = [
        SplitItem(name: "Pizza", amount: 18.00, assignedTo: [ConvexFriend.previewSelf.id, ConvexFriend.previewAlice.id]),
        SplitItem(name: "Salad", amount: 12.50, assignedTo: [ConvexFriend.previewAlice.id]),
        SplitItem(name: "Pasta", amount: 22.00, assignedTo: [ConvexFriend.previewSelf.id, ConvexFriend.previewBob.id]),
    ]
    return ScrollView {
        ByItemSection(
            viewModel: vm,
            expandedItemIds: .constant([]),
            showAddItemSheet: .constant(false),
            showReceiptCamera: .constant(false)
        )
        .padding()
    }
}
#endif
