//
//  ProfileView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile

struct ProfileView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel = ProfileViewModel()
    
    /// Get the display name from Clerk user or fallback
    private var displayName: String {
        if let user = clerk.user {
            if let firstName = user.firstName, !firstName.isEmpty {
                return firstName
            } else if let email = user.primaryEmailAddress?.emailAddress {
                return email
            }
        }
        return viewModel.currentUser?.name ?? "User"
    }
    
    /// Get user initials for avatar
    private var userInitials: String {
        if let user = clerk.user {
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            let firstInitial = firstName.first.map(String.init) ?? ""
            let lastInitial = lastName.first.map(String.init) ?? ""
            if !firstInitial.isEmpty || !lastInitial.isEmpty {
                return "\(firstInitial)\(lastInitial)"
            }
        }
        return "U"
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section - Clerk UserButton
                Section {
                    HStack(spacing: 16) {
                        // Clerk UserButton for profile management
                        UserButton()
                            .frame(width: 60, height: 60)
                        
                        // User Info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.headline)
                            
                            if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Signed In")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Tap your avatar to manage your account or sign out.")
                }
                
                // People Section
                Section {
                    NavigationLink {
                        ContactsListView(friends: viewModel.otherFriends)
                    } label: {
                        HStack {
                            Label("My People", systemImage: "person.2")
                            
                            Spacer()
                            
                            Text("\(viewModel.otherFriends.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button {
                        viewModel.showAddContact = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Add people to split expenses with them.")
                }
                
                // App Section
                Section {
                    // Currency Picker
                    Button {
                        viewModel.showCurrencyPicker = true
                    } label: {
                        HStack {
                            Label("Default Currency", systemImage: "dollarsign.circle")
                            
                            Spacer()
                            
                            if let currencyCode = viewModel.currentUser?.defaultCurrency,
                               let currency = SupportedCurrency.from(code: currencyCode) {
                                HStack(spacing: 6) {
                                    Text(currency.flag)
                                    Text(currency.rawValue)
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Text("USD")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    HStack {
                        Label("Storage", systemImage: "cloud")
                        Spacer()
                        Text("Convex Cloud")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("App Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App")
                } footer: {
                    Text("Your default currency is used to display total balances. Individual splits keep their original currency.")
                }
                
                // Developer Section (for testing)
                #if DEBUG
                Section {
                    // Manual sync button
                    Button {
                        manualSyncUser()
                    } label: {
                        if viewModel.isSyncing {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Syncing...")
                            }
                        } else {
                            Label("Sync User to Convex", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isSyncing)
                    
                    // Seed sample data button
                    Button {
                        seedSampleData()
                    } label: {
                        if viewModel.isSeedingData {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Creating sample data...")
                            }
                        } else {
                            Label("Seed Sample Data", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(viewModel.isSeedingData || viewModel.currentUser == nil)
                } header: {
                    Text("Developer")
                } footer: {
                    if let message = viewModel.syncMessage ?? viewModel.seedMessage {
                        Text(message)
                            .foregroundStyle((viewModel.syncError || viewModel.seedError) ? .red : .green)
                    } else if viewModel.currentUser == nil {
                        Text("User not synced to Convex. Tap 'Sync User' first.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("User synced. You can now seed sample data.")
                    }
                }
                #endif
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $viewModel.showAddContact) {
                AddPersonSheet()
            }
            .sheet(isPresented: $viewModel.showCurrencyPicker) {
                CurrencyPickerSheet(
                    selectedCurrency: Binding(
                        get: { viewModel.currentUser?.defaultCurrency ?? "USD" },
                        set: { newCurrency in
                            updateUserCurrency(to: newCurrency)
                        }
                    )
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
        viewModel.subscribeToFriends(clerkId: clerkId)
        viewModel.subscribeToUser(clerkId: clerkId)
    }
    
    // MARK: - Currency Update
    
    private func updateUserCurrency(to newCurrency: String) {
        guard let clerkId = clerk.user?.id else { return }
        
        Task {
            do {
                let _: String = try await convexService.client.mutation(
                    "users:updateProfile",
                    with: [
                        "clerkId": clerkId,
                        "defaultCurrency": newCurrency
                    ]
                )
                // The subscription will automatically update the UI
            } catch {
                print("Failed to update currency: \(error)")
            }
        }
    }
    
    // MARK: - Developer Functions
    
    #if DEBUG
    private func manualSyncUser() {
        viewModel.isSyncing = true
        viewModel.syncMessage = nil
        viewModel.syncError = false
        
        Task {
            do {
                try await convexService.syncUser(clerk: clerk)
                viewModel.syncMessage = "User synced successfully!"
                viewModel.syncError = false
                // Refresh subscriptions
                startSubscriptions()
            } catch {
                viewModel.syncMessage = "Sync failed: \(error.localizedDescription)"
                viewModel.syncError = true
            }
            viewModel.isSyncing = false
        }
    }
    
    private func seedSampleData() {
        guard let clerkId = clerk.user?.id else {
            viewModel.seedMessage = "Error: Not logged in"
            viewModel.seedError = true
            return
        }
        
        viewModel.isSeedingData = true
        viewModel.seedMessage = nil
        viewModel.seedError = false
        
        Task {
            do {
                let message = try await convexService.seedSampleData(clerkId: clerkId)
                viewModel.seedMessage = message
                viewModel.seedError = false
                // Refresh subscriptions to show new data
                startSubscriptions()
            } catch {
                viewModel.seedMessage = "Error: \(error.localizedDescription)"
                viewModel.seedError = true
            }
            viewModel.isSeedingData = false
        }
    }
    #endif
}

#Preview {
    ProfileView()
}
