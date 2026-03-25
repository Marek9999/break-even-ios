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

typealias TransactionDetailView = SplitDetailView

struct SplitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    let transaction: EnrichedTransaction
    let userCurrency: String
    
    @State private var detailedTransaction: EnrichedTransaction?
    @State private var isLoading = false
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var showPhotoOverlay = false
    @State private var scrollOffset: CGFloat = -74
    
    // Friends data for edit flow
    @State private var allFriends: [ConvexFriend] = []
    @State private var selfFriend: ConvexFriend?
    @State private var currentUser: ConvexUser?
    @State private var friendsSubscription: Task<Void, Never>?
    @State private var currentUserSubscription: Task<Void, Never>?
    
    private var displayTransaction: EnrichedTransaction {
        detailedTransaction ?? transaction
    }
    
    private var showCurrencyConversion: Bool {
        displayTransaction.currency != userCurrency
    }
    
    private var canDeleteTransaction: Bool {
        displayTransaction.createdById == convexService.currentUserId
    }
    
    private var shareText: String {
        SplitShareTextBuilder.text(
            for: displayTransaction,
            currentUserLabel: currentUserLabel
        )
    }
    
    private var currentUserLabel: String? {
        if let username = currentUser?.displayUsername, !username.isEmpty {
            return username
        }
        
        if let name = currentUser?.name, !name.isEmpty {
            return name
        }
        
        return nil
    }
    
    private var transitionProgress: CGFloat {
        let progress = min(max(((scrollOffset + 74) / 74), 0), 1)
        return progress
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                splitTotalCard
                splitSummarySection
                
                if let receiptUrl = displayTransaction.receiptUrl,
                   let url = URL(string: receiptUrl) {
                    receiptPhotoSection(url: url)
                }
                
                if let items = displayTransaction.items, !items.isEmpty {
                    itemizedListSection(items: items)
                }
                
                editTrackingSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .overlay {
            if showPhotoOverlay,
               let receiptUrl = displayTransaction.receiptUrl,
               let url = URL(string: receiptUrl) {
                receiptPhotoOverlay(url: url)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPhotoOverlay)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(displayTransaction.emoji)
                        .font(.system(size: 18))
                    Text(displayTransaction.title)
                        .fontWeight(.semibold)
                }
                .opacity(transitionProgress >= 0.5 ? 1 : 0)
                .animation(.smooth(duration: 0.25), value: transitionProgress >= 0.5)
            }
            if canDeleteTransaction {
                ToolbarItem(id: "detail-delete", placement: .topBarTrailing) {
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.destructive)
                            .font(.subheadline)
                    }
                }
                ToolbarSpacer(placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                }
                
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                }
            }
        }
        .alert("Delete Split", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("Are you sure you want to delete this split? This cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                NewSplitSheet(
                    allFriends: allFriends,
                    selfFriend: selfFriend,
                    userDefaultCurrency: userCurrency,
                    prefilledViewModel: NewSplitViewModel(
                        from: displayTransaction,
                        allFriends: allFriends
                    )
                )
            }
        }
        .onAppear {
            loadDetails()
            subscribeToFriends()
            subscribeToCurrentUser()
        }
        .onDisappear {
            friendsSubscription?.cancel()
            currentUserSubscription?.cancel()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 14) {
            Text(displayTransaction.emoji)
                .font(.system(size: 32))
                .frame(width: 64, height: 64)
                .background(Color.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTransaction.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(displayTransaction.dateValue.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.text.opacity(0.6))
            }
        }
        .opacity(transitionProgress < 0.5 ? 1 : 0)
        .animation(.smooth(duration: 0.25), value: transitionProgress < 0.5)
        .padding(.top, 12)
    }
    
    // MARK: - Split Total Card
    
    private var splitTotalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split Total")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.text.opacity(0.6))
            
            Text(displayTransaction.formattedAmount)
                .font(.title)
                .fontWeight(.semibold)
            
            if showCurrencyConversion {
                Text(displayTransaction.formattedAmount(in: userCurrency))
                    .font(.title3)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Divider()
            
            HStack {
                Text("Paid by")
                    .foregroundStyle(.text.opacity(0.6))
                
                Spacer()
                
                HStack(spacing: 8) {
                    if let payer = displayTransaction.payer {
                        payerAvatar(payer)
                    }
                    Text(displayTransaction.payerName)
                        .fontWeight(.medium)
                }
            }
            .padding(.top, 4)
            .font(.subheadline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    // MARK: - Split Summary
    
    private var splitSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split Summary")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading)
            
            VStack(spacing: 8) {
                ForEach(Array(displayTransaction.splits.enumerated()), id: \.element.id) { index, split in
                    splitParticipantRow(split: split)
                    
                    if index < displayTransaction.splits.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.background.secondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
    
    private func splitParticipantRow(split: EnrichedSplit) -> some View {
        HStack(spacing: 12) {
            if let friend = split.friend {
                participantAvatar(friend)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
            
            Text(split.personName)
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(split.amount.asCurrency(code: displayTransaction.currency))
                    .font(.body)
                    .fontWeight(.medium)
                
                if showCurrencyConversion, let rates = displayTransaction.exchangeRates {
                    let converted = rates.convert(
                        amount: split.amount,
                        from: displayTransaction.currency,
                        to: userCurrency
                    )
                    Text(converted.asCurrency(code: userCurrency))
                        .font(.caption)
                        .foregroundStyle(.text.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Receipt Photo (matches ReceiptPreviewRow capsule style)
    
    private func receiptPhotoSection(url: URL) -> some View {
        HStack(spacing: 12) {
            Text("Receipt Photo")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.text)
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showPhotoOverlay = true
                }
            } label: {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.text.opacity(0.2), lineWidth: 1)
                        }
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay { ProgressView().scaleEffect(0.6) }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.background.secondary.opacity(0.6))
        .clipShape(Capsule())
    }
    
    // MARK: - Itemized List (matches NewSplitSheet by-item styling)
    
    private func itemizedListSection(items: [ConvexTransactionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isFirst = index == 0
                    let isLast = index == items.count - 1
                    
                    readOnlyItemRow(
                        item: item,
                        topRadius: isFirst ? 20 : 8,
                        bottomRadius: isLast ? 20 : 8
                    )
                }
            }
        }
    }
    
    private func readOnlyItemRow(
        item: ConvexTransactionItem,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> some View {
        let friends: [ConvexFriend] = item.assignedToIds.compactMap { id in
            displayTransaction.splits.first(where: { $0.friendId == id })?.friend
        }
        let assignedCount = item.assignedToIds.count
        
        return VStack(spacing: 8) {
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
                
                Text(item.totalPrice.asCurrency(code: displayTransaction.currency))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .frame(width: 80, alignment: .trailing)
            }
            
            HStack {
                if assignedCount > 0 {
                    HStack(spacing: -(24 * 0.4)) {
                        ForEach(Array(friends.prefix(6)), id: \.id) { friend in
                            FriendAvatar(friend: friend, size: 24)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color(.systemBackground), lineWidth: 2)
                                }
                        }
                        
                        if friends.count > 6 {
                            Text("+\(friends.count - 6)")
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
                
                Text(assignedCount > 0 ? "\(assignedCount) people assigned" : "no one assigned")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(.background.secondary.opacity(0.6))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: topRadius,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: topRadius
            )
        )
    }
    
    // MARK: - Edit Tracking
    
    @ViewBuilder
    private var editTrackingSection: some View {
        let editHistory = displayTransaction.enrichedEditHistory ?? []
        let hasCreator = displayTransaction.createdByName != nil
        let hasEdits = !editHistory.isEmpty
        let hasLegacyEdit = editHistory.isEmpty && displayTransaction.lastEditedByName != nil && displayTransaction.lastEditedAt != nil
        
        if hasCreator || hasEdits || hasLegacyEdit {
            VStack(spacing: 8) {
                // Show full edit history (newest first)
                ForEach(editHistory.reversed(), id: \.editedAt) { entry in
                    let editDate = Date(timeIntervalSince1970: entry.editedAt / 1000)
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.caption2)
                        Text("Edited by \(entry.editedByName) on \(editDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                // Fallback for old transactions that only have lastEditedBy/lastEditedAt
                if hasLegacyEdit,
                   let editedByName = displayTransaction.lastEditedByName,
                   let editedAt = displayTransaction.lastEditedAt {
                    let editDate = Date(timeIntervalSince1970: editedAt / 1000)
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.caption2)
                        Text("Edited by \(editedByName) on \(editDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                if let creatorName = displayTransaction.createdByName {
                    let createdDate = Date(timeIntervalSince1970: displayTransaction.createdAt / 1000)
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption2)
                        Text("Created by \(creatorName) on \(createdDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Avatar Helpers
    
    private func payerAvatar(_ friend: ConvexFriend) -> some View {
        FriendAvatar(friend: friend, size: 24)
    }
    
    private func participantAvatar(_ friend: ConvexFriend) -> some View {
        FriendAvatar(friend: friend, size: 32)
    }
    
    // MARK: - Receipt Photo Overlay (Read-Only)
    
    private func receiptPhotoOverlay(url: URL) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showPhotoOverlay = false
                    }
                }
            
            VStack(spacing: 24) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 20)
                } placeholder: {
                    ProgressView()
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadDetails() {
        Task {
            let subscription = convexService.client.subscribe(
                to: "transactions:getTransactionDetail",
                with: ["transactionId": transaction._id],
                yielding: EnrichedTransaction?.self
            )
            .replaceError(with: nil)
            .values
            
            for await detail in subscription {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.detailedTransaction = detail
                }
            }
        }
    }
    
    private func subscribeToFriends() {
        guard let clerkId = clerk.user?.id else { return }
        friendsSubscription?.cancel()
        
        friendsSubscription = Task {
            let subscription = convexService.client.subscribe(
                to: "friends:listFriends",
                with: ["clerkId": clerkId],
                yielding: [ConvexFriend].self
            )
            .replaceError(with: [])
            .values
            
            for await friends in subscription {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.allFriends = friends
                    self.selfFriend = friends.first(where: { $0.isSelf })
                }
            }
        }
    }
    
    private func subscribeToCurrentUser() {
        guard let clerkId = clerk.user?.id else { return }
        currentUserSubscription?.cancel()
        
        currentUserSubscription = Task {
            let subscription = convexService.client.subscribe(
                to: "users:getCurrentUser",
                with: ["clerkId": clerkId],
                yielding: ConvexUser?.self
            )
            .replaceError(with: nil)
            .values
            
            for await user in subscription {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.currentUser = user
                }
            }
        }
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
                #if DEBUG
                print("Failed to delete transaction: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("USD Split") {
    NavigationStack {
        SplitDetailView(
            transaction: .previewDinner,
            userCurrency: "USD"
        )
    }
}

#Preview("Foreign Currency") {
    NavigationStack {
        SplitDetailView(
            transaction: .previewEuroTrip,
            userCurrency: "USD"
        )
    }
}

#Preview("5 Participants + Receipt + Items") {
    NavigationStack {
        SplitDetailView(
            transaction: .previewFullReceipt,
            userCurrency: "CAD"
        )
    }
}

#Preview("Receipt Only") {
    NavigationStack {
        SplitDetailView(
            transaction: .previewReceiptOnly,
            userCurrency: "USD"
        )
    }
}

#Preview("Items Only") {
    NavigationStack {
        SplitDetailView(
            transaction: .previewItemsOnly,
            userCurrency: "USD"
        )
    }
}
#endif
