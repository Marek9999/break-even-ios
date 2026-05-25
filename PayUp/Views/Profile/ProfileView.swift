//
//  ProfileView.swift
//  PayUp
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import PhotosUI
import Clerk
import ConvexMobile

enum ProfileExternalNavigationRequest: Equatable {
    case friends
}

private enum ProfileDestination: Hashable {
    case friends
    #if DEBUG
    case shaderTest
    case edgeCurveLab
    #endif
}

struct ProfileView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    @Environment(\.notificationManager) private var notificationManager
    @Environment(\.openURL) private var openURL
    @Environment(\.sessionCoordinator) private var sessionCoordinator
    
    @Binding var isDetailShowing: Bool
    @Binding var externalNavigationRequest: ProfileExternalNavigationRequest?
    let usesProfileSheetChrome: Bool
    let onDismiss: (() -> Void)?
    
    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var navigationPath = NavigationPath()
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var showEditUsername = false
    @State private var editedUsername = ""
    @State private var usernameError: String?
    @State private var showAccountDeletionSheet = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
    #if DEBUG
    @State private var showOnboarding = false
    #endif
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    private var sectionCardBackground: Color {
        Color.historyListBackground
    }
    
    private var displayName: String {
        if let convexName = currentUser?.name, !convexName.isEmpty {
            return convexName
        }
        if let user = clerk.user {
            let first = user.firstName ?? ""
            let last = user.lastName ?? ""
            let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { return full }
            if let email = user.primaryEmailAddress?.emailAddress {
                return email
            }
        }
        return "User"
    }
    
    private var userEmail: String {
        clerk.user?.primaryEmailAddress?.emailAddress
            ?? currentUser?.email
            ?? ""
    }
    
    private var userInitials: String {
        if let user = clerk.user {
            let first = user.firstName?.first.map(String.init) ?? ""
            let last = user.lastName?.first.map(String.init) ?? ""
            if !first.isEmpty || !last.isEmpty { return "\(first)\(last)" }
        }
        return "U"
    }

    private var currentUser: ConvexUser? {
        sessionCoordinator.currentUser
    }

    private let privacyPolicyURL = URL(string: "https://payupsplits.app/privacy")
    private let termsOfServiceURL = URL(string: "https://payupsplits.app/terms")
    
    // MARK: - Body
    
    init(
        isDetailShowing: Binding<Bool> = .constant(false),
        externalNavigationRequest: Binding<ProfileExternalNavigationRequest?> = .constant(nil),
        usesProfileSheetChrome: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        _isDetailShowing = isDetailShowing
        _externalNavigationRequest = externalNavigationRequest
        self.usesProfileSheetChrome = usesProfileSheetChrome
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 24) {
                    if let error = viewModel.error {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    headerSection
                    infoSection
                    cardsSection
                    notificationsSection
                    feedbackSection
                    signOutSection
                    
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(alignment: .top) {
                gradientOverlay
            }
            .toolbar {
                if usesProfileSheetChrome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onDismiss?()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                }
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                profileDestinationView(for: destination)
            }
            .sheet(isPresented: $viewModel.showAddContact) {
                AddPersonSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCompactAdaptation(.sheet)
            }
            .sheet(isPresented: $viewModel.showCurrencyPicker) {
                CurrencyPickerSheet(
                    selectedCurrency: Binding(
                        get: { currentUser?.defaultCurrency ?? "USD" },
                        set: { updateUserCurrency(to: $0) }
                    )
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAccountDeletionSheet) {
                AccountDeletionSheet(
                    isDeleting: isDeletingAccount,
                    errorMessage: accountDeletionError,
                    onCancel: {
                        guard !isDeletingAccount else { return }
                        showAccountDeletionSheet = false
                    },
                    onConfirmDelete: performAccountDeletion
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCompactAdaptation(.sheet)
            }
            .photosPicker(
                isPresented: $viewModel.showPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePickedPhoto(newItem) }
            }
            .fullScreenCover(isPresented: $viewModel.showCamera) {
                OnboardingProfileCameraView { image in
                    Task { await uploadProfileImage(image) }
                }
            }
            .alert("Sign Out?", isPresented: $viewModel.showSignOutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) { performSignOut() }
            } message: {
                Text("Are you sure you want to sign out of your account?")
            }
            .alert("Edit Name", isPresented: $showEditName) {
                TextField("Your name", text: $editedName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveEditedName() }
            } message: {
                Text("Enter your display name")
            }
            .alert("Edit Username", isPresented: $showEditUsername) {
                TextField("username", text: $editedUsername)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveEditedUsername() }
                    .disabled(!usernameEditAllowed)
            } message: {
                if let cooldown = usernameCooldownText {
                    Text(cooldown)
                } else if let error = usernameError {
                    Text(error)
                } else {
                    Text("Enter your new username (3-20 characters, letters, numbers, underscores)")
                }
            }
            #if DEBUG
            .alert("Nuke All Data?", isPresented: $viewModel.showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Nuke It", role: .destructive) { clearAllUserData() }
            } message: {
                Text("This will delete ALL your friends, transactions, and splits. This cannot be undone.")
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingFlowView(onClose: { showOnboarding = false })
            }
            #endif
            .onChange(of: navigationPath.count) { _, newCount in
                withAnimation(.spring(duration: 0.35)) {
                    isDetailShowing = newCount > 0
                }
            }
            .onChange(of: externalNavigationRequest) { _, newValue in
                handleExternalNavigation(newValue)
            }
            .onAppear {
                handleExternalNavigation(externalNavigationRequest)
            }
            .task(id: subscriptionKey) {
                startSubscriptions()
            }
            .task(id: clerk.user?.imageUrl) {
                await viewModel.loadAvatarImage(from: clerk.user?.imageUrl)
            }
        }
    }
    
    // MARK: - Gradient Overlay
    
    @ViewBuilder
    private var gradientOverlay: some View {
        if let color = viewModel.dominantColor {
            LinearGradient(
                colors: [color.opacity(0.15), color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                avatarImageView(size: 100)
                
                Menu {
                    Button {
                        viewModel.showPhotoLibrary = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        viewModel.showCamera = true
                    } label: {
                        Label("Take Picture", systemImage: "camera")
                    }
                    
                    if viewModel.cachedAvatarImage != nil {
                        Button(role: .destructive) {
                            Task { await removeProfileImage() }
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .offset(x: 2, y: 2)
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Avatar Image
    
    @ViewBuilder
    private func avatarImageView(size: CGFloat) -> some View {
        if let cachedImage = viewModel.cachedAvatarImage {
            Image(uiImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if viewModel.isUpdatingPhoto {
                        Circle().fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
        } else {
            Text(userInitials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.accentColor)
                .clipShape(Circle())
                .overlay {
                    if viewModel.isUpdatingPhoto {
                        Circle().fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(spacing: 0) {
            Button {
                editedName = displayName
                showEditName = true
            } label: {
                HStack {
                    Text("User Name")
                        .foregroundStyle(.text.opacity(0.6))
                    Spacer()
                    Text(displayName)
                        .fontWeight(.medium)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.text.opacity(0.4))
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().padding(.horizontal)
            
            Button {
                editedUsername = currentUser?.username ?? ""
                usernameError = nil
                showEditUsername = true
            } label: {
                HStack {
                    Text("Username")
                        .foregroundStyle(.text.opacity(0.6))
                    Spacer()
                    if let displayUsername = currentUser?.displayUsername {
                        Text(displayUsername)
                            .fontWeight(.medium)
                            .font(.body.monospaced())
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                    if usernameEditAllowed {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.text.opacity(0.4))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.text.opacity(0.3))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider().padding(.horizontal)
            infoRow(label: "Email", value: userEmail)
        }
        .background(sectionCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var usernameEditAllowed: Bool {
        guard let changedAt = currentUser?.usernameChangedAt else { return true }
        let hoursSince = (Date().timeIntervalSince1970 * 1000 - changedAt) / (1000 * 60 * 60)
        return hoursSince >= 48
    }
    
    private var usernameCooldownText: String? {
        guard let changedAt = currentUser?.usernameChangedAt else { return nil }
        let hoursSince = (Date().timeIntervalSince1970 * 1000 - changedAt) / (1000 * 60 * 60)
        if hoursSince < 48 {
            let remaining = Int(ceil(48 - hoursSince))
            return "You can change your username again in \(remaining) hour\(remaining == 1 ? "" : "s")"
        }
        return nil
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.text.opacity(0.6))
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
    }
    
    // MARK: - Cards Section
    
    private var cardsSection: some View {
        HStack(spacing: 20) {
            friendsCard
            currencyCard
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: Friends Card
    
    private var friendsCard: some View {
        NavigationLink(value: ProfileDestination.friends) {
            VStack(alignment: .leading, spacing: 12) {
                friendAvatarStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                HStack {
                    Text("My Friends")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    
                    Spacer()
                    
                    Text("\(viewModel.otherFriends.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(sectionCardBackground, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var friendAvatarStack: some View {
        let previews = viewModel.oldestFriendPreviews
        if previews.isEmpty {
            Image(systemName: "person.2.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 40)
        } else {
            HStack(spacing: -10) {
                ForEach(previews, id: \.id) { friend in
                    FriendAvatar(friend: friend, size: 40)
                        .overlay(
                            Circle()
                                .stroke(.background, lineWidth: 2)
                        )
                }
            }
        }
    }
    
    // MARK: Currency Card
    
    private var currencyCard: some View {
        let currencyCode = currentUser?.defaultCurrency ?? "USD"
        let currency = SupportedCurrency.from(code: currencyCode)
        let flag = currency?.flag ?? "🇺🇸"
        
        return Button {
            viewModel.showCurrencyPicker = true
        } label: {
            VStack(spacing: 12) {
                Text(flag)
                    .font(.system(size: 52))
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
                
                HStack {
                    Text("Default Currency")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(sectionCardBackground)
                    
                    currencyGradient(for: currency)
                        .frame(height: 80)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 16
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
    
    private func currencyGradient(for currency: SupportedCurrency?) -> some View {
        let color: Color = {
            switch currency {
            case .USD: return .blue
            case .EUR: return .indigo
            case .GBP: return .purple
            case .CAD: return .red
            case .AUD: return .green
            case .INR: return .orange
            case .JPY: return .red
            case .none: return .blue
            }
        }()
        
        return LinearGradient(
            colors: [color.opacity(0.1), color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Notifications Section
    
    private var notificationsSection: some View {
        VStack(spacing: 0) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: notificationToggleBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity Notifications")
                            .fontWeight(.medium)
                            .foregroundStyle(.text)
                        
                        Text(notificationManager.notificationDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(notificationManager.isUpdatingPreference || clerk.user == nil)
                
                if notificationManager.shouldShowSettingsPrompt {
                    Button("Open iPhone Settings") {
                        notificationManager.openSystemSettings()
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                
                if let lastErrorMessage = notificationManager.lastErrorMessage,
                   !lastErrorMessage.isEmpty {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(sectionCardBackground, in: RoundedRectangle(cornerRadius: 20))
        }
    }
    
    private var notificationToggleBinding: Binding<Bool> {
        Binding(
            get: { notificationManager.notificationsEnabled },
            set: { newValue in
                Task {
                    await notificationManager.updatePreference(isEnabled: newValue)
                }
            }
        )
    }
    
    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(spacing: 0) {
            Text("Feedback")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            Button {
                if let url = URL(string: "mailto:createplus.club@gmail.com") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Text("Contact Us")
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(sectionCardBackground, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Sign Out Section
    
    private var signOutSection: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.showSignOutConfirmation = true
            } label: {
                Text("Sign Out")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appDestructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appDestructive.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                legalLinkButton("Privacy Policy") {
                    if let privacyPolicyURL {
                        openURL(privacyPolicyURL)
                    }
                }

                legalLinkButton("Terms of Service") {
                    if let termsOfServiceURL {
                        openURL(termsOfServiceURL)
                    }
                }

                legalLinkButton("Delete Account", destructive: true) {
                    accountDeletionError = nil
                    showAccountDeletionSheet = true
                }
            }
        }
        .padding(.top, 20)
    }

    private func legalLinkButton(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(destructive ? Color.appDestructive : Color.text.opacity(0.65))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - DEBUG Section
    
    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: 0) {
            Text("Developer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                NavigationLink(value: ProfileDestination.shaderTest) {
                    debugRow(label: "Scan Beam Shader Test", icon: "wand.and.rays")
                }
                
                Divider().padding(.leading, 16)
                
                NavigationLink(value: ProfileDestination.edgeCurveLab) {
                    debugRow(label: "Edge Curve Lab", icon: "chart.line.uptrend.xyaxis")
                }
                
                Divider().padding(.leading, 16)
                
                Button { showOnboarding = true } label: {
                    debugRow(label: "Run Onboarding", icon: "sparkles")
                }
                
                Divider().padding(.leading, 16)
                
                Button { manualSyncUser() } label: {
                    if viewModel.isSyncing {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Syncing...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Sync User to Convex", icon: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(viewModel.isSyncing)
                
                Divider().padding(.leading, 16)
                
                Button { seedSampleData() } label: {
                    if viewModel.isSeedingData {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Creating sample data...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Seed Sample Data", icon: "wand.and.stars")
                    }
                }
                .disabled(viewModel.isSeedingData || currentUser == nil)
                
                Divider().padding(.leading, 16)
                
                Button { viewModel.showClearConfirmation = true } label: {
                    if viewModel.isClearingData {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Clearing data...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Nuke All Data", icon: "trash.fill", destructive: true)
                    }
                }
                .disabled(viewModel.isClearingData || currentUser == nil)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            
            if let message = viewModel.clearMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.clearError ? .red : .green)
                    .padding(.top, 6)
            } else if let message = viewModel.syncMessage ?? viewModel.seedMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle((viewModel.syncError || viewModel.seedError) ? .red : .green)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 10)
    }
    
    private func debugRow(label: String, icon: String, destructive: Bool = false) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(destructive ? .red : .text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    #endif
    
    // MARK: - Navigation Destinations
    
    @ViewBuilder
    private func profileDestinationView(for destination: ProfileDestination) -> some View {
        switch destination {
        case .friends:
            ContactsListView(viewModel: viewModel)
        #if DEBUG
        case .shaderTest:
            ShaderTestView()
        case .edgeCurveLab:
            EdgeCurveLabView()
        #endif
        }
    }

    private func handleExternalNavigation(_ request: ProfileExternalNavigationRequest?) {
        guard let request else { return }

        switch request {
        case .friends:
            navigationPath = NavigationPath()
            navigationPath.append(ProfileDestination.friends)
        }

        externalNavigationRequest = nil
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToFriends(clerkId: clerkId)
        viewModel.subscribeToInvitations(clerkId: clerkId)
        viewModel.subscribeToReceivedInvitations(clerkId: clerkId)
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
            } catch {
                #if DEBUG
                print("Failed to update currency: \(error)")
                #endif
            }
        }
    }
    
    private func saveEditedName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let clerkId = clerk.user?.id else { return }
        Task {
            do {
                // Split into first/last for Clerk (first word = first name, rest = last name)
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                let firstName = String(parts.first ?? Substring(trimmed))
                let lastName = parts.count > 1 ? String(parts[1]) : ""

                let _ = try await clerk.user?.update(.init(firstName: firstName, lastName: lastName))

                try await viewModel.updateProfile(
                    clerkId: clerkId,
                    name: trimmed,
                    phone: nil,
                    defaultCurrency: nil
                )
            } catch {
                #if DEBUG
                print("Failed to update name: \(error)")
                #endif
            }
        }
    }
    
    private func saveEditedUsername() {
        let trimmed = editedUsername.lowercased().trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let clerkId = clerk.user?.id else { return }
        
        Task {
            do {
                let _: SetUsernameResponse = try await convexService.client.mutation(
                    "users:setUsername",
                    with: [
                        "clerkId": clerkId,
                        "username": trimmed,
                    ]
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                await MainActor.run {
                    usernameError = error.localizedDescription
                    showEditUsername = true
                }
            }
        }
    }
    
    // MARK: - Photo Actions
    
    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        await uploadProfileImage(uiImage)
    }
    
    private func uploadProfileImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        viewModel.isUpdatingPhoto = true
        do {
            let _ = try await clerk.user?.setProfileImage(imageData: imageData)
            try await convexService.syncUser(clerk: clerk)
            await viewModel.loadAvatarImage(from: clerk.user?.imageUrl)
        } catch {
            #if DEBUG
            print("Failed to upload profile image: \(error)")
            #endif
        }
        viewModel.isUpdatingPhoto = false
    }
    
    private func removeProfileImage() async {
        viewModel.isUpdatingPhoto = true
        do {
            let _ = try await clerk.user?.deleteProfileImage()
            try await convexService.syncUser(clerk: clerk)
            viewModel.cachedAvatarImage = nil
            withAnimation { viewModel.dominantColor = nil }
        } catch {
            #if DEBUG
            print("Failed to remove profile image: \(error)")
            #endif
        }
        viewModel.isUpdatingPhoto = false
    }
    
    // MARK: - Sign Out
    
    private func performSignOut() {
        Task {
            do {
                if let clerkId = clerk.user?.id {
                    await notificationManager.prepareForSignOut(clerkId: clerkId)
                }
                try await clerk.signOut()
            } catch {
                #if DEBUG
                print("Failed to sign out: \(error)")
                #endif
            }
        }
    }

    private func performAccountDeletion() {
        guard let clerkId = clerk.user?.id, let clerkUser = clerk.user else {
            accountDeletionError = "We could not find an active account to delete. Please sign in again and retry."
            return
        }

        isDeletingAccount = true
        accountDeletionError = nil

        Task { @MainActor in
            do {
                await notificationManager.prepareForSignOut(clerkId: clerkId)

                let _: DeleteAccountResponse = try await convexService.client.mutation(
                    "users:deleteAccount",
                    with: [
                        "clerkId": clerkId,
                        "confirmationText": "DELETE_MY_PAYUP_ACCOUNT"
                    ]
                )

                let _ = try await clerkUser.delete()
                await convexService.signOut()
                sessionCoordinator.stopCurrentUserSubscription(clearData: true)

                isDeletingAccount = false
                showAccountDeletionSheet = false
            } catch {
                isDeletingAccount = false
                accountDeletionError = "We couldn't delete your account. Please check your connection and try again."

                #if DEBUG
                print("Failed to delete account: \(error)")
                #endif
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
                startSubscriptions()
            } catch {
                viewModel.seedMessage = "Error: \(error.localizedDescription)"
                viewModel.seedError = true
            }
            viewModel.isSeedingData = false
        }
    }
    
    private func clearAllUserData() {
        guard let clerkId = clerk.user?.id else {
            viewModel.clearMessage = "Error: Not logged in"
            viewModel.clearError = true
            return
        }
        
        viewModel.isClearingData = true
        viewModel.clearMessage = nil
        viewModel.clearError = false
        viewModel.seedMessage = nil
        viewModel.syncMessage = nil
        
        Task {
            do {
                struct ClearResult: Codable {
                    let message: String
                    let deleted: DeletedCounts
                    struct DeletedCounts: Codable {
                        let friends: Int
                        let transactions: Int
                        let splits: Int
                    }
                }
                
                let result: ClearResult = try await convexService.client.mutation(
                    "seed:clearUserData",
                    with: ["clerkId": clerkId]
                )
                
                viewModel.clearMessage = "Nuked: \(result.deleted.friends) friends, \(result.deleted.transactions) transactions, \(result.deleted.splits) splits"
                viewModel.clearError = false
                startSubscriptions()
            } catch {
                viewModel.clearMessage = "Error: \(error.localizedDescription)"
                viewModel.clearError = true
            }
            viewModel.isClearingData = false
        }
    }
    #endif
}

private struct DeleteAccountResponse: Decodable {
    let success: Bool
}

private struct AccountDeletionSheet: View {
    let isDeleting: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirmDelete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Text("⚠️")
                .font(.system(size: 72))
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Delete your PayUp account?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("This action is not reversible. Your PayUp profile, friends, invitations, expense records, settlements, receipt images, activity history, and notification device records will be permanently deleted. Shared records that other people need to keep may show you as a deleted user.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.appDestructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Go Back")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(Capsule())
                    .glassEffect(.clear.tint(.white.opacity(isDeleting ? 0.45 : 0.9)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)

                HoldToDeleteAccountButton(
                    isDeleting: isDeleting,
                    onConfirmDelete: onConfirmDelete
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct HoldToDeleteAccountButton: View {
    let isDeleting: Bool
    let onConfirmDelete: () -> Void

    @State private var isHolding = false
    @State private var didCompleteHold = false
    @State private var remainingSeconds = 5
    @State private var holdTask: Task<Void, Never>?

    private var countdownText: String {
        if isDeleting {
            return "Deleting your account..."
        }

        if isHolding {
            return "Keep holding for \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")"
        }

        return "Hold for 5 seconds to confirm"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(countdownText)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(isHolding ? Color.appDestructive : .secondary)
                .monospacedDigit()

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.appDestructive.opacity(isHolding ? 0.24 : 0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.appDestructive.opacity(isHolding ? 0.7 : 0.35), lineWidth: 1)
                    }

                HStack(spacing: 10) {
                    if isDeleting {
                        ProgressView()
                            .tint(Color.appDestructive)
                    } else {
                        Image(systemName: isHolding ? "hand.raised.fill" : "trash.fill")
                    }

                    Text(isDeleting ? "Deleting Account" : "Hold to Delete Account")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.appDestructive)
            }
            .frame(height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startHoldingIfNeeded() }
                    .onEnded { _ in cancelHoldingIfNeeded() }
            )
            .allowsHitTesting(!isDeleting)
        }
        .onDisappear {
            cancelHoldingIfNeeded()
        }
    }

    private func startHoldingIfNeeded() {
        guard !isDeleting, !isHolding else { return }

        isHolding = true
        didCompleteHold = false
        remainingSeconds = 5

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(5)

            while !Task.isCancelled {
                let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                remainingSeconds = remaining

                if remaining <= 0 {
                    didCompleteHold = true
                    isHolding = false
                    holdTask = nil
                    onConfirmDelete()
                    return
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func cancelHoldingIfNeeded() {
        guard !didCompleteHold else { return }

        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        remainingSeconds = 5
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}
