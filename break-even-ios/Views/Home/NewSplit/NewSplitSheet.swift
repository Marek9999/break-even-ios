//
//  NewSplitSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk

struct NewSplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel: NewSplitViewModel
    
    // All available friends
    let allFriends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    
    // User's default currency
    let userDefaultCurrency: String
    
    // Receipt data if scanning
    let receiptResult: ReceiptScanResult?
    
    @State private var showPersonPicker = false
    @State private var showSplitMethodPicker = false
    @State private var showPaidByPicker = false
    @State private var showError = false
    
    // MARK: - Initialization
    
    init(
        receiptResult: ReceiptScanResult? = nil,
        preSelectedFriend: ConvexFriend? = nil,
        allFriends: [ConvexFriend] = [],
        selfFriend: ConvexFriend? = nil,
        userDefaultCurrency: String = "USD"
    ) {
        self.receiptResult = receiptResult
        self.allFriends = allFriends
        self.selfFriend = selfFriend
        self.userDefaultCurrency = userDefaultCurrency
        self._viewModel = State(initialValue: NewSplitViewModel(preSelectedFriend: preSelectedFriend, defaultCurrency: userDefaultCurrency))
    }
    
    // Non-self friends for selection
    private var selectableFriends: [ConvexFriend] {
        allFriends.filter { !$0.isSelf }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Emoji and Title Section
                    emojiTitleSection
                    
                    // Amount Section
                    amountSection
                    
                    // Date Section
                    dateSection
                    
                    // Paid By Section
                    paidBySection
                    
                    // Participants Section
                    participantsSection
                    
                    // Split Method Section
                    splitMethodSection
                    
                    // Split Breakdown
                    if !viewModel.participants.isEmpty {
                        SplitBreakdownView(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isLoading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveSplit()
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.isValid)
                    }
                }
            }
            .sheet(isPresented: $showPersonPicker) {
                PersonPickerSheet(
                    friends: selectableFriends,
                    selectedFriends: $viewModel.participants,
                    onDone: { }
                )
            }
            .sheet(isPresented: $showPaidByPicker) {
                PaidByPickerSheet(
                    friends: viewModel.participants,
                    selfFriend: selfFriend,
                    selectedFriend: $viewModel.paidBy
                )
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.error ?? "An error occurred")
            }
            .onAppear {
                setupInitialData()
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupInitialData() {
        // Set default payer to self
        if viewModel.paidBy == nil, let self_ = selfFriend {
            viewModel.paidBy = self_
        }
        
        // Add self to participants if not already
        if let self_ = selfFriend, !viewModel.participants.contains(where: { $0.id == self_.id }) {
            viewModel.addParticipant(self_)
        }
        
        // Apply receipt data if available
        if let receipt = receiptResult {
            viewModel.title = receipt.title.isEmpty ? "Receipt" : receipt.title
            viewModel.totalAmount = receipt.total
            viewModel.emoji = "🧾"
            viewModel.scannedReceiptImage = receipt.image
            
            // Convert receipt items to split items
            viewModel.items = receipt.items.map { item in
                SplitItem(name: item.name, amount: item.amount)
            }
            
            // Always default to "by item" split method when scanning a receipt
            viewModel.splitMethod = .byItem
            
            // Debug logging
            print("=== Receipt Data Applied to ViewModel ===")
            print("Title: \(viewModel.title)")
            print("Total: \(viewModel.totalAmount)")
            print("Items count: \(viewModel.items.count)")
            print("Split method: \(viewModel.splitMethod)")
            print("=========================================")
        }
        
        // Set default currency (already set in ViewModel init, but ensure it's consistent)
        if viewModel.currency.isEmpty {
            viewModel.currency = userDefaultCurrency
        }
    }
    
    // MARK: - Save
    
    private func saveSplit() {
        guard let clerkId = clerk.user?.id else {
            viewModel.error = "Not authenticated"
            showError = true
            return
        }
        
        Task {
            do {
                try await viewModel.save(clerkId: clerkId)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Emoji & Title Section
    
    private var emojiTitleSection: some View {
        VStack(spacing: 12) {
            EmojiTextField(text: $viewModel.emoji)
            
            TextField("What's this for?", text: $viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total Amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Currency selector button
                CurrencyButton(selectedCurrency: $viewModel.currency)
            }
            
            HStack {
                CurrencySymbolView(currencyCode: viewModel.currency)
                
                TextField("0.00", value: $viewModel.totalAmount, format: .number.precision(.fractionLength(2)))
                    .font(.title)
                    .fontWeight(.semibold)
                    .keyboardType(.decimalPad)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Date Section
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                .labelsHidden()
        }
    }
    
    // MARK: - Paid By Section
    
    private var paidBySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paid By")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                showPaidByPicker = true
            } label: {
                HStack {
                    if let payer = viewModel.paidBy {
                        Text(payer.initials)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                        
                        Text(payer.displayName)
                            .font(.body)
                    } else {
                        Text("Select who paid")
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Participants Section
    
    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split Between")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    showPersonPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                }
            }
            
            if viewModel.participants.isEmpty {
                Text("No participants added")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.participants, id: \.id) { friend in
                            ParticipantChip(
                                friend: friend,
                                onRemove: {
                                    viewModel.removeParticipant(friend)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Split Method Section
    
    private var splitMethodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Split Method")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            SplitMethodPicker(selectedMethod: $viewModel.splitMethod)
        }
    }
}

// MARK: - Participant Chip

struct ParticipantChip: View {
    let friend: ConvexFriend
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(friend.initials)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(friend.displayName)
                .font(.subheadline)
            
            if !friend.isSelf {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Paid By Picker Sheet

struct PaidByPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let friends: [ConvexFriend]
    let selfFriend: ConvexFriend?
    @Binding var selectedFriend: ConvexFriend?
    
    private var allOptions: [ConvexFriend] {
        var options = friends
        if let self_ = selfFriend, !options.contains(where: { $0.id == self_.id }) {
            options.insert(self_, at: 0)
        }
        return options
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(allOptions, id: \.id) { friend in
                    Button {
                        selectedFriend = friend
                        dismiss()
                    } label: {
                        HStack {
                            Text(friend.initials)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            
                            Text(friend.displayName)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if selectedFriend?.id == friend.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Who Paid?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview("Empty State") {
    NewSplitSheet(allFriends: [], selfFriend: nil, userDefaultCurrency: "USD")
        .environment(\.convexService, ConvexService.shared)
}
