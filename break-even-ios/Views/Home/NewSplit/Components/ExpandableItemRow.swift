//
//  ExpandableItemRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
    
    private struct ArrangementResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            sizes.append(size)
            
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
            totalWidth = max(totalWidth, currentX - horizontalSpacing)
            totalHeight = currentY + rowHeight
        }
        
        return ArrangementResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}

// MARK: - Overlapping Avatars

struct OverlappingAvatars: View {
    let friends: [ConvexFriend]
    let assignedIds: Set<String>
    var avatarSize: CGFloat = 28
    var maxVisible: Int = 6
    var overlapOffset: CGFloat = 0.6
    
    private var assignedFriends: [ConvexFriend] {
        friends.filter { assignedIds.contains($0.id) }
    }
    
    private var visibleFriends: [ConvexFriend] {
        Array(assignedFriends.prefix(maxVisible))
    }
    
    private var overflowCount: Int {
        max(0, assignedFriends.count - maxVisible)
    }
    
    var body: some View {
        HStack(spacing: -(avatarSize * (1 - overlapOffset))) {
            ForEach(visibleFriends, id: \.id) { friend in
                FriendAvatar(friend: friend, size: avatarSize)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(.systemBackground), lineWidth: 2)
                    }
            }
            
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: avatarSize * 0.38, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color(.systemBackground), lineWidth: 2)
                    }
            }
        }
    }
}

// MARK: - Expandable Item Row

struct ExpandableItemRow: View {
    let item: SplitItem
    let participants: [ConvexFriend]
    let currencyCode: String
    let isFirst: Bool
    let isLast: Bool
    let isAboveExpanded: Bool
    let isBelowExpanded: Bool
    @Binding var isExpanded: Bool
    let onToggleAssignment: (ConvexFriend) -> Void
    let onAssignAll: () -> Void
    let onUnassignAll: () -> Void
    let onUpdate: (String, Int, Double) -> Void
    let onRemove: () -> Void
    
    @State private var showEditSheet = false
    @State private var pendingDelete = false
    @Namespace private var namespace
    
    private var assignedCount: Int {
        item.assignedTo.count
    }
    
    private var assignedFriends: [ConvexFriend] {
        participants.filter { item.assignedTo.contains($0.id) }
    }
    
    private var shape: UnevenRoundedRectangle {
        let topRadius: CGFloat
        let bottomRadius: CGFloat
        
        if isExpanded {
            topRadius = 24
            bottomRadius = 8
        } else {
            topRadius = isFirst ? 20 : (isAboveExpanded ? 24 : 8)
            bottomRadius = isLast ? 20 : (isBelowExpanded ? 24 : 8)
        }
        
        return UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                collapsedRow
                
                if isExpanded {
                    expandedSection
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.secondary.opacity(0.6))
            .clipShape(shape)
            
            if isExpanded {
                editItemButton
                    .padding(.top, 4)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .sheet(isPresented: $showEditSheet, onDismiss: {
            if pendingDelete {
                pendingDelete = false
                onRemove()
            }
        }) {
            EditItemSheet(
                item: item,
                currencyCode: currencyCode,
                onSave: { name, qty, amount in
                    onUpdate(name, qty, amount)
                },
                onDelete: {
                    pendingDelete = true
                }
            )
        }
    }
    
    // MARK: - Collapsed Row
    
    private var collapsedRow: some View {
        Button {
            isExpanded.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                        .lineLimit(1)
                    
                    Spacer(minLength: 12)
                    
                    Text("\(item.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.text)
                        .frame(width: 44, alignment: .center)
                    
                    Text(item.totalPrice.asCurrency(code: currencyCode))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                        .frame(width: 80, alignment: .trailing)
                }
                
                assignmentSummaryRow
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Assignment Summary
    
    private var assignmentSummaryRow: some View {
        HStack {
            if isExpanded {
                Text("Who all got this?")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            } else if assignedCount > 0 {
                HStack(spacing: -(24 * 0.4)) {
                    ForEach(Array(assignedFriends.prefix(6)), id: \.id) { friend in
                        FriendAvatar(friend: friend, size: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                            }
                            .matchedGeometryEffect(id: friend.id, in: namespace)
                    }
                    
                    if assignedFriends.count > 6 {
                        Text("+\(assignedFriends.count - 6)")
                            .font(.system(size: 24 * 0.38, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                            }
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            if assignedCount > 0 {
                Text("\(assignedCount) people assigned")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            } else if !isExpanded {
                Text("no one assigned")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            }
        }
    }
    
    // MARK: - Expanded Section
    
    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(participants, id: \.id) { friend in
                    let isAssigned = item.assignedTo.contains(friend.id)
                    
                    Button {
                        onToggleAssignment(friend)
                    } label: {
                        HStack(spacing: 6) {
                            FriendAvatar(friend: friend, size: 24)
                                .matchedGeometryEffect(id: friend.id, in: namespace)
                            
                            Text(friend.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            if isAssigned {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .padding(.trailing, 10)
                        .padding(.leading, 6)
                        .padding(.vertical, 6)
                        .background(isAssigned ? Color.accent.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundStyle(isAssigned ? .text : .text)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isAssigned ? Color.text.opacity(0.1) : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                quickActionButton(label: "Everyone") {
                    onAssignAll()
                }
                
                quickActionButton(label: "No one") {
                    onUnassignAll()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Edit Item Button
    
    private var editItemButton: some View {
        Button {
            showEditSheet = true
        } label: {
            Text("Edit Item")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
                .glassEffect(.clear.interactive(), in: UnevenRoundedRectangle(topLeadingRadius: 8,bottomLeadingRadius: 24,bottomTrailingRadius: 24,topTrailingRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func quickActionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.secondary.opacity(0.1))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Item Sheet

struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let item: SplitItem
    let currencyCode: String
    let onSave: (String, Int, Double) -> Void
    let onDelete: () -> Void
    
    @State private var itemName: String
    @State private var quantity: Int
    @State private var totalPriceText: String
    
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
    
    init(item: SplitItem, currencyCode: String, onSave: @escaping (String, Int, Double) -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.currencyCode = currencyCode
        self.onSave = onSave
        self.onDelete = onDelete
        self._itemName = State(initialValue: item.name)
        self._quantity = State(initialValue: item.quantity)
        self._totalPriceText = State(initialValue: String(format: "%.2f", item.amount * Double(item.quantity)))
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
            .navigationTitle("Edit Item")
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
                        onSave(itemName.trimmingCharacters(in: .whitespaces), quantity, pricePerUnit)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isValid ? .accent : .text.opacity(0.3))
                    }
                    .disabled(!isValid)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                    }
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

// MARK: - Preview

private enum ExpandableItemPreviewData {
    static let selfFriend = ConvexFriend(
        _id: "self-1", ownerId: "owner-1", linkedUserId: nil,
        name: "Alex Me", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: true, createdAt: 0
    )
    static let friend1 = ConvexFriend(
        _id: "f-1", ownerId: "owner-1", linkedUserId: nil,
        name: "Matt W", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friend2 = ConvexFriend(
        _id: "f-2", ownerId: "owner-1", linkedUserId: nil,
        name: "Mae W", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friend3 = ConvexFriend(
        _id: "f-3", ownerId: "owner-1", linkedUserId: nil,
        name: "Rob Bo", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friend4 = ConvexFriend(
        _id: "f-4", ownerId: "owner-1", linkedUserId: nil,
        name: "Domingo Maggio", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friend5 = ConvexFriend(
        _id: "f-5", ownerId: "owner-1", linkedUserId: nil,
        name: "Pablo Ziemann", email: nil, phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    
    static let allParticipants = [selfFriend, friend1, friend2, friend3, friend4, friend5]
}

#Preview("Item List") {
    struct ItemListPreview: View {
        @State private var expandedId: UUID?
        @State private var items: [SplitItem] = [
            SplitItem(name: "Margherita Pizza", quantity: 2, amount: 14.99, assignedTo: Set(ExpandableItemPreviewData.allParticipants.prefix(3).map(\.id))),
            SplitItem(name: "Caesar Salad", amount: 9.50),
            SplitItem(name: "Garlic Bread", amount: 6.00, assignedTo: Set(ExpandableItemPreviewData.allParticipants.prefix(5).map(\.id))),
            SplitItem(name: "Tiramisu", quantity: 3, amount: 8.75, assignedTo: [ExpandableItemPreviewData.selfFriend.id]),
        ]
        
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isFirst = index == 0
                        let isLast = index == items.count - 1
                        let isExpanded = expandedId == item.id
                        let isPrevExpanded = !isFirst && expandedId == items[index - 1].id
                        let isNextExpanded = !isLast && expandedId == items[index + 1].id
                        let bottomSpacing: CGFloat = isLast ? 0 : (isExpanded || isNextExpanded ? 16 : 8)
                        
                        ExpandableItemRow(
                            item: item,
                            participants: ExpandableItemPreviewData.allParticipants,
                            currencyCode: "USD",
                            isFirst: isFirst,
                            isLast: isLast,
                            isAboveExpanded: isPrevExpanded,
                            isBelowExpanded: isNextExpanded,
                            isExpanded: Binding(
                                get: { expandedId == item.id },
                                set: { newValue in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        expandedId = newValue ? item.id : nil
                                    }
                                }
                            ),
                            onToggleAssignment: { _ in },
                            onAssignAll: {},
                            onUnassignAll: {},
                            onUpdate: { _, _, _ in },
                            onRemove: {}
                        )
                        .padding(.bottom, bottomSpacing)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expandedId)
                .padding()
            }
        }
    }
    
    return ItemListPreview()
}
