//
//  HistoryView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

enum HistoryExternalNavigationRequest: Equatable {
    case transaction(String)
}

struct HistoryView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel: HistoryViewModel
    
    // MARK: - Old search state (commented out -- now managed by CustomTabBar via MainTabView)
    // @State private var isSearchExpanded: Bool = false
    // @FocusState private var isSearchFocused: Bool
    // @Namespace private var searchNamespace
    
    @Binding var searchText: String
    @Binding var isScrolled: Bool
    @Binding var isDetailShowing: Bool
    @Binding var externalNavigationRequest: HistoryExternalNavigationRequest?
    
    @State private var navigationPath = NavigationPath()
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    init(
        searchText: Binding<String>,
        isScrolled: Binding<Bool>,
        isDetailShowing: Binding<Bool>,
        externalNavigationRequest: Binding<HistoryExternalNavigationRequest?> = .constant(nil)
    ) {
        _viewModel = State(initialValue: HistoryViewModel())
        _searchText = searchText
        _isScrolled = isScrolled
        _isDetailShowing = isDetailShowing
        _externalNavigationRequest = externalNavigationRequest
    }
    
    fileprivate init(
        viewModel: HistoryViewModel,
        searchText: Binding<String>,
        isScrolled: Binding<Bool>,
        isDetailShowing: Binding<Bool>,
        externalNavigationRequest: Binding<HistoryExternalNavigationRequest?> = .constant(nil)
    ) {
        _viewModel = State(initialValue: viewModel)
        _searchText = searchText
        _isScrolled = isScrolled
        _isDetailShowing = isDetailShowing
        _externalNavigationRequest = externalNavigationRequest
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.filteredTransactions.isEmpty {
                        if let error = viewModel.error {
                            ContentUnavailableView(
                                "Couldn't Load Transactions",
                                systemImage: "wifi.exclamationmark",
                                description: Text(error)
                            )
                            .frame(minHeight: 400)
                        } else if !viewModel.searchText.isEmpty {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "magnifyingglass",
                                description: Text("No transactions match \"\(viewModel.searchText)\"")
                            )
                            .frame(minHeight: 400)
                        } else {
                            ContentUnavailableView(
                                "No Transactions",
                                systemImage: "clock",
                                description: Text("Your transaction history will appear here")
                            )
                            .frame(minHeight: 400)
                        }
                    } else {
                        transactionsList
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 20
            } action: { _, newValue in
                isScrolled = newValue
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                        Text("Past Splits")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                            
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
            }
            // MARK: - Old search accessory (commented out -- now managed by CustomTabBar)
            // .safeAreaInset(edge: .bottom) {
            //     searchAccessory
            // }
            .task(id: subscriptionKey) {
                startSubscriptions()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
            }
            .onChange(of: externalNavigationRequest) { _, newValue in
                handleExternalNavigation(newValue)
            }
            .navigationDestination(for: String.self) { transactionId in
                TransactionDetailLoader(transactionId: transactionId)
            }
            .safeAreaInset(edge: .bottom) {
                if let error = viewModel.error, !viewModel.transactions.isEmpty {
                    Button {
                        Task {
                            try? await convexService.recoverAuthenticatedSession(
                                clerk: clerk,
                                forceTokenRefresh: true
                            )
                        }
                    } label: {
                        Label(error, systemImage: "arrow.clockwise")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: navigationPath.count) { _, newCount in
            withAnimation(.spring(duration: 0.35)) {
                isDetailShowing = newCount > 0
            }
        }
    }
    
    // MARK: - Transactions List
    
    private var transactionsList: some View {
        let transactions = viewModel.filteredTransactions
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(transactions.enumerated()), id: \.element._id) { index, transaction in
                NavigationLink(value: transaction._id) {
                    SplitHistoryRow(transaction: transaction)
                }
                .buttonStyle(.plain)
                
                if index < transactions.count - 1 {
                    Divider()
                        .padding(.vertical, 12)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToTransactions(clerkId: clerkId)
        viewModel.subscribeToUser(clerkId: clerkId)
    }
    
    private func handleExternalNavigation(_ request: HistoryExternalNavigationRequest?) {
        guard let request else { return }
        
        switch request {
        case .transaction(let transactionId):
            navigationPath = NavigationPath()
            navigationPath.append(transactionId)
        }
        
        externalNavigationRequest = nil
    }
    
    // MARK: - Old Search Accessory (commented out -- now managed by CustomTabBar via MainTabView)
    //
    // @ViewBuilder
    // private var searchAccessory: some View {
    //     GlassEffectContainer(spacing: 20.0) {
    //         HStack {
    //             if isSearchExpanded {
    //                 HStack(spacing: 12) {
    //                     HStack(spacing: 8) {
    //                         Image(systemName: "magnifyingglass")
    //                             .foregroundStyle(.text)
    //
    //                         TextField("Search past splits", text: $viewModel.searchText)
    //                             .focused($isSearchFocused)
    //                             .submitLabel(.search)
    //
    //                         if !viewModel.searchText.isEmpty {
    //                             Button {
    //                                 viewModel.searchText = ""
    //                             } label: {
    //                                 Image(systemName: "xmark.circle.fill")
    //                                     .foregroundStyle(.secondary)
    //                             }
    //                         }
    //                     }
    //                     .padding(.horizontal, 12)
    //                     .padding(.vertical, 12)
    //                     .glassEffect()
    //                     .glassEffectID("searchBar", in: searchNamespace)
    //
    //                     Button(action: {
    //                         withAnimation(.easeInOut(duration: 0.25)) {
    //                             isSearchExpanded = false
    //                             viewModel.searchText = ""
    //                             isSearchFocused = false
    //                         }
    //                     }) {
    //                         Image(systemName: "xmark")
    //                             .font(.system(size: 18, weight: .medium))
    //                             .padding(.vertical, 6)
    //                     }
    //                     .buttonStyle(.glass)
    //                     .glassEffectID("dismissButton", in: searchNamespace)
    //                     .fontWeight(.medium)
    //                 }
    //             } else {
    //                 Button {
    //                     withAnimation(.easeInOut(duration: 0.25)) {
    //                         isSearchExpanded = true
    //                     }
    //                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    //                         isSearchFocused = true
    //                     }
    //                     let generator = UIImpactFeedbackGenerator(style: .light)
    //                     generator.impactOccurred()
    //                 } label: {
    //                     HStack(spacing: 8) {
    //                         Image(systemName: "magnifyingglass")
    //                             .font(.system(size: 14, weight: .medium))
    //                         Text("Search")
    //                             .font(.subheadline)
    //                             .fontWeight(.medium)
    //                     }
    //                     .foregroundStyle(.text)
    //                     .padding(.horizontal, 16)
    //                     .padding(.vertical, 12)
    //                     .glassEffect(.clear.interactive())
    //                     .glassEffectID("searchButton", in: searchNamespace)
    //                 }
    //             }
    //         }
    //         .padding(.horizontal, 16)
    //         .padding(.vertical, 8)
    //         .animation(.easeInOut(duration: 0.25), value: isSearchExpanded)
    //     }
    // }
}

#if DEBUG
#Preview("Populated") {
    let vm = HistoryViewModel()
    vm.transactions = EnrichedTransaction.previewList
    return HistoryView(
        viewModel: vm,
        searchText: .constant(""),
        isScrolled: .constant(false),
        isDetailShowing: .constant(false)
    )
}

#Preview("Empty") {
    HistoryView(
        searchText: .constant(""),
        isScrolled: .constant(false),
        isDetailShowing: .constant(false)
    )
}
#endif
