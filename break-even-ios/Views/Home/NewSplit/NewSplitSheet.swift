//
//  NewSplitSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile
import UIKit

struct NewSplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel: NewSplitViewModel
    
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    let userDefaultCurrency: String
    let receiptResult: ReceiptScanResult?
    
    // MARK: - State
    @State private var isSearchActive = false
    @State private var showPaidByPicker = false
    @State private var showError = false
    @State private var showReceiptCamera = false
    @State private var showAddItemSheet = false
    @State private var showReplaceReceiptAlert = false
    @State private var showPhotoOverlay = false
    @State private var showDeleteSplitAlert = false
    @State private var amountText: String = ""
    @FocusState private var focusedField: Field?
    @State private var isAmountFocused: Bool = false
    @State private var fixedElementsWidth: CGFloat = 0
    @State private var expandedItemIds: Set<UUID> = []
    
    private enum Field: Hashable {
        case title
    }
    
    // MARK: - Initialization
    
    init(
        receiptResult: ReceiptScanResult? = nil,
        preSelectedFriend: ConvexFriend? = nil,
        allFriends: [ConvexFriend] = [],
        selfFriend: ConvexFriend? = nil,
        userDefaultCurrency: String = "USD",
        prefilledViewModel: NewSplitViewModel? = nil
    ) {
        self.receiptResult = receiptResult
        self.allFriends = allFriends
        self.selfFriend = selfFriend
        self.userDefaultCurrency = userDefaultCurrency
        self._viewModel = State(initialValue: prefilledViewModel ?? NewSplitViewModel(preSelectedFriend: preSelectedFriend, defaultCurrency: userDefaultCurrency))
    }
    
    private var selectableFriends: [ConvexFriend] {
        allFriends.filter(\.isSelectableForNewSplit)
    }
    
    private var canEditParticipants: Bool {
        guard viewModel.isEditing, let creatorUserId = viewModel.creatorUserId else {
            return true
        }
        return creatorUserId == convexService.currentUserId
    }
    
    private var participantSelfFriend: ConvexFriend? {
        viewModel.participants.first { friend in
            friend.id == selfFriend?.id || friend.isSelf
        }
    }
    
    private var payerSelectionFriends: [ConvexFriend] {
        if canEditParticipants {
            return allFriends
        }
        let lockedSelfId = participantSelfFriend?.id
        return viewModel.participants.filter { $0.id != lockedSelfId }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            contentWithSheetsAndAlerts
        }
        .overlay { searchOverlay }
        .overlay { photoOverlay }
        .animation(.easeInOut(duration: 0.3), value: isSearchActive)
        .animation(.easeInOut(duration: 0.25), value: showPhotoOverlay)
    }
    
    private var contentWithNavigation: some View {
        mainScrollContent
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, newValue in
                if newValue != nil {
                    isAmountFocused = false
                }
            }
            .onChange(of: isAmountFocused) { _, newValue in
                if newValue {
                    focusedField = nil
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Split" : "New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaBar(edge: .bottom) {
                NewSplitBottomBar(
                    isEditing: viewModel.isEditing,
                    canDelete: canEditParticipants,
                    isValid: viewModel.isValid,
                    isLoading: viewModel.isLoading,
                    hasReceiptImage: viewModel.scannedReceiptImage != nil,
                    onSave: { saveSplit() },
                    onDelete: { showDeleteSplitAlert = true },
                    onScanReceipt: { showReceiptCamera = true },
                    onReplaceReceipt: { showReplaceReceiptAlert = true }
                )
            }
    }
    
    private var contentWithSheetsAndAlerts: some View {
        contentWithNavigation
            .sheet(isPresented: $showPaidByPicker) {
                PaidByPickerSheet(
                    allFriends: payerSelectionFriends,
                    selfFriend: canEditParticipants ? selfFriend : participantSelfFriend,
                    selectedFriend: $viewModel.paidBy,
                    onSelect: { friend in
                        if !viewModel.participants.contains(where: { $0.id == friend.id }) {
                            viewModel.addParticipant(friend)
                        }
                    }
                )
            }
            .sheet(isPresented: $showReceiptCamera) {
                ReceiptCameraView { result in handleReceiptScanned(result) }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddItemSheet(
                    currencyCode: viewModel.currency,
                    onAdd: { name, amount, quantity in
                        viewModel.addItem(name: name, amount: amount, quantity: quantity)
                    }
                )
            }
            .alert("Replace Receipt?", isPresented: $showReplaceReceiptAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Replace", role: .destructive) { showReceiptCamera = true }
            } message: {
                Text("Scanning a new receipt will replace the current receipt and all itemized items.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.error ?? "An error occurred")
            }
            .alert("Delete Split", isPresented: $showDeleteSplitAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteSplit() }
            } message: {
                Text("Are you sure you want to delete this split? This cannot be undone.")
            }
            .onAppear { setupInitialData() }
    }
    
    // MARK: - Main Content
    
    private var mainScrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                emojiTitleRow
                paidByRow
                splitMethodRow
                amountRow
                friendsSection
                
                if viewModel.scannedReceiptImage != nil {
                    receiptPreviewSection
                }
                
                if viewModel.splitMethod == .byItem {
                    ByItemSection(
                        viewModel: viewModel,
                        expandedItemIds: $expandedItemIds,
                        showAddItemSheet: $showAddItemSheet,
                        showReceiptCamera: $showReceiptCamera
                    )
                }
                
                if !viewModel.participants.isEmpty && viewModel.splitMethod != .byItem {
                    SplitBreakdownView(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
                isAmountFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(viewModel.isLoading)
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Text(viewModel.date.smartFormatted)
                .padding(.horizontal, 12)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.text)
                .overlay {
                    DatePicker(selection: $viewModel.date, in: ...Date(), displayedComponents: .date) {}
                        .labelsHidden()
                        .colorMultiply(.clear)
                }
        }
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    private var searchOverlay: some View {
        if isSearchActive && canEditParticipants {
            FriendSearchOverlay(
                availableFriends: selectableFriends,
                selectedFriends: $viewModel.participants,
                selfFriend: selfFriend,
                onDismiss: { isSearchActive = false }
            )
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    private var photoOverlay: some View {
        if showPhotoOverlay, let image = viewModel.scannedReceiptImage {
            ReceiptPhotoOverlay(
                image: image,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showPhotoOverlay = false
                    }
                },
                onDeletePhoto: {
                    withAnimation {
                        if viewModel.splitMethod == .byItem {
                            viewModel.clearReceiptPhoto()
                        } else {
                            viewModel.clearReceipt()
                        }
                    }
                },
                onScanNew: {
                    showReplaceReceiptAlert = true
                }
            )
            .transition(.opacity)
        }
    }
    
    // MARK: - Row 1: Emoji & Title
    
    private var emojiTitleRow: some View {
        HStack(spacing: 12) {
            EmojiTextField(text: $viewModel.emoji)
                .frame(width: 56, height: 56)
            
            TextField("Split Name", text: $viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.text)
                .focused($focusedField, equals: .title)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.background.secondary)
                .clipShape(Capsule())
        }
    }
    
    // MARK: - Row 2: Paid By
    
    private var paidByRow: some View {
        HStack {
            Text("Paid by")
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
            
            Spacer()
            
            Button {
                showPaidByPicker = true
            } label: {
                HStack(spacing: 6) {
                    if let payer = viewModel.paidBy {
                        FriendAvatar(friend: payer, size: 24)
                        
                        Text(payer.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.text)
                    } else {
                        Text("Select")
                            .font(.subheadline)
                            .foregroundStyle(.text.opacity(0.6))
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.text.opacity(0.6))
                }
                .padding(.leading, viewModel.paidBy == nil ? 10 : 5)
                .padding(.trailing, 10)
                .padding(.vertical, viewModel.paidBy == nil ? 8 : 5)
                .background(.background.secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Row 3: Split Method
    
    private var splitMethodRow: some View {
        SplitMethodSelector(selectedMethod: $viewModel.splitMethod)
            .frame(height: 64)
    }
    
    // MARK: - Row 4: Amount

    private let amountMinFieldWidth: CGFloat = 90
    private let amountMinSpacing: CGFloat = 24
    private let amountFieldLeadingPad: CGFloat = 2
    private let amountCursorPadding: CGFloat = 8

    private var amountRow: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxFieldWidth = max(amountMinFieldWidth, totalWidth - fixedElementsWidth - amountMinSpacing - amountFieldLeadingPad)
            let displayText = amountText.isEmpty ? "0.00" : amountText
            let textWidth = ExpandingAmountField.measuredWidth(for: displayText) + amountCursorPadding
            let fieldWidth = max(amountMinFieldWidth, min(textWidth, maxFieldWidth))

            HStack(spacing: 0) {
                Text("Total")
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Spacer(minLength: amountMinSpacing)

                CurrencyButton(selectedCurrency: $viewModel.currency)
                    .fixedSize()

                CurrencySymbolView(currencyCode: viewModel.currency)
                    .fixedSize()
                    .padding(.leading, 6)

                ExpandingAmountField(
                    text: $amountText,
                    isFocused: $isAmountFocused,
                    placeholder: "0.00",
                    fieldWidth: fieldWidth
                )
                .padding(.leading, amountFieldLeadingPad)
                .onChange(of: amountText) { _, newValue in
                    viewModel.totalAmount = Double(newValue) ?? 0
                }
            }
            .background {
                measureFixedElements
            }
        }
        .frame(height: 44)
        .padding(.vertical, 16)
    }

    private var measureFixedElements: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.title)
                .fontWeight(.medium)
                .fixedSize()

            CurrencyButton(selectedCurrency: .constant(viewModel.currency))
                .fixedSize()

            CurrencySymbolView(currencyCode: viewModel.currency)
                .fixedSize()
                .padding(.leading, 6)
        }
        .hidden()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self) { width in
            fixedElementsWidth = width
        }
    }
    
    // MARK: - Friends Section
    
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.participants.isEmpty {
                SelectedFriendsScroll(
                    friends: viewModel.participants,
                    selfFriend: participantSelfFriend ?? selfFriend,
                    canRemoveFriends: canEditParticipants,
                    onRemove: { friend in
                        viewModel.removeParticipant(friend)
                        if viewModel.paidBy?.id == friend.id {
                            viewModel.paidBy = nil
                        }
                    }
                )
                .padding(.horizontal, -20)
            }
            
            if canEditParticipants {
                FriendSearchTrigger {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSearchActive = true
                    }
                }
            } else {
                Text("Participants are fixed because this split was created by someone else.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Receipt Preview
    
    @ViewBuilder
    private var receiptPreviewSection: some View {
        if let image = viewModel.scannedReceiptImage {
            ReceiptPreviewRow(
                image: image,
                showMismatchWarning: viewModel.splitMethod == .byItem && viewModel.itemsTotalMismatch,
                itemsTotal: viewModel.itemsTotal,
                splitTotal: viewModel.totalAmount,
                currencyCode: viewModel.currency,
                onScanReceipt: { showReceiptCamera = true },
                onDeletePhoto: {
                    withAnimation {
                        if viewModel.splitMethod == .byItem {
                            viewModel.clearReceiptPhoto()
                        } else {
                            viewModel.clearReceipt()
                        }
                    }
                },
                onScanNewReceipt: {
                    showReplaceReceiptAlert = true
                },
                onTapPhoto: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showPhotoOverlay = true
                    }
                }
            )
        }
    }
    
    // MARK: - Setup
    
    private func setupInitialData() {
        if viewModel.paidBy == nil, let self_ = selfFriend {
            viewModel.paidBy = self_
        }
        
        if let self_ = selfFriend {
            let alreadyRepresented = viewModel.participants.contains { participant in
                participant.id == self_.id ||
                participant.isSelf ||
                participant.linkedUserId == self_.ownerId
            }
            if !alreadyRepresented {
                viewModel.addParticipant(self_)
            }
        }
        
        if let receipt = receiptResult {
            viewModel.replaceReceiptData(from: receipt)
        }
        
        if viewModel.totalAmount > 0 {
            amountText = String(format: "%.2f", viewModel.totalAmount)
        }
        
        if viewModel.currency.isEmpty {
            viewModel.currency = userDefaultCurrency
        }
    }
    
    // MARK: - Handle Receipt Scanned
    
    private func handleReceiptScanned(_ result: ReceiptScanResult) {
        viewModel.replaceReceiptData(from: result)
        if viewModel.totalAmount > 0 {
            amountText = String(format: "%.2f", viewModel.totalAmount)
        }
    }
    
    // MARK: - Save
    
    private func saveSplit() {
        guard let clerkId = clerk.user?.id else {
            viewModel.error = "Not authenticated"
            showError = true
            return
        }
        
        Task {
            do {
                try await viewModel.save(clerkId: clerkId)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Delete (edit mode only)
    
    private func deleteSplit() {
        guard let txId = viewModel.editingTransactionId else { return }
        
        Task {
            do {
                let _: Bool = try await convexService.client.mutation(
                    "transactions:deleteTransaction",
                    with: ["transactionId": txId]
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Previews

private enum NewSplitSheetPreviewData {
    static let selfFriend = ConvexFriend(
        _id: "self-1",
        ownerId: "owner-1",
        linkedUserId: nil,
        name: "Alex Me",
        email: "alex@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: true,
        createdAt: 0
    )

    static let friendJane = ConvexFriend(
        _id: "friend-jane",
        ownerId: "owner-1",
        linkedUserId: nil,
        name: "Jane Smith",
        email: "jane@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        createdAt: 0
    )

    static let friendBob = ConvexFriend(
        _id: "friend-bob",
        ownerId: "owner-1",
        linkedUserId: nil,
        name: "Bob Wilson",
        email: "bob@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: false,
        createdAt: 0
    )

    static let allFriends: [ConvexFriend] = [selfFriend, friendJane, friendBob]

    static func makeFilledViewModel(
        splitMethod: NewSplitMethod = .equal,
        includeReceiptImage: Bool = false,
        includeItems: Bool = false
    ) -> NewSplitViewModel {
        let vm = NewSplitViewModel(preSelectedFriend: nil, defaultCurrency: "USD")
        vm.emoji = "🍕"
        vm.title = "Dinner at Mario's"
        vm.date = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        vm.currency = "USD"
        vm.paidBy = selfFriend
        vm.participants = [selfFriend, friendJane, friendBob]
        vm.totalAmount = 87.50
        vm.splitMethod = splitMethod

        switch splitMethod {
        case .equal:
            break
        case .unequal:
            vm.customAmounts = [
                selfFriend.id: 35.00,
                friendJane.id: 27.50,
                friendBob.id: 25.00
            ]
        case .byParts:
            vm.partsPerPerson = [
                selfFriend.id: 2,
                friendJane.id: 1,
                friendBob.id: 1
            ]
        case .byItem:
            if includeItems {
                vm.items = [
                    SplitItem(name: "Margherita Pizza", amount: 18.00, assignedTo: [selfFriend.id, friendJane.id]),
                    SplitItem(name: "Caesar Salad", amount: 12.50, assignedTo: [friendJane.id]),
                    SplitItem(name: "Pasta Carbonara", amount: 22.00, assignedTo: [selfFriend.id, friendBob.id]),
                    SplitItem(name: "Tiramisu", amount: 9.00, assignedTo: Set([selfFriend.id, friendJane.id, friendBob.id]))
                ]
            }
        }

        if includeReceiptImage {
            let size = CGSize(width: 200, height: 280)
            let renderer = UIGraphicsImageRenderer(size: size)
            vm.scannedReceiptImage = renderer.image { ctx in
                UIColor.systemGray5.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.systemGray.setStroke()
                ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
            }
        }

        return vm
    }

    static var receiptResult: ReceiptScanResult {
        ReceiptScanResult(
            title: "Grocery Run",
            emoji: "🛒",
            total: 64.32,
            items: [
                SplitItem(name: "Milk", amount: 4.99, assignedTo: []),
                SplitItem(name: "Bread", amount: 3.49, assignedTo: []),
                SplitItem(name: "Eggs", amount: 5.99, assignedTo: [])
            ],
            date: "2025-02-04",
            image: nil
        )
    }
}

#Preview("Empty State") {
    NewSplitSheet(allFriends: [], selfFriend: nil, userDefaultCurrency: "USD")
        .environment(\.convexService, ConvexService.shared)
}

#Preview("All Fields – Equal Split") {
    NewSplitSheet(
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .equal)
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("All Fields – Unequal Split") {
    NewSplitSheet(
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .unequal)
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("All Fields – By Parts") {
    NewSplitSheet(
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .byParts)
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("All Fields – By Item") {
    NewSplitSheet(
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .byItem, includeItems: true)
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("With Receipt Image") {
    NewSplitSheet(
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .equal, includeReceiptImage: true)
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("With Receipt Scan Result") {
    NewSplitSheet(
        receiptResult: NewSplitSheetPreviewData.receiptResult,
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD"
    )
    .environment(\.convexService, ConvexService.shared)
}

#Preview("Pre-Selected Friend") {
    NewSplitSheet(
        preSelectedFriend: NewSplitSheetPreviewData.friendJane,
        allFriends: NewSplitSheetPreviewData.allFriends,
        selfFriend: NewSplitSheetPreviewData.selfFriend,
        userDefaultCurrency: "USD",
        prefilledViewModel: {
            let vm = NewSplitSheetPreviewData.makeFilledViewModel(splitMethod: .equal)
            vm.participants = [NewSplitSheetPreviewData.selfFriend, NewSplitSheetPreviewData.friendJane]
            return vm
        }()
    )
    .environment(\.convexService, ConvexService.shared)
}
