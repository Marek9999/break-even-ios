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
    @State private var showFriendPicker: Bool = false
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
                                
                                // Friend filter button
                                FriendFilterChip(
                                    selectedFriend: viewModel.selectedFriend,
                                    onTap: { showFriendPicker = true },
                                    onClear: { viewModel.clearFriendFilter() }
                                )
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
                        } else if let friend = viewModel.selectedFriend {
                            ContentUnavailableView(
                                "No Transactions",
                                systemImage: "person.crop.circle",
                                description: Text("No transactions with \(friend.name)")
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
                                    TransactionDetailView(
                                        transaction: transaction,
                                        userCurrency: viewModel.userCurrency
                                    )
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
            .sheet(isPresented: $showFriendPicker) {
                FriendFilterSheet(
                    friends: viewModel.uniqueFriends,
                    selectedFriendId: viewModel.selectedFriendId,
                    onSelect: { friendId in
                        viewModel.selectedFriendId = friendId
                        showFriendPicker = false
                    },
                    onClear: {
                        viewModel.clearFriendFilter()
                        showFriendPicker = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
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

// MARK: - Friend Filter Chip

struct FriendFilterChip: View {
    let selectedFriend: ConvexFriend?
    let onTap: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let friend = selectedFriend {
                    // Show selected friend with avatar
                    FriendAvatarMini(friend: friend)
                    
                    Text(friend.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    // Clear button
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Show "Person" filter button
                    Image(systemName: "person.fill")
                        .font(.caption)
                    Text("Person")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selectedFriend != nil ? .white : .primary)
            .if(selectedFriend == nil) { view in
                view
                    .background(in: Capsule())
                    .glassEffect()
            }
            .if(selectedFriend != nil) { view in
                view.background(Capsule().fill(Color.accentColor))
            }
        }
    }
}

// MARK: - Friend Avatar Mini

struct FriendAvatarMini: View {
    let friend: ConvexFriend
    
    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.accent.opacity(0.8)))
    }
}

// MARK: - Friend Filter Sheet

struct FriendFilterSheet: View {
    let friends: [ConvexFriend]
    let selectedFriendId: String?
    let onSelect: (String) -> Void
    let onClear: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    private var filteredFriends: [ConvexFriend] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // "All Friends" option
                Button {
                    onClear()
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.title3)
                            .foregroundStyle(.accent)
                            .frame(width: 40, height: 40)
                            .background(Color.accent.opacity(0.2))
                            .clipShape(Circle())
                        
                        Text("All Friends")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        if selectedFriendId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                        }
                    }
                }
                .listRowBackground(selectedFriendId == nil ? Color.accent.opacity(0.1) : Color.clear)
                
                // Individual friends
                ForEach(filteredFriends, id: \.id) { friend in
                    Button {
                        onSelect(friend.id)
                    } label: {
                        HStack {
                            FriendAvatarView(friend: friend, size: 40)
                            
                            Text(friend.name)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if selectedFriendId == friend.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                    .listRowBackground(selectedFriendId == friend.id ? Color.accent.opacity(0.1) : Color.clear)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search friends")
            .navigationTitle("Filter by Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Friend Avatar View (for sheet)

struct FriendAvatarView: View {
    let friend: ConvexFriend
    var size: CGFloat = 40
    
    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accent.opacity(0.8)))
    }
}

#Preview {
    HistoryView()
}
