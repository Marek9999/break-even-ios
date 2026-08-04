//
//  InlineNewSplitFlow.swift
//  PayUp
//
//  Created by Rudra Das on 2025-04-14.
//

import SwiftUI

struct InlineNewSplitFlow: View {
    @Bindable var viewModel: NewSplitViewModel
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    var onScanReceipt: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var startsAtFriends: Bool = false
    
    @State private var step: Step
    @State private var furthestStep: Step
    @State private var amountText = ""
    @State private var keyboardInset: CGFloat = 0
    @State private var showEmojiPicker = false
    @State private var showPaidByPicker = false
    @State private var friendSearchText = ""
    @State private var expandedItemIds: Set<UUID> = []
    @State private var showAddItemSheet = false
    @State private var showReceiptOverlay = false
    @State private var showReplaceReceiptAlert = false
    @State private var showAddPersonSheet = false
    @FocusState private var focusedField: Field?
    
    private enum Step: Int, Comparable {
        case amount
        case title
        case friends
        case summary
        
        static func < (lhs: Step, rhs: Step) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    init(
        viewModel: NewSplitViewModel,
        allFriends: [ConvexFriend],
        selfFriend: ConvexFriend?,
        onScanReceipt: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil,
        startsAtFriends: Bool = false
    ) {
        self.viewModel = viewModel
        self.allFriends = allFriends
        self.selfFriend = selfFriend
        self.onScanReceipt = onScanReceipt
        self.onSave = onSave
        self.startsAtFriends = startsAtFriends
        let initialStep: Step = startsAtFriends ? .friends : .amount
        self._step = State(initialValue: initialStep)
        self._furthestStep = State(initialValue: initialStep)
    }
    
    private var hasReachedSummary: Bool {
        furthestStep == .summary
    }
    
    private enum Field: Hashable {
        case amount
        case title
        case friendSearch
    }
    
    private var currencySymbol: String {
        SupportedCurrency.from(code: viewModel.currency)?.symbol ?? "$"
    }
    
    private var formattedAmount: String {
        String(format: "%.2f", viewModel.totalAmount)
    }
    
    var body: some View {
        GeometryReader { proxy in
            Group {
                if step == .friends {
                    friendsStepLayout(in: proxy)
                } else {
                    standardStepLayout
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if step != .summary {
                confirmBar
            }
        }
        .safeAreaBar(edge: .bottom) {
            if step == .summary {
                bottomActionBar
            }
        }
        .padding(.bottom, keyboardInset)
        .sheet(isPresented: $showPaidByPicker) {
            PaidByPickerSheet(
                participants: paidByOptions,
                selectedFriend: $viewModel.paidBy
            )
        }
        .sheet(isPresented: $showAddItemSheet) {
            ItemEditorSheet(
                initialItem: nil,
                currencyCode: viewModel.currency,
                onSave: { name, quantity, amount in
                    viewModel.addItem(name: name, amount: amount, quantity: quantity)
                }
            )
        }
        .sheet(isPresented: $showAddPersonSheet, onDismiss: handleAddPersonDismiss) {
            AddPersonSheet(
                existingFriends: allFriends,
                initialPlaceholderName: friendSearchText
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCompactAdaptation(.sheet)
        }
        .alert("Replace Receipt?", isPresented: $showReplaceReceiptAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Replace", role: .destructive) { onScanReceipt?() }
        } message: {
            Text("Scanning a new receipt will replace the current receipt and all itemized items.")
        }
        .overlay {
            if showReceiptOverlay, let image = viewModel.scannedReceiptImage {
                ReceiptPhotoOverlay(
                    image: image,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showReceiptOverlay = false
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
                .zIndex(50)
            }
        }
        .onAppear {
            if amountText.isEmpty, viewModel.totalAmount > 0 {
                amountText = String(format: "%.2f", viewModel.totalAmount)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                switch step {
                case .amount:
                    focusedField = .amount
                case .title:
                    focusedField = .title
                case .friends:
                    focusedField = .friendSearch
                case .summary:
                    focusedField = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            applyKeyboardChange(notification: notification, isHiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            applyKeyboardChange(notification: notification, isHiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            applyKeyboardChange(notification: notification, isHiding: true)
        }
    }
    
    // MARK: - Confirm Bar
    
    private var canConfirmCurrentStep: Bool {
        !isCurrentStepConfirmDisabled
    }
    
    private var confirmBar: some View {
        Button {
            guard canConfirmCurrentStep else { return }
            confirmCurrentStep()
        } label: {
            Image(systemName: confirmButtonSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .clear.tint(.white.opacity(canConfirmCurrentStep ? 0.9 : 0.4)).interactive(),
            in: .circle
        )
        .allowsHitTesting(canConfirmCurrentStep)
        .padding(.trailing, 30)
        .padding(.bottom, 8)
        .zIndex(10)
    }
    
    private var confirmButtonSymbol: String {
        if hasReachedSummary { return "checkmark" }
        return step == .friends ? "checkmark" : "chevron.right"
    }
    
    // MARK: - Bottom Action Bar (Summary Step)
    
    private var canSubmitBottomActionBar: Bool {
        viewModel.isValid && !viewModel.isLoading
    }
    
    private var bottomActionBar: some View {
        Button {
            guard canSubmitBottomActionBar else { return }
            triggerHaptic(.medium)
            onSave?()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add Split")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .clipShape(Capsule())
            .glassEffect(.clear.tint(.white.opacity(canSubmitBottomActionBar ? 0.9 : 0.4)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canSubmitBottomActionBar)
        .padding(.vertical, 12)
    }
    
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    // MARK: - Collapsed Header Stack
    
    private var collapsedHeaderStack: some View {
        VStack(spacing: 18) {
            if step != .amount {
                amountCollapsed
                    .transition(.collapsedRise)
            }
            if step == .friends || step == .summary {
                titleCollapsed
                    .transition(.collapsedRise)
            }
        }
    }
    
    // MARK: - Layout per step
    
    /// Used for the amount, title, and summary steps. The friends step has its
    /// own layout (`friendsStepLayout`) so it can keep the header chips
    /// scrollable when the friend list pushes them up.
    private var standardStepLayout: some View {
        VStack(spacing: 0) {
            collapsedHeaderStack
                .padding(.horizontal, 30)
                .padding(.top, 8)
            
            activeArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    /// On the friends step we wrap the collapsed amount/title chips together
    /// with the selected-friend chips and the "Add Friends" input in a single
    /// bounded ScrollView. As the user adds more people the chip block can
    /// scroll vertically but the total/title rows are always reachable.
    private func friendsStepLayout(in proxy: GeometryProxy) -> some View {
        let maxHeaderHeight = proxy.size.height * 0.45
        return VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        collapsedHeaderStack
                            .padding(.horizontal, 30)
                            .padding(.top, 8)
                        
                        friendChipsAndInput
                            .padding(.horizontal, 24)
                            .id("chipsBlock")
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: maxHeaderHeight)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.never)
                .onChange(of: viewModel.participants.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("chipsBlock", anchor: .bottom)
                    }
                }
            }
            
            friendList
                .padding(.top, 4)
                .frame(maxHeight: .infinity)
        }
        .transition(.editableSwap)
    }
    
    // MARK: - Active Area (used by standardStepLayout)
    
    @ViewBuilder
    private var activeArea: some View {
        switch step {
        case .amount:
            amountEditable
                .padding(.horizontal, 30)
                .transition(.editableSwap)
        case .title:
            titleEditable
                .padding(.horizontal, 30)
                .transition(.editableSwap)
        case .friends:
            // Friends has its own top-level layout; this branch should never be
            // reached because `body` switches to `friendsStepLayout` for it.
            EmptyView()
        case .summary:
            summaryArea
                .padding(.top, 18)
                .transition(.editableSwap)
        }
    }
    
    // MARK: - Amount (editable + collapsed)
    
    private var amountEditable: some View {
        VStack(spacing: 14) {
            Text("Total")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.appText.opacity(0.58))
            
            CurrencyButton(selectedCurrency: $viewModel.currency)
                .scaleEffect(0.94)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currencySymbol)
                    .opacity(0.6)
                
                TextField(
                    "",
                    text: $amountText,
                    prompt: Text("0.00")
                        .foregroundStyle(Color.appText.opacity(0.32))
                )
                .focused($focusedField, equals: .amount)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 48, weight: .bold))
            .foregroundStyle(Color.appText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: amountText) { _, newValue in
            let sanitized = sanitizedAmountText(newValue)
            if sanitized != newValue {
                amountText = sanitized
                return
            }
            viewModel.totalAmount = Double(sanitized) ?? 0
        }
    }
    
    /// In By-item mode the total row is never tappable — the user must change
    /// the items to change the total.
    private var isTotalLocked: Bool {
        viewModel.splitMethod == .byItem
    }
    
    /// We only dim the total when it's locked AND not yet driving the split,
    /// which is the case when the user manually switches to By-item before
    /// adding any items. Once an item exists (or right after a receipt scan,
    /// where items are always present) the total is the actual split total, so
    /// it stays at full opacity even though the row is still locked.
    private var isTotalDimmed: Bool {
        isTotalLocked && viewModel.items.isEmpty
    }
    
    private var totalLockedHint: String {
        viewModel.items.isEmpty
            ? "Add items below to set the total."
            : "Total is calculated from the items below."
    }
    
    private var amountCollapsed: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                Text("Total")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.appText.opacity(0.58))
                
                Spacer()
                
                HStack(spacing: 0) {
                    Text(currencySymbol)
                        .opacity(0.6)
                    Text(formattedAmount)
                }
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.appText)
                .opacity(isTotalDimmed ? 0.45 : 1)
            }
            
            if isTotalLocked {
                Text(totalLockedHint)
                    .font(.caption2)
                    .foregroundStyle(Color.appText.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isTotalLocked else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            editAmount()
        }
    }
    
    // MARK: - Title (editable + collapsed)
    
    private var titleEditable: some View {
        VStack(spacing: 14) {
            emojiButton(font: .system(size: 56), boxSize: 72)
            
            TextField(
                "",
                text: $viewModel.title,
                prompt: Text("Split title")
                    .foregroundStyle(Color.appText.opacity(0.32))
            )
            .focused($focusedField, equals: .title)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color.appText)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var titleCollapsed: some View {
        HStack(spacing: 12) {
            Text("Title")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.appText.opacity(0.58))
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(viewModel.emoji.isEmpty ? "🍗" : viewModel.emoji)
                    .font(.system(size: 22))
                    .opacity(viewModel.emoji.isEmpty ? 0.45 : 1)
                
                Text(viewModel.title.isEmpty ? "Untitled" : viewModel.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editTitle()
        }
    }
    
    private func emojiButton(font: Font, boxSize: CGFloat) -> some View {
        Button {
            showEmojiPicker = true
        } label: {
            Text(viewModel.emoji.isEmpty ? "🍗" : viewModel.emoji)
                .font(font)
                .opacity(viewModel.emoji.isEmpty ? 0.45 : 1)
                .frame(width: boxSize, height: boxSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(
                selectedEmoji: Binding(
                    get: { viewModel.emoji },
                    set: { viewModel.selectEmoji($0) }
                )
            )
            .presentationCompactAdaptation(.popover)
        }
    }
    
    // MARK: - Friends Area
    
    /// Used by `standardStepLayout` for steps OTHER than `.friends`. The friends
    /// step has its own layout (`friendsStepLayout`) that wraps the header +
    /// chips in a bounded ScrollView so adding people doesn't push the
    /// total/title chips off-screen.
    private var friendsArea: some View {
        VStack(spacing: 0) {
            friendChipsAndInput
                .padding(.horizontal, 24)
            
            friendList
                .padding(.top, 4)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var friendChipsAndInput: some View {
        WrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8, alignment: .center) {
            if let selfFriend {
                friendChip(selfFriend, isRemovable: false)
            }
            
            ForEach(selectedNonSelfFriends, id: \.id) { friend in
                friendChip(friend, isRemovable: true)
            }
            
            TextField(
                "",
                text: $friendSearchText,
                prompt: Text("Add Friends")
                    .foregroundStyle(Color.appText.opacity(0.32))
            )
            .focused($focusedField, equals: .friendSearch)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .multilineTextAlignment(.leading)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Color.appText)
            .frame(minWidth: 140)
            .frame(height: 36)
        }
    }
    
    private func friendChip(_ friend: ConvexFriend, isRemovable: Bool) -> some View {
        HStack(spacing: 6) {
            FriendAvatar(friend: friend, size: 24)
            
            Text(friend.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(Color.appText)
            
            if isRemovable {
                Button {
                    removeFriend(friend)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appText.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, isRemovable ? 8 : 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
    
    private var friendList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleFriends, id: \.id) { friend in
                    friendListRow(friend)
                    
                    if friend.id != visibleFriends.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 76)
                    }
                }

                addNewFriendButton
                    .padding(.horizontal, 24)
                    .padding(.top, visibleFriends.isEmpty ? 8 : 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.never)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.15),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Glass button at the bottom of the friend list that opens `AddPersonSheet`
    /// so the user can add someone who isn't in their contacts yet without
    /// leaving the new-split flow. Styled to match `byItemAddItemButton`.
    private var addNewFriendButton: some View {
        Button {
            triggerHaptic(.light)
            focusedField = nil
            showAddPersonSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.body.weight(.medium))
                Text(addNewFriendTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
            .foregroundStyle(Color.appText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    private var addNewFriendTitle: String {
        let trimmed = friendSearchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Add new friend"
        }
        return "Add \"\(trimmed)\" as a new friend"
    }

    private func handleAddPersonDismiss() {
        // Keep `friendSearchText` as-is — if a placeholder was created with that
        // name it'll still match the filter and surface in the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedField = .friendSearch
        }
    }
    
    private func friendListRow(_ friend: ConvexFriend) -> some View {
        Button {
            addFriend(friend)
        } label: {
            HStack(spacing: 14) {
                FriendAvatar(friend: friend, size: 40)
                
                Text(friend.displayName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.appText)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Summary Area
    
    private var summaryArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                summaryFriendChipsList
                    .padding(.horizontal, 24)
                
                paidByRow
                    .padding(.horizontal, 30)
                
                Divider()
                    .background(Color.white.opacity(0.12))
                    .padding(.horizontal, 30)
                
                SplitMethodSelector(selectedMethod: $viewModel.splitMethod)
                    .frame(height: 64)
                    .padding(.horizontal, 20)
                
                breakdownContent
                    .padding(.horizontal, 30)
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.85), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)
        }
    }
    
    private var summaryFriendChipsList: some View {
        WrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8, alignment: .leading) {
            if let selfFriend {
                friendChip(selfFriend, isRemovable: false)
            }
            
            ForEach(selectedNonSelfFriends, id: \.id) { friend in
                friendChip(friend, isRemovable: true)
            }
            
            addFriendsChip
        }
    }
    
    /// Lets the user jump back to the friends step from the summary to add
    /// more people without having to remove anyone first.
    private var addFriendsChip: some View {
        Button {
            editFriends()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText.opacity(0.75))
                    .frame(width: 24, height: 24)
                
                Text("Add Friends")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.appText.opacity(0.75))
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private var paidByRow: some View {
        HStack {
            Text("Paid by")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.appText.opacity(0.58))
            
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
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Select")
                            .font(.subheadline)
                            .foregroundStyle(Color.appText.opacity(0.6))
                    }
                }
                .padding(.leading, viewModel.paidBy == nil ? 12 : 5)
                .padding(.trailing, 12)
                .padding(.vertical, viewModel.paidBy == nil ? 8 : 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var breakdownContent: some View {
        if viewModel.splitMethod == .byItem {
            byItemContent
        } else if !viewModel.participants.isEmpty {
            SplitBreakdownView(viewModel: viewModel)
        }
    }
    
    // MARK: - By-Item Content
    
    private var byItemContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            byItemReceiptHeaderRow
            
            if !viewModel.items.isEmpty {
                byItemColumnHeaders
                byItemList
            }
            
            byItemAddItemButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var byItemReceiptHeaderRow: some View {
        if let image = viewModel.scannedReceiptImage {
            HStack(spacing: 12) {
                Text("Your Receipt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appText)
                
                Spacer(minLength: 12)
                
                Button {
                    triggerHaptic(.light)
                    showReceiptOverlay = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.appText.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 12) {
                Text("Scan a receipt to add items")
                    .font(.subheadline)
                    .foregroundStyle(Color.appText.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Spacer(minLength: 8)
                
                Button {
                    triggerHaptic(.light)
                    onScanReceipt?()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var byItemColumnHeaders: some View {
        HStack(spacing: 0) {
            Text("Item")
                .font(.caption)
                .foregroundStyle(Color.appText.opacity(0.6))
            
            Spacer(minLength: 12)
            
            Text("Qty")
                .font(.caption)
                .foregroundStyle(Color.appText.opacity(0.6))
                .frame(width: 44, alignment: .center)
            
            Text("Price")
                .font(.caption)
                .foregroundStyle(Color.appText.opacity(0.6))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
    
    private var byItemList: some View {
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
    
    private var byItemAddItemButton: some View {
        Button {
            triggerHaptic(.light)
            showAddItemSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                Text("Add Item")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 12)
            .foregroundStyle(Color.appText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }
    
    // MARK: - Friend Filtering
    
    private var selectedNonSelfFriends: [ConvexFriend] {
        viewModel.participants.filter { friend in
            !friend.isSelf && friend.id != selfFriend?.id
        }
    }
    
    /// Candidate payers for the wheel picker: self first (so the picker
    /// always opens with self pre-selected when no payer has been picked)
    /// followed by every non-self friend currently in the split.
    private var paidByOptions: [ConvexFriend] {
        var options: [ConvexFriend] = []
        var seenIds: Set<String> = []
        if let selfFriend {
            options.append(selfFriend)
            seenIds.insert(selfFriend.id)
        }
        for friend in selectedNonSelfFriends where !seenIds.contains(friend.id) {
            options.append(friend)
            seenIds.insert(friend.id)
        }
        return options
    }
    
    private var availableFriends: [ConvexFriend] {
        let selectedIds = Set(viewModel.participants.map { $0.id })
        return allFriends.filter { friend in
            friend.isSelectableForNewSplit &&
            friend.id != selfFriend?.id &&
            !selectedIds.contains(friend.id)
        }
    }
    
    private var visibleFriends: [ConvexFriend] {
        let trimmed = friendSearchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return availableFriends
        }
        return availableFriends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(trimmed) ||
            (friend.email?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
    
    // MARK: - Actions
    
    private func confirmCurrentStep() {
        guard !isCurrentStepConfirmDisabled else { return }
        if hasReachedSummary {
            jumpToSummary()
            return
        }
        switch step {
        case .amount:
            confirmAmount()
        case .title:
            confirmTitle()
        case .friends:
            confirmFriends()
        case .summary:
            break
        }
    }
    
    private var isCurrentStepConfirmDisabled: Bool {
        switch step {
        case .amount:
            return viewModel.totalAmount <= 0
        case .title:
            return viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty
        case .friends:
            return selectedNonSelfFriends.isEmpty
        case .summary:
            return true
        }
    }
    
    private func advanceFurthest(to newStep: Step) {
        if newStep > furthestStep {
            furthestStep = newStep
        }
    }
    
    private func confirmAmount() {
        guard viewModel.totalAmount > 0 else { return }
        focusedField = .title
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .title
        }
        advanceFurthest(to: .title)
    }
    
    private func confirmTitle() {
        guard !viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focusedField = .friendSearch
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .friends
        }
        advanceFurthest(to: .friends)
    }
    
    private func confirmFriends() {
        guard !selectedNonSelfFriends.isEmpty else { return }
        jumpToSummary()
    }
    
    private func jumpToSummary() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        friendSearchText = ""
        if viewModel.paidBy == nil, let selfFriend {
            viewModel.paidBy = selfFriend
        }
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .summary
        }
        advanceFurthest(to: .summary)
    }
    
    private func editAmount() {
        triggerHaptic(.light)
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .amount
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            focusedField = .amount
        }
    }
    
    private func editTitle() {
        triggerHaptic(.light)
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .title
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            focusedField = .title
        }
    }
    
    private func editFriends() {
        triggerHaptic(.light)
        withAnimation(.spring(duration: 0.4, bounce: 0)) {
            step = .friends
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            focusedField = .friendSearch
        }
    }
    
    private func addFriend(_ friend: ConvexFriend) {
        guard !viewModel.participants.contains(where: { $0.id == friend.id }) else { return }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            viewModel.participants.append(friend)
            friendSearchText = ""
        }
        focusedField = .friendSearch
    }
    
    private func removeFriend(_ friend: ConvexFriend) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.spring(duration: 0.32, bounce: 0.1)) {
            viewModel.removeParticipant(friend)
            if viewModel.paidBy?.id == friend.id {
                viewModel.paidBy = selfFriend ?? viewModel.participants.first
            }
        }
        focusedField = .friendSearch
    }
    
    // MARK: - Keyboard Avoidance
    
    private func applyKeyboardChange(notification: Notification, isHiding: Bool) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
        let target: CGFloat
        if isHiding {
            target = 0
        } else if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            target = frame.height
        } else {
            return
        }
        let animation: Animation = (UIView.AnimationCurve(rawValue: curveValue) == .linear)
            ? .linear(duration: duration)
            : .easeOut(duration: duration)
        withAnimation(animation) {
            keyboardInset = target
        }
    }
    
    // MARK: - Helpers
    
    private func sanitizedAmountText(_ value: String) -> String {
        let localeSeparator = Locale.current.decimalSeparator ?? "."
        var result = ""
        var hasSeparator = false
        var fractionDigits = 0
        
        for character in value {
            if character.isNumber {
                if hasSeparator {
                    guard fractionDigits < 2 else { continue }
                    fractionDigits += 1
                }
                result.append(character)
                continue
            }
            
            if String(character) == localeSeparator || character == "." || character == "," {
                guard !hasSeparator else { continue }
                hasSeparator = true
                if result.isEmpty {
                    result = "0"
                }
                result.append(localeSeparator)
            }
        }
        
        return result
    }
}

// MARK: - Wrapping Flow Layout

/// Wrapping flow layout used by the friend chips + input field. Lays subviews
/// left-to-right, wrapping to a new row when there isn't enough horizontal
/// space. Supports leading, center, or trailing row alignment.
private struct WrappingFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowStart: CGFloat = {
                switch alignment {
                case .center:
                    return bounds.minX + max(0, (bounds.width - row.width) / 2)
                case .trailing:
                    return bounds.minX + max(0, bounds.width - row.width)
                default:
                    return bounds.minX
                }
            }()
            
            var x = rowStart
            for entry in row.entries {
                let size = entry.size
                let yOffset = (row.height - size.height) / 2
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }
    
    private struct RowEntry {
        let index: Int
        let size: CGSize
    }
    
    private struct Row {
        var entries: [RowEntry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    
    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projectedWidth = current.entries.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if !current.entries.isEmpty && projectedWidth > maxWidth {
                rows.append(current)
                current = Row()
            }
            if current.entries.isEmpty {
                current.width = size.width
            } else {
                current.width += horizontalSpacing + size.width
            }
            current.height = max(current.height, size.height)
            current.entries.append(RowEntry(index: index, size: size))
        }
        if !current.entries.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Step Transitions

private extension AnyTransition {
    /// The active editable view fades + blurs upward on exit, and rises in from
    /// slightly below with a blur fade on entry.
    static var editableSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 14))
                .combined(with: .modifier(active: BlurAmount(radius: 6), identity: BlurAmount(radius: 0))),
            removal: .opacity
                .combined(with: .offset(y: -14))
                .combined(with: .modifier(active: BlurAmount(radius: 6), identity: BlurAmount(radius: 0)))
        )
    }
    
    /// A collapsed header rises into place from slightly below with a blur fade.
    /// Removal is a simple blur fade (we don't currently navigate backward, but
    /// keep it graceful in case we do).
    static var collapsedRise: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 14))
                .combined(with: .modifier(active: BlurAmount(radius: 6), identity: BlurAmount(radius: 0))),
            removal: .opacity
                .combined(with: .modifier(active: BlurAmount(radius: 4), identity: BlurAmount(radius: 0)))
        )
    }
}

private struct BlurAmount: ViewModifier {
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
