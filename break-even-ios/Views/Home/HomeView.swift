//
//  HomeView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

// MARK: - Split Sheet Configuration
/// Identifiable configuration for presenting NewSplitSheet with optional pre-selected friend
struct SplitSheetConfig: Identifiable {
    let id = UUID()
    let preSelectedFriend: ConvexFriend?
}

struct HomeView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel = HomeViewModel()
    @State private var splitSheetConfig: SplitSheetConfig?
    @State private var showReceiptCamera = false
    @State private var selectedTab: OwedTab = .owedToYou
    @State private var selectedFriend: FriendWithBalance?
    @State private var receiptScanResult: ReceiptScanResult?
    @State private var pendingSavedTransactionId: String?
    
    let onOpenTransactionInHistory: ((String) -> Void)?
    
    private var currentTabData: [FriendWithBalance] {
        selectedTab == .owedToYou ? viewModel.owedToMe : viewModel.iOwe
    }
    
    private var currentTabAmount: Double {
        selectedTab == .owedToYou ? viewModel.totalOwedToMe : viewModel.totalIOwe
    }
    
    init(onOpenTransactionInHistory: ((String) -> Void)? = nil) {
        self.onOpenTransactionInHistory = onOpenTransactionInHistory
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("What did you\nspend on today?")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color("Text"))
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            // Tab Selector
            OwedTabSelector(
                selectedTab: $selectedTab,
                owedToYouAmount: viewModel.totalOwedToMe,
                youOweAmount: viewModel.totalIOwe,
                currencyCode: viewModel.userCurrency
            )
            .padding(.horizontal, 20)
            .padding(.top, 24)
            
            // Bubble Cluster View
            bubbleClusterSection
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            // Action Buttons
            actionButtons
                .frame(maxWidth: .infinity)
                .padding(.bottom, 80)
        }
        .background(.background)
        .navigationBarHidden(true)
        .fullScreenCover(item: $splitSheetConfig, onDismiss: handleSplitSheetDismissal) { config in
            NewSplitSheet(
                preSelectedFriend: config.preSelectedFriend,
                allFriends: viewModel.allFriends,
                selfFriend: viewModel.selfFriend,
                userDefaultCurrency: viewModel.userCurrency,
                onSaveSuccess: { transactionId in
                    pendingSavedTransactionId = transactionId
                }
            )
        }
        .fullScreenCover(item: $receiptScanResult, onDismiss: handleSplitSheetDismissal) { result in
            NewSplitSheet(
                receiptResult: result,
                allFriends: viewModel.allFriends,
                selfFriend: viewModel.selfFriend,
                userDefaultCurrency: viewModel.userCurrency,
                onSaveSuccess: { transactionId in
                    pendingSavedTransactionId = transactionId
                }
            )
        }
        .fullScreenCover(isPresented: $showReceiptCamera) {
            ReceiptCameraView { result in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    receiptScanResult = result
                    
                    #if DEBUG
                    print("=== HomeView: Receipt Result Set ===")
                    print("Title: \(result.title), Total: \(result.total), Items: \(result.items.count)")
                    print("====================================")
                    #endif
                }
            }
        }
        .sheet(item: $selectedFriend) { friendWithBalance in
            PersonDetailSheet(
                friend: friendWithBalance.friend,
                balance: BalanceSummary(
                    friendOwesUser: friendWithBalance.friendOwesUser,
                    userOwesFriend: friendWithBalance.userOwesFriend,
                    netBalance: friendWithBalance.netBalance,
                    userCurrency: viewModel.userCurrency,
                    balancesByCurrency: friendWithBalance.balancesByCurrency
                ),
                onStartSplit: { friend in
                    selectedFriend = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitSheetConfig = SplitSheetConfig(preSelectedFriend: friend)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: clerk.user?.id) {
            startSubscriptions()
        }
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToBalances(clerkId: clerkId)
        viewModel.subscribeToFriends(clerkId: clerkId)
        viewModel.subscribeToUser(clerkId: clerkId)
    }
    
    private func handleSplitSheetDismissal() {
        guard let transactionId = pendingSavedTransactionId else { return }
        pendingSavedTransactionId = nil
        onOpenTransactionInHistory?(transactionId)
    }
    
    // MARK: - Bubble Cluster Section
    
    @ViewBuilder
    private var bubbleClusterSection: some View {
        if currentTabData.isEmpty {
            BubbleClusterEmptyView(isOwedToUser: selectedTab == .owedToYou)
        } else {
            BubbleClusterView(
                contacts: currentTabData.map { ($0.friend, abs($0.netBalance)) },
                isOwedToUser: selectedTab == .owedToYou,
                currencyCode: viewModel.userCurrency,
                onPersonTap: { friend in
                    selectedFriend = currentTabData.first(where: { $0.friend.id == friend.id })
                }
            )
            .id(selectedTab)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                Button {
                    splitSheetConfig = SplitSheetConfig(preSelectedFriend: nil)
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("New Split")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .glassEffect(.clear.tint(.accent).interactive())
                }
                
                Button {
                    showReceiptCamera = true
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.text)
                        .frame(width: 56, height: 56)
                        .glassEffect(.clear.tint(.accent.opacity(0.2)).interactive())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView()
    }
}
