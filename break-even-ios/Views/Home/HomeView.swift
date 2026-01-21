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
    
    private var currentTabData: [FriendWithBalance] {
        selectedTab == .owedToYou ? viewModel.owedToMe : viewModel.iOwe
    }
    
    private var currentTabAmount: Double {
        selectedTab == .owedToYou ? viewModel.totalOwedToMe : viewModel.totalIOwe
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
                .padding(.bottom, 8)
        }
        .background(.background)
        .navigationBarHidden(true)
        .fullScreenCover(item: $splitSheetConfig) { config in
            NewSplitSheet(
                preSelectedFriend: config.preSelectedFriend,
                allFriends: viewModel.allFriends,
                selfFriend: viewModel.selfFriend,
                userDefaultCurrency: viewModel.userCurrency
            )
        }
        .fullScreenCover(item: $receiptScanResult) { result in
            // This fullScreenCover is specifically for receipt scan results
            // Using item: binding ensures the data is properly passed when presenting
            NewSplitSheet(
                receiptResult: result,
                allFriends: viewModel.allFriends,
                selfFriend: viewModel.selfFriend,
                userDefaultCurrency: viewModel.userCurrency
            )
        }
        .fullScreenCover(isPresented: $showReceiptCamera) {
            ReceiptCameraView { result in
                // Small delay to allow camera to dismiss before showing split sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Setting receiptScanResult will automatically present the fullScreenCover
                    receiptScanResult = result
                    
                    // Debug logging
                    print("=== HomeView: Receipt Result Set ===")
                    print("Title: \(result.title)")
                    print("Total: \(result.total)")
                    print("Items: \(result.items.count)")
                    print("====================================")
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
        .onAppear {
            startSubscriptions()
        }
        .onDisappear {
            viewModel.unsubscribe()
        }
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToBalances(clerkId: clerkId)
        viewModel.subscribeToFriends(clerkId: clerkId)
        viewModel.subscribeToUser(clerkId: clerkId)
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
                    // Using sheet(item:) so just setting selectedFriend triggers the sheet
                    selectedFriend = currentTabData.first(where: { $0.friend.id == friend.id })
                }
            )
            .id(selectedTab) // Force re-render and re-animate on tab change
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                // New Split Button
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
                
                // Receipt Scanner Button
                Button {
                    showReceiptCamera = true
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.accent)
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
