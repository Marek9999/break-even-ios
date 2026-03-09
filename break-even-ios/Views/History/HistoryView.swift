//
//  HistoryView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

struct HistoryView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel: HistoryViewModel
    @State private var isSearchExpanded: Bool = false
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    
    init() {
        _viewModel = State(initialValue: HistoryViewModel())
    }
    
    fileprivate init(viewModel: HistoryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.filteredTransactions.isEmpty {
                        if !viewModel.searchText.isEmpty {
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
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                        Text("Past Splits")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
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
            .safeAreaInset(edge: .bottom) {
                searchAccessory
            }
            .onAppear {
                startSubscriptions()
            }
            .onDisappear {
                viewModel.unsubscribe()
            }
        }
    }
    
    // MARK: - Transactions List
    
    private var transactionsList: some View {
        let transactions = viewModel.filteredTransactions
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(transactions.enumerated()), id: \.element._id) { index, transaction in
                NavigationLink {
                    TransactionDetailView(
                        transaction: transaction,
                        userCurrency: viewModel.userCurrency
                    )
                } label: {
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
    
    // MARK: - Search Accessory
    
    @ViewBuilder
    private var searchAccessory: some View {
        GlassEffectContainer(spacing: 20.0) {
            HStack {
                if isSearchExpanded {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.text)
                            
                            TextField("Search past splits", text: $viewModel.searchText)
                                .focused($isSearchFocused)
                                .submitLabel(.search)
                            
                            if !viewModel.searchText.isEmpty {
                                Button {
                                    viewModel.searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .glassEffect()
                        .glassEffectID("searchBar", in: searchNamespace)
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSearchExpanded = false
                                viewModel.searchText = ""
                                isSearchFocused = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("dismissButton", in: searchNamespace)
                        .fontWeight(.medium)
                    }
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearchExpanded = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                            Text("Search")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.clear.interactive())
                        .glassEffectID("searchButton", in: searchNamespace)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.25), value: isSearchExpanded)
        }
    }
}

#Preview("Populated") {
    let vm = HistoryViewModel()
    vm.transactions = EnrichedTransaction.previewList
    return HistoryView(viewModel: vm)
}

#Preview("Empty") {
    HistoryView()
}
