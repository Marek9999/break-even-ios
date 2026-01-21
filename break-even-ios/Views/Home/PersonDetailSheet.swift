//
//  PersonDetailSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct PersonDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    let friend: ConvexFriend
    let balance: BalanceSummary
    let onStartSplit: (ConvexFriend) -> Void
    
    @State private var transactions: [EnrichedTransaction] = []
    @State private var settlements: [EnrichedSettlement] = []
    @State private var scrollOffset: CGFloat = 0
    @State private var showSettleSheet = false
    @State private var isSettled = false
    @State private var shouldResetSlider = false
    @State private var isLoading = false
    @State private var showOlderItems = false
    
    private var transitionProgress: CGFloat {
        let progress = min(max(((scrollOffset + 74) / 74), 0), 1)
        return progress
    }
    
    private var owedToMe: Bool {
        balance.isOwedToUser
    }
    
    private var displayAmount: Double {
        balance.displayAmount
    }
    
    private var userCurrency: String {
        balance.userCurrency
    }
    
    // MARK: - Activity Items (Combined Feed)
    
    /// Combined activity feed with transactions and settlements sorted by date descending
    /// Shows ORIGINAL amounts (not remaining) - settlements in the timeline show balance changes
    private var activityItems: [ActivityItem] {
        var items: [ActivityItem] = []
        
        // Add transactions - use ORIGINAL amounts, not remaining
        for transaction in transactions {
            let friendPaid = transaction.paidById == friend.id
            let userPaid = transaction.payer?.isSelf == true
            let txCurrency = transaction.currency
            
            if userPaid {
                // User paid - look for friend's split (friend owes user)
                if let friendSplit = transaction.splits.first(where: { $0.friendId == friend.id }) {
                    let originalAmount = friendSplit.amount  // Use ORIGINAL amount
                    items.append(.transaction(transaction, originalAmount: originalAmount, originalCurrency: txCurrency, isOwed: true))
                }
            }
            
            if friendPaid {
                // Friend paid - look for user's split (user owes friend)
                if let userSplit = transaction.splits.first(where: { $0.friend?.isSelf == true }) {
                    let originalAmount = userSplit.amount  // Use ORIGINAL amount
                    items.append(.transaction(transaction, originalAmount: originalAmount, originalCurrency: txCurrency, isOwed: false))
                }
            }
        }
        
        // Add settlements
        for settlement in settlements {
            items.append(.settlement(settlement))
        }
        
        // Sort by date descending (newest first)
        return items.sorted { $0.sortTimestamp > $1.sortTimestamp }
    }
    
    /// Find the index of the last full settlement (where all older transactions are settled)
    private var lastFullSettlementIndex: Int? {
        // Find the most recent settlement that appears to have cleared everything
        // (i.e., no unsettled transactions exist before it)
        for (index, item) in activityItems.enumerated() {
            if case .settlement = item {
                // Check if all transactions after this settlement (older in time) are settled
                let olderTransactions = activityItems.suffix(from: index + 1).compactMap { item -> EnrichedTransaction? in
                    if case .transaction(let tx, _, _, _) = item { return tx }
                    return nil
                }
                
                // If all older transactions are fully settled, this was a "full" settlement point
                let allOlderSettled = olderTransactions.allSatisfy { tx in
                    let friendSplit = tx.splits.first(where: { $0.friendId == friend.id })
                    let userSplit = tx.splits.first(where: { $0.friend?.isSelf == true })
                    let friendRemaining = friendSplit?.remainingAmount ?? 0
                    let userRemaining = userSplit?.remainingAmount ?? 0
                    return friendRemaining < 0.01 && userRemaining < 0.01
                }
                
                if allOlderSettled && !olderTransactions.isEmpty {
                    return index
                }
            }
        }
        
        return nil
    }
    
    /// Items after the last full settlement (recent activity)
    private var recentItems: [ActivityItem] {
        guard let dividerIndex = lastFullSettlementIndex else {
            // No full settlement found - show all items
            return activityItems
        }
        // Return items before the full settlement index (newer items)
        return Array(activityItems.prefix(dividerIndex))
    }
    
    /// Items at and before the last full settlement (historical)
    private var olderItems: [ActivityItem] {
        guard let dividerIndex = lastFullSettlementIndex else {
            // No full settlement - no older items to show
            return []
        }
        // Return items from the full settlement index onwards (older items)
        return Array(activityItems.suffix(from: dividerIndex))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Header with avatar and amount
                    HStack(spacing: 12) {
                        if transitionProgress < 0.5 {
                            avatarView(size: 60)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(owedToMe ? "\(friend.name) owes you" : "You owe \(friend.name)")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.text.opacity(0.6))
                                
                                Text(displayAmount.asCurrency(code: userCurrency))
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(owedToMe ? .accent : .appDestructive)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(transitionProgress < 0.5 ? 1 : 0)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Activity list
                    if recentItems.isEmpty && olderItems.isEmpty {
                        emptyState
                    } else {
                        activityList
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .bottom) {
                if displayAmount > 0 {
                    SlideToConfirmButton(
                        onSlideComplete: {
                            showSettleSheet = true
                        },
                        isConfirmed: $isSettled,
                        shouldReset: $shouldResetSlider
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 0)
                }
            }
            .sheet(isPresented: $showSettleSheet, onDismiss: {
                // Reset slider if sheet was dismissed without settling
                if !isSettled {
                    shouldResetSlider = true
                }
            }) {
                SettleAmountSheet(
                    maxAmount: displayAmount,
                    currency: userCurrency,
                    friendName: friend.name,
                    isUserPaying: !owedToMe,  // If friend owes me, I'm receiving; if I owe, I'm paying
                    onSettle: { amount in
                        try await settleAmount(amount)
                    }
                )
                .presentationDetents([.medium])
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                scrollOffset = newValue
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        onStartSplit(friend)
                    }
                    .buttonStyle(.glassProminent)
                }
                ToolbarItem(placement: .principal) {
                    ZStack {
                        HStack {
                            if transitionProgress >= 0.5 {
                                avatarView(size: 36, fontSize: 14)
                            }
                            Text(friend.name)
                        }
                        .opacity(transitionProgress >= 0.5 ? 1 : 0)
                    }
                }
            }
            .animation(.smooth(duration: 0.4), value: transitionProgress > 0.5)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadActivity()
            }
        }
    }
    
    // MARK: - Load Activity
    
    private func loadActivity() {
        guard let clerkId = clerk.user?.id else { return }
        
        Task {
            // Use subscribe + first value pattern since ConvexMobile has no query() method
            let subscription = convexService.client.subscribe(
                to: "transactions:getActivityWithFriend",
                with: [
                    "clerkId": clerkId,
                    "friendId": friend.id
                ],
                yielding: ActivityWithFriendResponse.self
            )
            .replaceError(with: ActivityWithFriendResponse(transactions: [], settlements: [], userCurrency: "USD"))
            .values
            
            var iterator = subscription.makeAsyncIterator()
            if let response = await iterator.next() {
                await MainActor.run {
                    self.transactions = response.transactions
                    self.settlements = response.settlements
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("All settled up!")
                .font(.headline)
                .foregroundStyle(.text)
            
            Text("No pending transactions with \(friend.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    // MARK: - Activity List
    
    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recent items (always shown)
            ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                activityRow(for: item)
                
                if index < recentItems.count - 1 {
                    Divider()
                        .padding(.vertical, 8)
                }
            }
            
            // Show Older / Hide Older button
            if !olderItems.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showOlderItems.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showOlderItems ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(showOlderItems ? "Hide older" : "Show older")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                
                // Older items (conditionally shown)
                if showOlderItems {
                    Divider()
                        .padding(.bottom, 8)
                    
                    ForEach(Array(olderItems.enumerated()), id: \.element.id) { index, item in
                        activityRow(for: item)
                            .opacity(0.7)  // Slightly dimmed to indicate historical
                        
                        if index < olderItems.count - 1 {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.accentSecondary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Activity Row
    
    @ViewBuilder
    private func activityRow(for item: ActivityItem) -> some View {
        switch item {
        case .transaction(let tx, let originalAmount, let originalCurrency, let isOwed):
            transactionRow(transaction: tx, originalAmount: originalAmount, originalCurrency: originalCurrency, isOwed: isOwed)
            
        case .settlement(let settlement):
            settlementRow(settlement: settlement)
        }
    }
    
    private func transactionRow(transaction: EnrichedTransaction, originalAmount: Double, originalCurrency: String, isOwed: Bool) -> some View {
        let showOriginalCurrency = originalCurrency != userCurrency
        
        // Convert amount to user currency
        func convertToUserCurrency(_ amount: Double) -> Double {
            guard originalCurrency != userCurrency, let rates = transaction.exchangeRates else {
                return amount
            }
            return rates.convert(amount: amount, from: originalCurrency, to: userCurrency)
        }
        
        let convertedAmount = convertToUserCurrency(originalAmount)
        
        return HStack(spacing: 10) {
            Text(transaction.emoji)
                .font(Font.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Color.accent.opacity(0.2)
                    .cornerRadius(8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.default)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                Text(transaction.dateValue.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(isOwed ? "They owe" : "You owe")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
                
                // Amount display - show ORIGINAL amount
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // Show original currency amount if different from user's currency
                    if showOriginalCurrency {
                        Text(originalAmount.asCurrency(code: originalCurrency))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.text.opacity(0.5))
                    }
                    
                    // Main amount in user's currency
                    Text(convertedAmount.asCurrency(code: userCurrency))
                        .font(.default)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOwed ? .accent : .appDestructive)
                }
            }
        }
    }
    
    private func settlementRow(settlement: EnrichedSettlement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(settlement.isUserPaying ? "You paid" : "Received payment")
                    .font(.default)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                Text(settlement.settledAtDate.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                // Amount in user's currency with +/- prefix
                HStack(spacing: 0) {
                    Text(settlement.isUserPaying ? "-" : "+")
                    Text(settlement.formattedConvertedAmount)
                }
                .font(.default)
                .fontWeight(.semibold)
                .foregroundStyle(settlement.isUserPaying ? Color.appDestructive : Color.green)
                
                // Show "out of X" if we have the balance before settlement
                if let balanceBefore = settlement.formattedConvertedBalanceBefore {
                    Text("out of \(balanceBefore)")
                        .font(.caption)
                        .foregroundStyle(.text.opacity(0.5))
                }
            }
        }
    }
    
    // MARK: - Settle Amount
    
    /// Settle a specific amount with the friend (supports partial settlements)
    private func settleAmount(_ amount: Double) async throws {
        guard let clerkId = clerk.user?.id else {
            throw ConvexServiceError.notAuthenticated
        }
        
        // Direction: if friend owes me, they're paying me back ("from_friend")
        // If I owe them, I'm paying them ("to_friend")
        let direction = owedToMe ? "from_friend" : "to_friend"
        
        let _: SettleAmountResponse = try await convexService.client.mutation(
            "transactions:settleAmount",
            with: [
                "clerkId": clerkId,
                "friendId": friend.id,
                "amount": String(amount),
                "currency": userCurrency,
                "direction": direction
            ]
        )
        
        await MainActor.run {
            isSettled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        }
    }
    
    // MARK: - Avatar View
    
    @ViewBuilder
    private func avatarView(size: CGFloat = 40, fontSize: CGFloat = 18) -> some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView(size: size, fontSize: fontSize)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView(size: size, fontSize: fontSize)
        }
    }
    
    private func initialsView(size: CGFloat, fontSize: CGFloat) -> some View {
        Text(friend.initials)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Color.accent.opacity(0.4)), in: .circle)
    }
}

// MARK: - Slide To Confirm Button

struct SlideToConfirmButton: View {
    var label: String = "Slide to Settle"
    var onSlideComplete: () -> Void
    @Binding var isConfirmed: Bool
    @Binding var shouldReset: Bool
    
    @State private var dragOffset: CGFloat = 0
    @State private var isAtEnd = false
    
    private let height: CGFloat = 54
    private let thumbSize: CGFloat = 48
    private let padding: CGFloat = 4
    
    var body: some View {
        GeometryReader { geo in
            let maxDrag = geo.size.width - thumbSize - (padding * 2)
            let progress = min(dragOffset / maxDrag, 1.0)
            
            ZStack(alignment: .leading) {
                Text(isConfirmed ? "Confirmed" : label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isConfirmed ? Color.green : Color.accent)
                    .frame(maxWidth: .infinity)
                    .opacity(1 * progress)
                
                Text(isConfirmed ? "Confirmed" : label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - progress)
                
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.accent)
                        .padding(.trailing, 20)
                        .opacity(1 - progress)
                        .symbolEffect(.pulse)
                }
                
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Image(systemName: isConfirmed ? "checkmark" : "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isConfirmed ? Color.green : Color.accent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .offset(x: padding + dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isConfirmed && !isAtEnd else { return }
                                dragOffset = min(max(0, value.translation.width), maxDrag)
                            }
                            .onEnded { _ in
                                guard !isConfirmed && !isAtEnd else { return }
                                
                                if dragOffset > maxDrag * 0.85 {
                                    withAnimation(.spring(response: 0.3)) {
                                        dragOffset = maxDrag
                                        isAtEnd = true
                                    }
                                    onSlideComplete()
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: height + 2)
            .glassEffect(.clear.interactive().tint(isConfirmed ? Color.green.opacity(0.3) : Color.accent.opacity(0.1)))
            .onChange(of: shouldReset) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                        isAtEnd = false
                    }
                    shouldReset = false
                }
            }
            .onChange(of: isConfirmed) { _, newValue in
                if newValue {
                    UINotificationFeedbackGenerator()
                        .notificationOccurred(.success)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview {
    PersonDetailSheet(
        friend: ConvexFriend(
            _id: "test",
            ownerId: "owner",
            linkedUserId: nil,
            name: "Alice Johnson",
            email: "alice@example.com",
            phone: nil,
            avatarUrl: nil,
            isDummy: true,
            isSelf: false,
            createdAt: Date().timeIntervalSince1970 * 1000
        ),
        balance: BalanceSummary(
            friendOwesUser: 50.0,
            userOwesFriend: 0,
            netBalance: 50.0,
            userCurrency: "USD",
            balancesByCurrency: nil
        ),
        onStartSplit: { _ in }
    )
}
