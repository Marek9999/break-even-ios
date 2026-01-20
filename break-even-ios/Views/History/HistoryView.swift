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
    
    @State private var viewModel = HistoryViewModel()
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchNamespace
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Filter Chips and Sort Button
                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                                    FilterChip(
                                        title: filter.rawValue,
                                        isSelected: viewModel.selectedFilter == filter
                                    ) {
                                        viewModel.selectedFilter = filter
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Liquid Glass Sort Button
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
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(in: Circle())
                                .glassEffect()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    // Transactions List
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
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.filteredTransactions, id: \._id) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    SplitHistoryRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Past Splits")
            .navigationBarTitleDisplayMode(.large)
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
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToTransactions(clerkId: clerkId)
    }
    
    // MARK: - Search Accessory
    
    @ViewBuilder
    private var searchAccessory: some View {
        GlassEffectContainer {
            HStack {
                if isSearchExpanded {
                    // Expanded search field
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            
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
                        .matchedGeometryEffect(id: "searchCapsule", in: searchNamespace)
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSearchExpanded = false
                                viewModel.searchText = ""
                                isSearchFocused = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18,weight: .medium))
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .fontWeight(.medium)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
                } else {
                    // Collapsed search button
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
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive())
                        .matchedGeometryEffect(id: "searchCapsule", in: searchNamespace)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.25), value: isSearchExpanded)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .if(!isSelected) { view in
                    view
                        .background(in: Capsule())
                        .glassEffect()
                }
                .if(isSelected) { view in
                    view.background(Capsule().fill(Color.accentColor))
                }
        }
    }
}

// MARK: - View Extension for Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    HistoryView()
}
