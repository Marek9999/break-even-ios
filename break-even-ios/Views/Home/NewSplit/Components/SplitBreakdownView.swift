//
//  SplitBreakdownView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

struct SplitBreakdownView: View {
    @Bindable var viewModel: NewSplitViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch viewModel.splitMethod {
            case .equal:
                equalSplitView
            case .unequal:
                unequalSplitView
            case .byParts:
                byPartsSplitView
            case .byItem:
                EmptyView()
            }
        }
    }
    
    // MARK: - Equal Split View
    
    private var equalSplitView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 28) {
            ForEach(viewModel.participants, id: \.id) { friend in
                VStack(spacing: 6) {
                    FriendAvatar(friend: friend, size: 56)
                    Text(viewModel.formattedShare(for: friend))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Unequal Split View
    
    private var unequalSplitView: some View {
        VStack(spacing: 20) {
            unequalSummaryHeader
            
            ForEach(viewModel.participants, id: \.id) { friend in
                UnequalParticipantRow(
                    friend: friend,
                    viewModel: viewModel
                )
            }
        }
    }
    
    private var unequalSummaryHeader: some View {
        let diff = viewModel.unequalSplitDifference
        let assigned = viewModel.assignedTotal
        let total = viewModel.totalAmount
        let isBalanced = abs(diff) < 0.01
        let isOver = diff < -0.01
        
        return HStack {
            Text("\(assigned.asCurrency(code: viewModel.currency)) of \(total.asCurrency(code: viewModel.currency))")
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
            
            Spacer()
            
            if isBalanced {
                Text("\(0.0.asCurrency(code: viewModel.currency)) left")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.text.opacity(0.6))
            } else if isOver {
                Text("\(abs(diff).asCurrency(code: viewModel.currency)) over")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            } else {
                Text("\(diff.asCurrency(code: viewModel.currency)) left")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - By Parts Split View
    
    private var sortedParticipantsWithOpacity: [(friend: ConvexFriend, opacity: Double)] {
        let sorted = viewModel.participants.sorted {
            viewModel.getParts(for: $0) < viewModel.getParts(for: $1)
        }
        let n = Double(sorted.count)
        return sorted.enumerated().map { index, friend in
            let opacity = max(0.15, (n - Double(index)) / n)
            return (friend: friend, opacity: opacity)
        }
    }
    
    private var byPartsSplitView: some View {
        VStack(spacing: 20) {
            byPartsVisualization
            
            VStack(spacing: 6) {
                ForEach(viewModel.participants, id: \.id) { friend in
                    byPartsRow(for: friend)
                }
            }
        }
    }
    
    private var byPartsVisualization: some View {
        HStack(spacing: 4) {
            ForEach(sortedParticipantsWithOpacity, id: \.friend.id) { entry in
                let parts = viewModel.getParts(for: entry.friend)
                ForEach(0..<parts, id: \.self) { _ in
                    Color.clear
                        .frame(height: 48)
                        .glassEffect(
                            .regular.tint(Color.accent.opacity(entry.opacity)),
                            in: ConcentricRectangle(
                                topLeadingCorner: .concentric(minimum: 4),
                                topTrailingCorner: .concentric(minimum: 4),
                                bottomLeadingCorner: .concentric(minimum: 4),
                                bottomTrailingCorner: .concentric(minimum: 4)
                            )
                        )
                }
            }
        }
        .padding(4)
        .containerShape(.rect(cornerRadius: 16))
        .animation(.smooth(duration: 0.3), value: viewModel.totalParts)
    }
    
    private func byPartsRow(for friend: ConvexFriend) -> some View {
        HStack {
            FriendAvatar(friend: friend, size: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline)
                
                Text(viewModel.formattedShare(for: friend))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                let isMinimum = viewModel.getParts(for: friend) <= 1
                
                Button {
                    viewModel.decrementParts(for: friend)
                } label: {
                    Image(systemName: "minus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.text.opacity(isMinimum ? 0.3 : 1.0))
                        .frame(width: 32, height: 32)
                        .glassEffect(.clear.interactive(), in: .circle)
                }
                .disabled(isMinimum)
                
                Text("\(viewModel.getParts(for: friend))")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(minWidth: 30)
                
                Button {
                    viewModel.incrementParts(for: friend)
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.text)
                        .frame(width: 32, height: 32)
                        .glassEffect(.clear.interactive(), in: .circle)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
}

// MARK: - Unequal Participant Row

private struct UnequalParticipantRow: View {
    let friend: ConvexFriend
    @Bindable var viewModel: NewSplitViewModel
    
    @State private var amountText: String = ""
    @FocusState private var isFocused: Bool
    
    private var currencySymbol: String {
        SupportedCurrency.from(code: viewModel.currency)?.symbol ?? "$"
    }
    
    var body: some View {
        HStack(spacing: 10) {
            FriendAvatar(friend: friend, size: 32)
            
            Text(friend.displayName)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            Text(currencySymbol)
                .font(.body)
                .foregroundStyle(.text.opacity(0.6))
            
            TextField(
                viewModel.suggestedPlaceholder(for: friend),
                text: $amountText
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: 100)
            .background(.background.secondary)
            .clipShape(Capsule())
            .focused($isFocused)
            .onChange(of: amountText) { _, newValue in
                if newValue.isEmpty {
                    viewModel.unequalEnteredIds.remove(friend.id)
                    viewModel.setCustomAmount(0, for: friend)
                } else {
                    viewModel.unequalEnteredIds.insert(friend.id)
                    viewModel.setCustomAmount(Double(newValue) ?? 0, for: friend)
                }
            }
            .onAppear {
                let current = viewModel.getCustomAmount(for: friend)
                if viewModel.unequalEnteredIds.contains(friend.id) && current > 0 {
                    amountText = String(format: "%.2f", current)
                }
            }
        }
    }
}

// MARK: - Preview

private enum SplitBreakdownPreviewData {
    static let selfFriend = ConvexFriend(
        _id: "self-1", ownerId: "owner-1", linkedUserId: nil,
        name: "Alex Me", email: "alex@example.com", phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: true, createdAt: 0
    )
    static let friendJane = ConvexFriend(
        _id: "friend-jane", ownerId: "owner-1", linkedUserId: nil,
        name: "Jane Smith", email: "jane@example.com", phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friendBob = ConvexFriend(
        _id: "friend-bob", ownerId: "owner-1", linkedUserId: nil,
        name: "Bob Wilson", email: "bob@example.com", phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friendLisa = ConvexFriend(
        _id: "friend-lisa", ownerId: "owner-1", linkedUserId: nil,
        name: "Lisa Park", email: "lisa@example.com", phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
    static let friendKai = ConvexFriend(
        _id: "friend-kai", ownerId: "owner-1", linkedUserId: nil,
        name: "Kai Chen", email: "kai@example.com", phone: nil,
        avatarUrl: nil, isDummy: false, isSelf: false, createdAt: 0
    )
}

#Preview("Equal Split") {
    let vm = NewSplitViewModel()
    vm.totalAmount = 200.00
    vm.splitMethod = .equal
    vm.participants = [
        SplitBreakdownPreviewData.selfFriend,
        SplitBreakdownPreviewData.friendJane,
        SplitBreakdownPreviewData.friendBob,
        SplitBreakdownPreviewData.friendLisa,
        SplitBreakdownPreviewData.friendKai
    ]
    return SplitBreakdownView(viewModel: vm)
        .padding()
}

#Preview("Unequal Split") {
    let vm = NewSplitViewModel()
    vm.totalAmount = 200.00
    vm.splitMethod = .unequal
    vm.currency = "USD"
    vm.participants = [
        SplitBreakdownPreviewData.selfFriend,
        SplitBreakdownPreviewData.friendJane,
        SplitBreakdownPreviewData.friendBob,
        SplitBreakdownPreviewData.friendLisa,
        SplitBreakdownPreviewData.friendKai
    ]
    return SplitBreakdownView(viewModel: vm)
        .padding()
}

#Preview("By Parts Split") {
    let vm = NewSplitViewModel()
    vm.totalAmount = 180.00
    vm.splitMethod = .byParts
    vm.currency = "USD"
    vm.participants = [
        SplitBreakdownPreviewData.selfFriend,
        SplitBreakdownPreviewData.friendJane,
        SplitBreakdownPreviewData.friendBob
    ]
    vm.partsPerPerson = [
        SplitBreakdownPreviewData.selfFriend.id: 1,
        SplitBreakdownPreviewData.friendJane.id: 2,
        SplitBreakdownPreviewData.friendBob.id: 3
    ]
    return SplitBreakdownView(viewModel: vm)
        .padding()
}
