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

// MARK: - Dominant Color Extractor

extension UIImage {
    /// Extracts the dominant color from an image by downsampling and analyzing pixel data
    func dominantColor() -> Color? {
        // Downsample to 10x10 for performance
        let size = CGSize(width: 10, height: 10)
        
        guard let cgImage = self.cgImage else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: Int(size.width * size.height * 4))
        
        guard let context = CGContext(
            data: &rawData,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        // Count color occurrences (quantize to reduce unique colors)
        var colorCounts: [UInt32: Int] = [:]
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            let a = rawData[i + 3]
            
            // Skip transparent or nearly white/black pixels
            guard a > 128 else { continue }
            let brightness = (Int(r) + Int(g) + Int(b)) / 3
            guard brightness > 30 && brightness < 225 else { continue }
            
            // Quantize to reduce unique colors (divide by 16 = shift right 4)
            let quantizedR = (r >> 4) << 4
            let quantizedG = (g >> 4) << 4
            let quantizedB = (b >> 4) << 4
            
            let key = (UInt32(quantizedR) << 16) | (UInt32(quantizedG) << 8) | UInt32(quantizedB)
            colorCounts[key, default: 0] += 1
        }
        
        // Find most common color
        guard let dominantKey = colorCounts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        
        let r = CGFloat((dominantKey >> 16) & 0xFF) / 255.0
        let g = CGFloat((dominantKey >> 8) & 0xFF) / 255.0
        let b = CGFloat(dominantKey & 0xFF) / 255.0
        
        // --- VIBRANCY BOOST ---
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        
        uiColor.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        
        // 1. Boost Saturation: Ensure it's at least 60% saturated
        let vibrantS = max(s * 1.5, 0.6)
        
        // 2. Adjust Brightness: Ensure it's not too dark (at least 50% bright)
        let vibrantBr = max(br, 0.5)
        
        return Color(hue: Double(h), saturation: Double(vibrantS), brightness: Double(vibrantBr))
    }
}

struct PersonDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    let friend: ConvexFriend
    let balance: BalanceSummary
    let onStartSplit: (ConvexFriend) -> Void
    
    @State private var transactions: [EnrichedTransaction] = []
    @State private var settlements: [EnrichedSettlement] = []
    @State private var scrollOffset: CGFloat = -74
    @State private var isLoading = false
    @State private var showOlderItems = false
    @State private var dominantColor: Color?
    @State private var cachedAvatarImage: UIImage?
    @Namespace private var olderItemsNamespace
    
    // Keyboard pre-warming
    @State private var keyboardPrewarmText = ""
    @FocusState private var keyboardPrewarmFocused: Bool
    
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
    
    /// Current user's display name from Clerk
    private var currentUserName: String {
        if let user = clerk.user {
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            let fullName = [firstName, lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return fullName.isEmpty ? "Me" : fullName
        }
        return "Me"
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
    
    /// Find the index of the last full settlement (where balance was cleared to zero)
    private var lastFullSettlementIndex: Int? {
        // Find the most recent settlement that cleared the balance (amount ≈ balanceBeforeSettlement)
        for (index, item) in activityItems.enumerated() {
            if case .settlement(let settlement) = item {
                // A "full settlement" is when the amount equals (or nearly equals) the balance before
                // This means the debt was completely paid off at that point
                if let balanceBefore = settlement.convertedBalanceBefore,
                   abs(settlement.convertedAmount - balanceBefore) < 0.01 {
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
    
    // MARK: - Activity Chunk (for grouped rendering)
    
    /// Represents a group of consecutive items for rendering
    /// Transaction groups get accent background, settlements appear plain
    private enum ActivityChunk: Identifiable {
        case transactionGroup([ActivityItem])  // Consecutive transactions
        case settlement(EnrichedSettlement)    // Single settlement
        
        var id: String {
            switch self {
            case .transactionGroup(let items):
                return "group-\(items.first?.id ?? UUID().uuidString)"
            case .settlement(let s):
                return "settlement-\(s.id)"
            }
        }
    }
    
    /// Groups consecutive transactions together, settlements become their own chunks
    private func chunkActivityItems(_ items: [ActivityItem]) -> [ActivityChunk] {
        var chunks: [ActivityChunk] = []
        var currentTransactionGroup: [ActivityItem] = []
        
        for item in items {
            switch item {
            case .transaction:
                currentTransactionGroup.append(item)
            case .settlement(let settlement):
                // Flush current transaction group if any
                if !currentTransactionGroup.isEmpty {
                    chunks.append(.transactionGroup(currentTransactionGroup))
                    currentTransactionGroup = []
                }
                chunks.append(.settlement(settlement))
            }
        }
        
        // Flush remaining transactions
        if !currentTransactionGroup.isEmpty {
            chunks.append(.transactionGroup(currentTransactionGroup))
        }
        
        return chunks
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Header with avatar and amount
                    HStack(spacing: 12) {
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
                    }
                    .opacity(transitionProgress < 0.5 ? 1 : 0)
                    .animation(.smooth(duration: 0.25), value: transitionProgress < 0.5)
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
                    NavigationLink {
                        SettleView(
                            friend: friend,
                            userName: currentUserName,
                            userAvatarUrl: clerk.user?.imageUrl,
                            maxAmount: displayAmount,
                            currency: userCurrency,
                            isUserPaying: !owedToMe,
                            onSettle: { amount, date in
                                try await settleAmount(amount: amount, date: date)
                            }
                        )
                    } label: {
                        Text("Settle with \(friend.name.components(separatedBy: " ").first ?? friend.name)")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 0)
                }
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
                    HStack(spacing: 8) {
                        avatarView(size: 36, fontSize: 14)
                        Text(friend.name)
                    }
                    .opacity(transitionProgress >= 0.5 ? 1 : 0)
                    .animation(.smooth(duration: 0.25), value: transitionProgress >= 0.5)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadActivity()
                // Pre-warm keyboard system to avoid first-use lag
                prewarmKeyboard()
            }
            .background {
                // Hidden TextField for keyboard pre-warming
                TextField("", text: $keyboardPrewarmText)
                    .focused($keyboardPrewarmFocused)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
            .onChange(of: friend.id) { _, _ in
                // Reset dominant color and cached image when friend changes
                dominantColor = nil
                cachedAvatarImage = nil
            }
        }
        .overlay(alignment: .top) {
            if let color = dominantColor {
                LinearGradient(
                    colors: [color.opacity(0.35), color.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
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
    
    // MARK: - Keyboard Pre-warming
    
    /// Pre-warm the keyboard system to avoid first-use lag
    private func prewarmKeyboard() {
        // Brief focus/unfocus cycle to initialize keyboard system
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            keyboardPrewarmFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                keyboardPrewarmFocused = false
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
        let recentChunks = chunkActivityItems(recentItems)
        let olderChunks = chunkActivityItems(olderItems)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Recent chunks
            ForEach(recentChunks) { chunk in
                chunkView(for: chunk)
            }
            
            // Show Older button (outside accent VStack)
            if !olderItems.isEmpty {
                showOlderButton
            }
            
            // Older chunks (conditionally shown)
            if showOlderItems {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(olderChunks) { chunk in
                        chunkView(for: chunk)
                            .opacity(0.7)
                    }
                }
                .transition(.offset(y: -20).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Chunk View
    
    @ViewBuilder
    private func chunkView(for chunk: ActivityChunk) -> some View {
        switch chunk {
        case .transactionGroup(let items):
            transactionGroupView(items: items)
        case .settlement(let settlement):
            settlementRow(settlement: settlement)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
    }
    
    // MARK: - Transaction Group View
    
    @ViewBuilder
    private func transactionGroupView(items: [ActivityItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                activityRow(for: item)
                
                if index < items.count - 1 {
                    Divider()
                        .padding(.vertical, 16)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.accentSecondary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Show Older Button
    
    private var showOlderButton: some View {
        Button(action: {
            withAnimation(.smooth(duration: 0.4)) {
                showOlderItems.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Text(showOlderItems ? "Hide older" : "Show older")
                    .font(.subheadline)
                    .contentTransition(.interpolate)
                Image(systemName: showOlderItems ? "chevron.up" : "chevron.down")
                    .font(.subheadline)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "olderItemsToggle", in: olderItemsNamespace)
    }
    
    // MARK: - Activity Row
    
    @ViewBuilder
    private func activityRow(for item: ActivityItem) -> some View {
        switch item {
        case .transaction(let tx, let originalAmount, let originalCurrency, let isOwed):
            NavigationLink {
                SplitDetailView(transaction: tx, userCurrency: userCurrency)
            } label: {
                transactionRow(transaction: tx, originalAmount: originalAmount, originalCurrency: originalCurrency, isOwed: isOwed)
            }
            .buttonStyle(.plain)
            
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.title)
                    .font(.default)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                Text(transaction.dateValue.smartFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                
                // Amount display - show ORIGINAL amount
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    
                    // Main amount in user's currency
                    Text(convertedAmount.asCurrency(code: userCurrency))
                        .font(.default)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOwed ? .accent : .appDestructive)
                    
                    Image(systemName: isOwed ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 14))
                        .foregroundStyle(isOwed ? Color.accent : Color.destructive)
                        .frame(width: 17, height: 17)
                }
                
                // Show original currency amount if different from user's currency
                if showOriginalCurrency {
                    Text(originalAmount.asCurrency(code: originalCurrency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text.opacity(0.5))
                }
            }
        }
        .contentShape(Rectangle())
    }
    
    private func settlementRow(settlement: EnrichedSettlement) -> some View {
        HStack(spacing: 4) {
            Image(systemName: settlement.isUserPaying ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 14))
                .foregroundStyle(settlement.isUserPaying ? Color.destructive : Color.accent)
                .frame(width: 24, height: 24)
            HStack(spacing: 0) {
                Text(settlement.isUserPaying ? "-" : "+")
                Text(settlement.formattedConvertedAmount)
            }
            .font(.default)
            .fontWeight(.medium)
            .foregroundStyle(settlement.isUserPaying ? Color.appDestructive : Color.accent)
            if let balanceBefore = settlement.formattedConvertedBalanceBefore {
                Text("out of \(balanceBefore)")
                    .font(.default)
                    .foregroundStyle(.text.opacity(0.6))
            }
            Spacer()
            Text(settlement.settledAtDate.smartFormatted)
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
            
        }
    }
    
    // MARK: - Settle Amount
    
    /// Execute settlement with Convex backend
    private func settleAmount(amount: Double, date: Date) async throws {
        guard let clerkId = clerk.user?.id else {
            throw ConvexServiceError.notAuthenticated
        }
        
        let direction = owedToMe ? "from_friend" : "to_friend"
        let settledAtTimestamp = String(Int64(date.timeIntervalSince1970 * 1000))
        
        let _: SettleAmountResponse = try await convexService.client.mutation(
            "transactions:settleAmount",
            with: [
                "clerkId": clerkId,
                "friendId": friend.id,
                "amount": String(amount),
                "currency": userCurrency,
                "direction": direction,
                "settledAt": settledAtTimestamp
            ]
        )
    }
    
    // MARK: - Avatar View
    
    @ViewBuilder
    private func avatarView(size: CGFloat = 40, fontSize: CGFloat = 18) -> some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            // Use cached image if available, otherwise show placeholder while loading
            if let cachedImage = cachedAvatarImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                initialsView(size: size, fontSize: fontSize)
                    .task(id: "\(friend.id)-\(avatarUrl)") {
                        await loadAvatarImage(from: url)
                    }
            }
        } else {
            initialsView(size: size, fontSize: fontSize)
        }
    }
    
    private func loadAvatarImage(from url: URL) async {
        let capturedFriendId = friend.id
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return }
            
            // Only update if we're still showing the same friend
            await MainActor.run {
                guard friend.id == capturedFriendId else { return }
                cachedAvatarImage = uiImage
                
                // Extract dominant color from the loaded image
                if dominantColor == nil, let color = uiImage.dominantColor() {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dominantColor = color
                    }
                }
            }
        } catch {
            // Silently fail - placeholder will remain
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

#Preview("With Activity") {
    PersonDetailSheetPreview.withMixedActivity
}

#Preview("Transactions Only") {
    PersonDetailSheetPreview.transactionsOnly
}

#Preview("Empty State") {
    PersonDetailSheetPreview.emptyState
}

#Preview("User Owes Friend") {
    PersonDetailSheetPreview.userOwesFriend
}

#Preview("With Show Older") {
    PersonDetailSheetPreview.withShowOlder
}

// MARK: - Preview Helpers

private enum PersonDetailSheetPreview {
    // Mock friend
    static let mockFriend = ConvexFriend(
        _id: "friend-1",
        ownerId: "owner",
        linkedUserId: nil,
        name: "Alice Johnson",
        email: "alice@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: true,
        isSelf: false,
        createdAt: Date().timeIntervalSince1970 * 1000
    )
    
    // Mock self (current user)
    static let mockSelf = ConvexFriend(
        _id: "self-1",
        ownerId: "owner",
        linkedUserId: nil,
        name: "Me",
        email: "me@example.com",
        phone: nil,
        avatarUrl: nil,
        isDummy: false,
        isSelf: true,
        createdAt: Date().timeIntervalSince1970 * 1000
    )
    
    // Helper to create timestamps
    static func daysAgo(_ days: Int) -> Double {
        Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60)).timeIntervalSince1970 * 1000
    }
    
    // Mock splits for transactions
    static func mockSplits(friendAmount: Double, userAmount: Double) -> [EnrichedSplit] {
        [
            EnrichedSplit(
                _id: UUID().uuidString,
                transactionId: "tx",
                friendId: mockFriend.id,
                amount: friendAmount,
                percentage: nil,
                createdAt: daysAgo(0),
                friend: mockFriend
            ),
            EnrichedSplit(
                _id: UUID().uuidString,
                transactionId: "tx",
                friendId: mockSelf.id,
                amount: userAmount,
                percentage: nil,
                createdAt: daysAgo(0),
                friend: mockSelf
            )
        ]
    }
    
    // Mock transaction where user paid (friend owes user)
    static func userPaidTransaction(id: String, title: String, emoji: String, amount: Double, daysAgo days: Int, friendOwes: Double) -> EnrichedTransaction {
        EnrichedTransaction(
            _id: id,
            createdById: mockSelf.id,
            paidById: mockSelf.id,
            title: title,
            emoji: emoji,
            description: nil,
            totalAmount: amount,
            currency: "USD",
            splitMethod: "equal",
            receiptFileId: nil,
            items: nil,
            exchangeRates: nil,
            date: daysAgo(days),
            createdAt: daysAgo(days),
            payer: mockSelf,
            splits: mockSplits(
                friendAmount: friendOwes,
                userAmount: amount - friendOwes
            ),
            receiptUrl: nil
        )
    }
    
    // Mock transaction where friend paid (user owes friend)
    static func friendPaidTransaction(id: String, title: String, emoji: String, amount: Double, daysAgo days: Int, userOwes: Double) -> EnrichedTransaction {
        EnrichedTransaction(
            _id: id,
            createdById: mockFriend.id,
            paidById: mockFriend.id,
            title: title,
            emoji: emoji,
            description: nil,
            totalAmount: amount,
            currency: "USD",
            splitMethod: "equal",
            receiptFileId: nil,
            items: nil,
            exchangeRates: nil,
            date: daysAgo(days),
            createdAt: daysAgo(days),
            payer: mockFriend,
            splits: mockSplits(
                friendAmount: amount - userOwes,
                userAmount: userOwes
            ),
            receiptUrl: nil
        )
    }
    
    // Mock settlement
    static func mockSettlement(id: String, amount: Double, daysAgo days: Int, isUserPaying: Bool, balanceBefore: Double? = nil) -> EnrichedSettlement {
        EnrichedSettlement(
            _id: id,
            createdById: isUserPaying ? mockSelf.id : mockFriend.id,
            friendId: mockFriend.id,
            amount: amount,
            currency: "USD",
            direction: isUserPaying ? "to_friend" : "from_friend",
            note: nil,
            balanceBeforeSettlement: balanceBefore,
            exchangeRates: nil,
            settledAt: daysAgo(days),
            createdAt: daysAgo(days),
            convertedAmount: amount,
            convertedCurrency: "USD",
            convertedBalanceBefore: balanceBefore
        )
    }
    
    // MARK: - Preview Configurations
    
    /// Mixed activity with transactions and settlements interleaved
    static var withMixedActivity: some View {
        let transactions = [
            userPaidTransaction(id: "tx1", title: "Dinner at Olive Garden", emoji: "🍝", amount: 85.50, daysAgo: 1, friendOwes: 42.75),
            userPaidTransaction(id: "tx2", title: "Coffee", emoji: "☕️", amount: 12.00, daysAgo: 3, friendOwes: 6.00),
            userPaidTransaction(id: "tx3", title: "Groceries", emoji: "🛒", amount: 120.00, daysAgo: 8, friendOwes: 60.00),
            userPaidTransaction(id: "tx4", title: "Movie tickets", emoji: "🎬", amount: 32.00, daysAgo: 15, friendOwes: 16.00),
        ]
        
        let settlements = [
            mockSettlement(id: "s1", amount: 50.00, daysAgo: 5, isUserPaying: false, balanceBefore: 108.75),
            mockSettlement(id: "s2", amount: 76.00, daysAgo: 12, isUserPaying: false, balanceBefore: 76.00),
        ]
        
        return PersonDetailSheetPreviewWrapper(
            friend: mockFriend,
            balance: BalanceSummary(
                friendOwesUser: 58.75,
                userOwesFriend: 0,
                netBalance: 58.75,
                userCurrency: "USD",
                balancesByCurrency: nil
            ),
            transactions: transactions,
            settlements: settlements
        )
    }
    
    /// Only transactions, no settlements
    static var transactionsOnly: some View {
        let transactions = [
            userPaidTransaction(id: "tx1", title: "Dinner", emoji: "🍽️", amount: 60.00, daysAgo: 1, friendOwes: 30.00),
            userPaidTransaction(id: "tx2", title: "Uber ride", emoji: "🚗", amount: 25.00, daysAgo: 2, friendOwes: 12.50),
            userPaidTransaction(id: "tx3", title: "Drinks", emoji: "🍺", amount: 45.00, daysAgo: 4, friendOwes: 22.50),
        ]
        
        return PersonDetailSheetPreviewWrapper(
            friend: mockFriend,
            balance: BalanceSummary(
                friendOwesUser: 65.00,
                userOwesFriend: 0,
                netBalance: 65.00,
                userCurrency: "USD",
                balancesByCurrency: nil
            ),
            transactions: transactions,
            settlements: []
        )
    }
    
    /// Empty state - all settled
    static var emptyState: some View {
        PersonDetailSheetPreviewWrapper(
            friend: mockFriend,
            balance: BalanceSummary(
                friendOwesUser: 0,
                userOwesFriend: 0,
                netBalance: 0,
                userCurrency: "USD",
                balancesByCurrency: nil
            ),
            transactions: [],
            settlements: []
        )
    }
    
    /// User owes friend
    static var userOwesFriend: some View {
        let transactions = [
            friendPaidTransaction(id: "tx1", title: "Concert tickets", emoji: "🎵", amount: 150.00, daysAgo: 2, userOwes: 75.00),
            friendPaidTransaction(id: "tx2", title: "Brunch", emoji: "🥞", amount: 48.00, daysAgo: 5, userOwes: 24.00),
        ]
        
        return PersonDetailSheetPreviewWrapper(
            friend: mockFriend,
            balance: BalanceSummary(
                friendOwesUser: 0,
                userOwesFriend: 99.00,
                netBalance: -99.00,
                userCurrency: "USD",
                balancesByCurrency: nil
            ),
            transactions: transactions,
            settlements: []
        )
    }
    
    /// With "Show older" button - has recent activity and a full settlement divider
    static var withShowOlder: some View {
        // Recent transactions
        // Settlement that marks the "full settlement" point (amount = balanceBefore)
        // Older transactions (before the full settlement)
        let transactions = [
            // Recent transactions
            userPaidTransaction(id: "tx1", title: "Dinner last night", emoji: "🍝", amount: 60.00, daysAgo: 1, friendOwes: 30.00),
            userPaidTransaction(id: "tx2", title: "Coffee", emoji: "☕️", amount: 12.00, daysAgo: 3, friendOwes: 6.00),
            // Older transactions (before the full settlement)
            userPaidTransaction(id: "tx3", title: "Old groceries", emoji: "🛒", amount: 100.00, daysAgo: 20, friendOwes: 50.00),
            userPaidTransaction(id: "tx4", title: "Old movie", emoji: "🎬", amount: 40.00, daysAgo: 25, friendOwes: 20.00),
            userPaidTransaction(id: "tx5", title: "Old lunch", emoji: "🥗", amount: 30.00, daysAgo: 30, friendOwes: 15.00),
        ]
        
        let settlements = [
            // This settlement at day 10 is a "full settlement" (amount == balanceBefore)
            // This creates the divider between recent and older items
            mockSettlement(id: "s1", amount: 85.00, daysAgo: 10, isUserPaying: false, balanceBefore: 85.00),
        ]
        
        return PersonDetailSheetPreviewWrapper(
            friend: mockFriend,
            balance: BalanceSummary(
                friendOwesUser: 36.00,  // 30 + 6 from recent transactions
                userOwesFriend: 0,
                netBalance: 36.00,
                userCurrency: "USD",
                balancesByCurrency: nil
            ),
            transactions: transactions,
            settlements: settlements
        )
    }
}

/// Wrapper view that injects mock data into PersonDetailSheet
private struct PersonDetailSheetPreviewWrapper: View {
    let friend: ConvexFriend
    let balance: BalanceSummary
    let transactions: [EnrichedTransaction]
    let settlements: [EnrichedSettlement]
    
    var body: some View {
        PersonDetailSheetPreviewContent(
            friend: friend,
            balance: balance,
            transactions: transactions,
            settlements: settlements
        )
    }
}

/// A copy of PersonDetailSheet that uses injected data for previews
private struct PersonDetailSheetPreviewContent: View {
    @Environment(\.dismiss) var dismiss
    
    let friend: ConvexFriend
    let balance: BalanceSummary
    let transactions: [EnrichedTransaction]
    let settlements: [EnrichedSettlement]
    
    @State private var scrollOffset: CGFloat = -74
    @State private var showSettleSheet = false
    @State private var isSettled = false
    @State private var shouldResetSlider = false
    @State private var showOlderItems = false
    @Namespace private var olderItemsNamespace
    
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
    
    // MARK: - Activity Items
    
    private var activityItems: [ActivityItem] {
        var items: [ActivityItem] = []
        
        for transaction in transactions {
            let friendPaid = transaction.paidById == friend.id
            let userPaid = transaction.payer?.isSelf == true
            let txCurrency = transaction.currency
            
            if userPaid {
                if let friendSplit = transaction.splits.first(where: { $0.friendId == friend.id }) {
                    let originalAmount = friendSplit.amount
                    items.append(.transaction(transaction, originalAmount: originalAmount, originalCurrency: txCurrency, isOwed: true))
                }
            }
            
            if friendPaid {
                if let userSplit = transaction.splits.first(where: { $0.friend?.isSelf == true }) {
                    let originalAmount = userSplit.amount
                    items.append(.transaction(transaction, originalAmount: originalAmount, originalCurrency: txCurrency, isOwed: false))
                }
            }
        }
        
        for settlement in settlements {
            items.append(.settlement(settlement))
        }
        
        return items.sorted { $0.sortTimestamp > $1.sortTimestamp }
    }
    
    private var lastFullSettlementIndex: Int? {
        // Find the most recent settlement that cleared the balance (amount ≈ balanceBeforeSettlement)
        for (index, item) in activityItems.enumerated() {
            if case .settlement(let settlement) = item {
                // A "full settlement" is when the amount equals (or nearly equals) the balance before
                if let balanceBefore = settlement.convertedBalanceBefore,
                   abs(settlement.convertedAmount - balanceBefore) < 0.01 {
                    return index
                }
            }
        }
        return nil
    }
    
    private var recentItems: [ActivityItem] {
        guard let dividerIndex = lastFullSettlementIndex else {
            return activityItems
        }
        return Array(activityItems.prefix(dividerIndex))
    }
    
    private var olderItems: [ActivityItem] {
        guard let dividerIndex = lastFullSettlementIndex else {
            return []
        }
        return Array(activityItems.suffix(from: dividerIndex))
    }
    
    // MARK: - Activity Chunk
    
    private enum ActivityChunk: Identifiable {
        case transactionGroup([ActivityItem])
        case settlement(EnrichedSettlement)
        
        var id: String {
            switch self {
            case .transactionGroup(let items):
                return "group-\(items.first?.id ?? UUID().uuidString)"
            case .settlement(let s):
                return "settlement-\(s.id)"
            }
        }
    }
    
    private func chunkActivityItems(_ items: [ActivityItem]) -> [ActivityChunk] {
        var chunks: [ActivityChunk] = []
        var currentTransactionGroup: [ActivityItem] = []
        
        for item in items {
            switch item {
            case .transaction:
                currentTransactionGroup.append(item)
            case .settlement(let settlement):
                if !currentTransactionGroup.isEmpty {
                    chunks.append(.transactionGroup(currentTransactionGroup))
                    currentTransactionGroup = []
                }
                chunks.append(.settlement(settlement))
            }
        }
        
        if !currentTransactionGroup.isEmpty {
            chunks.append(.transactionGroup(currentTransactionGroup))
        }
        
        return chunks
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Header with avatar and amount
                    HStack(spacing: 12) {
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
                    }
                    .opacity(transitionProgress < 0.5 ? 1 : 0)
                    .animation(.smooth(duration: 0.25), value: transitionProgress < 0.5)
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
                        onSlideComplete: { },
                        isConfirmed: $isSettled,
                        shouldReset: $shouldResetSlider
                    )
                    .padding(.horizontal, 20)
                }
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
                    Button("Split") { }
                    .buttonStyle(.glassProminent)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        avatarView(size: 36, fontSize: 14)
                        Text(friend.name)
                    }
                    .opacity(transitionProgress >= 0.5 ? 1 : 0)
                    .animation(.smooth(duration: 0.25), value: transitionProgress >= 0.5)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Views
    
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
    
    private var activityList: some View {
        let recentChunks = chunkActivityItems(recentItems)
        let olderChunks = chunkActivityItems(olderItems)
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(recentChunks) { chunk in
                chunkView(for: chunk)
            }
            
            if !olderItems.isEmpty {
                showOlderButton
            }
            
            if showOlderItems {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(olderChunks) { chunk in
                        chunkView(for: chunk)
                            .opacity(0.7)
                    }
                }
                .transition(.offset(y: -30).combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private func chunkView(for chunk: ActivityChunk) -> some View {
        switch chunk {
        case .transactionGroup(let items):
            transactionGroupView(items: items)
        case .settlement(let settlement):
            settlementRow(settlement: settlement)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func transactionGroupView(items: [ActivityItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                activityRow(for: item)
                
                if index < items.count - 1 {
                    Divider()
                        .padding(.vertical, 16)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.accentSecondary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var showOlderButton: some View {
        Button(action: {
            withAnimation(.smooth(duration: 0.4)) {
                showOlderItems.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Text(showOlderItems ? "Hide older" : "Show older")
                    .font(.subheadline)
                    .contentTransition(.interpolate)
                Image(systemName: showOlderItems ? "chevron.up" : "chevron.down")
                    .font(.subheadline)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "olderItemsToggle", in: olderItemsNamespace)
    }
    
    @ViewBuilder
    private func activityRow(for item: ActivityItem) -> some View {
        switch item {
        case .transaction(let tx, let originalAmount, let originalCurrency, let isOwed):
            NavigationLink {
                SplitDetailView(transaction: tx, userCurrency: userCurrency)
            } label: {
                transactionRow(transaction: tx, originalAmount: originalAmount, originalCurrency: originalCurrency, isOwed: isOwed)
            }
            .buttonStyle(.plain)
        case .settlement(let settlement):
            settlementRow(settlement: settlement)
        }
    }
    
    private func transactionRow(transaction: EnrichedTransaction, originalAmount: Double, originalCurrency: String, isOwed: Bool) -> some View {
        let showOriginalCurrency = originalCurrency != userCurrency
        
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
                Text(transaction.dateValue.smartFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
//                Text(isOwed ? "They owe" : "You owe")
//                    .font(.subheadline)
//                    .foregroundStyle(.text.opacity(0.6))
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: isOwed ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 14))
                        .foregroundStyle(isOwed ? Color.destructive : Color.accent)
                        .frame(width: 17, height: 17)
                        
                    Text(convertedAmount.asCurrency(code: userCurrency))
                        .font(.default)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOwed ? .accent : .appDestructive)
                }
                
                if showOriginalCurrency {
                    Text(originalAmount.asCurrency(code: originalCurrency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text.opacity(0.5))
                }
            }
        }
        .contentShape(Rectangle())
    }
    
    private func settlementRow(settlement: EnrichedSettlement) -> some View {
        HStack(spacing: 4) {
            Image(systemName: settlement.isUserPaying ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 14))
                .foregroundStyle(settlement.isUserPaying ? Color.destructive : Color.accent)
                .frame(width: 24, height: 24)
            HStack(spacing: 0) {
                Text(settlement.isUserPaying ? "-" : "+")
                Text(settlement.formattedConvertedAmount)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(settlement.isUserPaying ? Color.appDestructive : Color.accent)
            if let balanceBefore = settlement.formattedConvertedBalanceBefore {
                Text("out of \(balanceBefore)")
                    .font(.subheadline)
                    .foregroundStyle(.text.opacity(0.6))
            }
            Spacer()
            Text(settlement.settledAtDate.smartFormatted)
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
        }
    }
    
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
