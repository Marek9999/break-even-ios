//
//  NewSplitSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

struct NewSplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel: NewSplitViewModel
    
    // All available friends
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    
    // User's default currency
    let userDefaultCurrency: String
    
    // Receipt data if scanning
    let receiptResult: ReceiptScanResult?
    
    // MARK: - State
    @State private var showPersonPicker = false
    @State private var showPaidByPicker = false
    @State private var showError = false
    @State private var showReceiptCamera = false
    @State private var showAddItemSheet = false
    @State private var showReplaceReceiptAlert = false
    @State private var amountText: String = ""
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedField: Field?
    @State private var isEmojiFocused: Bool = false
    
    private enum Field: Hashable {
        case title, amount
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
    
    // Non-self friends for selection
    private var selectableFriends: [ConvexFriend] {
        allFriends.filter { !$0.isSelf }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Row 1: Emoji + Title
                    emojiTitleRow
                    
                    // Row 2: Paid By + Date
                    paidByDateRow
                    
                    // Row 3: Split Method Selector
                    splitMethodRow
                    
                    // Row 4: Currency/Amount
                    amountRow
                    
                    // Row 5: Friends Section (Search + Scroll)
                    friendsSection
                    
                    // Conditional: Receipt Preview
                    if viewModel.scannedReceiptImage != nil {
                        receiptPreviewSection
                    }
                    
                    // Conditional: Itemized List
                    if viewModel.splitMethod == .byItem && !viewModel.items.isEmpty {
                        itemizedListSection
                    }
                    
                    // Split Breakdown (for non-itemized methods)
                    if !viewModel.participants.isEmpty && viewModel.splitMethod != .byItem {
                        SplitBreakdownView(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 80) // Space for bottom bar
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    isEmojiFocused = false
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, newValue in
                if newValue != nil {
                    isEmojiFocused = false
                }
            }
            .onChange(of: isEmojiFocused) { _, newValue in
                if newValue {
                    focusedField = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showPersonPicker) {
                PersonPickerSheet(
                    friends: selectableFriends,
                    selectedFriends: $viewModel.participants,
                    onDone: { }
                )
            }
            .sheet(isPresented: $showPaidByPicker) {
                PaidByPickerSheet(
                    allFriends: allFriends,
                    selfFriend: selfFriend,
                    selectedFriend: $viewModel.paidBy,
                    onSelect: { friend in
                        // Add the payer to participants if not already included
                        if !viewModel.participants.contains(where: { $0.id == friend.id }) {
                            viewModel.addParticipant(friend)
                        }
                    }
                )
            }
            .sheet(isPresented: $showReceiptCamera) {
                ReceiptCameraView { result in
                    handleReceiptScanned(result)
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddItemSheet(
                    currencyCode: viewModel.currency,
                    onAdd: { name, amount in
                        viewModel.addItem(name: name, amount: amount)
                    }
                )
            }
            .alert("Replace Receipt?", isPresented: $showReplaceReceiptAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Replace", role: .destructive) {
                    showReceiptCamera = true
                }
            } message: {
                Text("Scanning a new receipt will replace the current receipt and all itemized items.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.error ?? "An error occurred")
            }
            .onAppear {
                setupInitialData()
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupInitialData() {
        // Set default payer to self
        if viewModel.paidBy == nil, let self_ = selfFriend {
            viewModel.paidBy = self_
        }
        
        // Add self to participants if not already
        if let self_ = selfFriend, !viewModel.participants.contains(where: { $0.id == self_.id }) {
            viewModel.addParticipant(self_)
        }
        
        // Apply receipt data if available
        if let receipt = receiptResult {
            viewModel.replaceReceiptData(from: receipt)
        }
        
        // Seed amountText from viewModel if pre-filled (e.g. from receipt or prefilled preview)
        if viewModel.totalAmount > 0 {
            amountText = String(format: "%.2f", viewModel.totalAmount)
        }
        
        // Set default currency (already set in ViewModel init, but ensure it's consistent)
        if viewModel.currency.isEmpty {
            viewModel.currency = userDefaultCurrency
        }
    }
    
    // MARK: - Handle Receipt Scanned
    
    private func handleReceiptScanned(_ result: ReceiptScanResult) {
        viewModel.replaceReceiptData(from: result)
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
    
    // MARK: - Row 1: Emoji & Title Row
    
    private var emojiTitleRow: some View {
        HStack(spacing: 12) {
            // Emoji picker
            EmojiTextField(text: $viewModel.emoji, isFocused: $isEmojiFocused)
                .frame(width: 56, height: 56)
                
            
            // Title text field
            TextField("Split Name", text: $viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.text)
                .focused($focusedField, equals: .title)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.background.secondary)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }
    
    // MARK: - Row 2: Paid By + Date Row
    
    private var paidByDateRow: some View {
        VStack(spacing: 10) {
            // Paid by label and picker
            
            Text("paid by:")
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                
                HStack(spacing: 8) {
                    Button {
                        showPaidByPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            if let payer = viewModel.paidBy {
                                PaidByAvatar(friend: payer, size: 24)
                                
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
                
                Spacer()
                
                // Date picker
                DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }
    
    // MARK: - Row 3: Split Method Selector
    
    private var splitMethodRow: some View {
        SplitMethodSelector(selectedMethod: $viewModel.splitMethod)
            .frame(height: 64)
    }
    
    // MARK: - Row 4: Amount Row
    
    private var amountRow: some View {
        HStack(spacing: 16) {
            Text("Total")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            CurrencyButton(selectedCurrency: $viewModel.currency)
            
            CurrencySymbolView(currencyCode: viewModel.currency)
                .font(.title2)
            
            TextField("0.00", text: $amountText)
                .font(.title)
                .fontWeight(.bold)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .focused($focusedField, equals: .amount)
                .onChange(of: amountText) { _, newValue in
                    viewModel.totalAmount = Double(newValue) ?? 0
                }
        }
    }
    
    // MARK: - Row 4: Friends Section
    
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Inline search
            InlineFriendSearch(
                availableFriends: selectableFriends,
                selectedFriends: $viewModel.participants
            )
            
            // Selected friends horizontal scroll
            if !viewModel.participants.isEmpty {
                SelectedFriendsScroll(
                    friends: viewModel.participants,
                    selfFriend: selfFriend,
                    onRemove: { friend in
                        viewModel.removeParticipant(friend)
                        // Clear paidBy if the removed friend was the payer
                        if viewModel.paidBy?.id == friend.id {
                            viewModel.paidBy = nil
                        }
                    },
                    onAddMore: {
                        showPersonPicker = true
                    }
                )
            }
        }
    }
    
    // MARK: - Receipt Preview Section
    
    @ViewBuilder
    private var receiptPreviewSection: some View {
        if let image = viewModel.scannedReceiptImage {
            ReceiptPreviewRow(
                image: image,
                onRemove: {
                    withAnimation {
                        viewModel.clearReceipt()
                    }
                }
            )
        }
    }
    
    // MARK: - Itemized List Section
    
    private var itemizedListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Items")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showAddItemSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            // Items list
            ForEach(viewModel.items) { item in
                ExpandableItemRow(
                    item: item,
                    participants: viewModel.participants,
                    currencyCode: viewModel.currency,
                    onToggleAssignment: { friend in
                        viewModel.toggleItemAssignment(item: item, friend: friend)
                    },
                    onRemove: {
                        withAnimation {
                            viewModel.removeItem(item)
                        }
                    }
                )
            }
            
            // Items total
            HStack {
                Text("Items Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(viewModel.itemsTotal.asCurrency(code: viewModel.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                // Scan receipt button (icon only)
                Button {
                    if viewModel.scannedReceiptImage != nil {
                        showReplaceReceiptAlert = true
                    } else {
                        showReceiptCamera = true
                    }
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.accent)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                
                // Add Split button (main action)
                Button {
                    saveSplit()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Add Split")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(viewModel.isValid ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isValid || viewModel.isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Paid By Avatar

private struct PaidByAvatar: View {
    let friend: ConvexFriend
    let size: CGFloat
    
    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

// MARK: - Add Item Sheet

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let currencyCode: String
    let onAdd: (String, Double) -> Void
    
    @State private var itemName = ""
    @State private var itemAmount: Double = 0
    
    private var isValid: Bool {
        !itemName.isEmpty && itemAmount > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $itemName)
                    
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", value: $itemAmount, format: .currency(code: currencyCode))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(itemName, itemAmount)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Paid By Picker Sheet

struct PaidByPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    @Binding var selectedFriend: ConvexFriend?
    let onSelect: (ConvexFriend) -> Void
    
    @State private var searchText = ""
    
    /// All available options including self
    private var allOptions: [ConvexFriend] {
        var options = allFriends
        if let self_ = selfFriend, !options.contains(where: { $0.id == self_.id }) {
            options.insert(self_, at: 0)
        }
        return options
    }
    
    /// Filtered options based on search
    private var filteredOptions: [ConvexFriend] {
        if searchText.isEmpty {
            return allOptions
        }
        return allOptions.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            (friend.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredOptions.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No people match \"\(searchText)\"")
                    )
                } else {
                    ForEach(filteredOptions, id: \.id) { friend in
                        Button {
                            selectedFriend = friend
                            onSelect(friend)
                            dismiss()
                        } label: {
                            HStack {
                                PaidByPickerAvatar(friend: friend, size: 36)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                        .foregroundStyle(.primary)
                                    
                                    if let email = friend.email {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedFriend?.id == friend.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("Who Paid?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Paid By Picker Avatar

private struct PaidByPickerAvatar: View {
    let friend: ConvexFriend
    let size: CGFloat
    
    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
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

