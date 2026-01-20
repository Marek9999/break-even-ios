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
    @State private var scrollOffset: CGFloat = 0
    @State private var showSettleConfirmation = false
    @State private var isSettled = false
    @State private var shouldResetSlider = false
    @State private var isLoading = false
    
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
    
    // Filter transactions for this friend
    private var relevantTransactions: [(transaction: EnrichedTransaction, amount: Double, isOwed: Bool)] {
        transactions.compactMap { transaction in
            // Find the friend's split in this transaction
            guard let friendSplit = transaction.splits.first(where: { $0.friendId == friend.id && !$0.isSettled }) else {
                return nil
            }
            
            // Check if friend paid or user paid
            let friendPaid = transaction.paidById == friend.id
            
            if friendPaid {
                // Friend paid - find user's unsettled split
                if let userSplit = transaction.splits.first(where: { $0.friend?.isSelf == true && !$0.isSettled }) {
                    return (transaction, userSplit.amount, false) // User owes friend
                }
            } else if transaction.payer?.isSelf == true {
                // User paid - friend owes user
                return (transaction, friendSplit.amount, true)
            }
            
            return nil
        }.sorted { $0.transaction.date > $1.transaction.date }
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
                                
                                Text(displayAmount.asCurrency)
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(owedToMe ? .accent : .appDestructive)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(transitionProgress < 0.5 ? 1 : 0)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Transactions list
                    if relevantTransactions.isEmpty {
                        emptyState
                    } else {
                        transactionsList
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .bottom) {
                if displayAmount > 0 {
                    SlideToConfirmButton(
                        onSlideComplete: {
                            showSettleConfirmation = true
                        },
                        isConfirmed: $isSettled,
                        shouldReset: $shouldResetSlider
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 0)
                }
            }
            .alert(
                "Settle all \(displayAmount.asCurrency) \(owedToMe ? "from" : "to") \(friend.name)?",
                isPresented: $showSettleConfirmation
            ) {
                Button("Not Yet", role: .cancel) {
                    shouldResetSlider = true
                }
                Button("Yup") {
                    settleAllTransactions()
                }
                .keyboardShortcut(.defaultAction)
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
                loadTransactions()
            }
        }
    }
    
    // MARK: - Load Transactions
    
    private func loadTransactions() {
        guard let clerkId = clerk.user?.id else { return }
        
        Task {
            // Use subscribe + first value pattern since ConvexMobile has no query() method
            let subscription = convexService.client.subscribe(
                to: "transactions:getTransactionsWithFriend",
                with: [
                    "clerkId": clerkId,
                    "friendId": friend.id
                ],
                yielding: [EnrichedTransaction].self
            )
            .replaceError(with: [])
            .values
            
            var iterator = subscription.makeAsyncIterator()
            if let txs = await iterator.next() {
                await MainActor.run {
                    self.transactions = txs
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
    
    // MARK: - Transactions List
    
    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(relevantTransactions, id: \.transaction.id) { item in
                HStack(spacing: 10) {
                    Text(item.transaction.emoji)
                        .font(Font.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(Color.accent.opacity(0.2)
                            .cornerRadius(8))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.transaction.title)
                            .font(.default)
                            .fontWeight(.medium)
                            .foregroundStyle(.text)
                        Text(item.transaction.dateValue.shortFormatted)
                            .font(.caption)
                            .foregroundStyle(.text.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.isOwed ? "They owe" : "You owe")
                            .font(.caption)
                            .foregroundStyle(.text.opacity(0.6))
                        Text(item.amount.asCurrency)
                            .font(.default)
                            .fontWeight(.semibold)
                            .foregroundStyle(item.isOwed ? .accent : .appDestructive)
                    }
                }
                Divider()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.accentSecondary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Settle Transactions
    
    private func settleAllTransactions() {
        guard let clerkId = clerk.user?.id else { return }
        
        isLoading = true
        
        Task {
            do {
                let _: Int = try await convexService.client.mutation(
                    "transactions:settleAllWithFriend",
                    with: [
                        "clerkId": clerkId,
                        "friendId": friend.id
                    ]
                )
                
                await MainActor.run {
                    isSettled = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    shouldResetSlider = true
                    isLoading = false
                }
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
        balance: BalanceSummary(friendOwesUser: 50.0, userOwesFriend: 0, netBalance: 50.0),
        onStartSplit: { _ in }
    )
}
